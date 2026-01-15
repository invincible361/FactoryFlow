import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart' as uuid;
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../main.dart';
import '../ui_components/navigation_home_screen.dart';
import '../app_theme.dart';

class ProductionEntryScreen extends StatefulWidget {
  final Employee employee;
  const ProductionEntryScreen({super.key, required this.employee});

  @override
  State<ProductionEntryScreen> createState() => _ProductionEntryScreenState();
}

class _ProductionEntryScreenState extends State<ProductionEntryScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final LocationService _locationService = LocationService();
  final AttendanceService _attendanceService = AttendanceService();

  Machine? _selectedMachine;
  Item? _selectedItem;
  String? _selectedOperation;
  final List<Map<String, String?>> _extraEntries = [];

  bool _isSaving = false;
  bool _showPdf = false;

  // Data State
  List<Machine> _machines = [];
  List<Item> _items = [];
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoadingData = true;
  List<Map<String, dynamic>> _shifts = [];
  String? _selectedShift;

  // Location State
  Position? _currentPosition;
  String _locationStatus = 'Checking location...';
  bool _isLocationLoading = false;
  bool? _isInside; // Track inside/outside state more robustly

  // Timer State
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  bool _isTimerRunning = false;
  String? _currentLogId;
  String? _activeAssignmentId;
  RealtimeChannel? _assignmentSubscription;

  // Notifiers for lag optimization
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier<DateTime>(
    TimeUtils.nowIst(),
  );
  final ValueNotifier<Duration> _elapsedTimeNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  Timer? _uiUpdateTimer;

  final List<Color> _lightColors = [
    const Color(0xFFE3F2FD), // Light Blue
    const Color(0xFFF1F8E9), // Light Green
    const Color(0xFFFFF3E0), // Light Orange
    const Color(0xFFF3E5F5), // Light Purple
    const Color(0xFFE0F2F1), // Light Teal
    const Color(0xFFFFFDE7), // Light Yellow
    const Color(0xFFFFEBEE), // Light Red
    const Color(0xFFE8EAF6), // Light Indigo
  ];

  final List<Color> _darkColors = [
    const Color(0xFF1A237E), // Dark Indigo
    const Color(0xFF1B5E20), // Dark Green
    const Color(0xFFE65100), // Dark Orange
    const Color(0xFF4A148C), // Dark Purple
    const Color(0xFF004D40), // Dark Teal
    const Color(0xFF33691E), // Dark Light Green
    const Color(0xFFB71C1C), // Dark Red
    const Color(0xFF01579B), // Dark Blue
  ];

  Color _getRandomColor(String seed, bool isDark) {
    final random = math.Random(seed.hashCode);
    final colors = isDark ? _darkColors : _lightColors;
    return colors[random.nextInt(colors.length)];
  }

  Widget _metricTile(String title, String value, Color color, IconData icon) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final bgColor = _getRandomColor(title, isDark);

        // Adjust the icon/accent color for dark mode if it's too light
        final accentColor = isDark ? _getContrastColor(color) : color;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : AppTheme.grey.withValues(alpha: 0.05),
                offset: const Offset(1.1, 1.1),
                blurRadius: 10.0,
              ),
            ],
          ),
          padding: EdgeInsets.all(isLandscape ? 8 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: isLandscape ? 18 : 22,
                ),
              ),
              SizedBox(width: isLandscape ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isLandscape ? 10 : 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.white
                            : AppTheme.grey.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isLandscape ? 12 : 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.darkText,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getContrastColor(Color color) {
    // If color is too light, return a lighter version or white for dark mode
    // If it's a shade100, we should probably use shade400 or just the base color
    if (color.computeLuminance() < 0.5) {
      return color; // Already dark enough
    }
    // Try to get a more vibrant version for dark mode
    return HSVColor.fromColor(
      color,
    ).withValue(0.9).withSaturation(0.4).toColor();
  }

  int _extraUnitsToday = 0;

  Future<void> _fetchTodayExtraUnits() async {
    try {
      final now = TimeUtils.nowUtc();
      final dayFrom = DateTime(now.year, now.month, now.day);
      final response = await Supabase.instance.client
          .from('production_logs')
          .select('performance_diff, created_at')
          .eq('worker_id', widget.employee.id)
          .eq('organization_code', widget.employee.organizationCode ?? '')
          .gte('created_at', dayFrom.toIso8601String());
      int sum = 0;
      for (final l in List<Map<String, dynamic>>.from(response)) {
        final diff = (l['performance_diff'] ?? 0) as int;
        if (diff > 0) sum += diff;
      }
      if (mounted) setState(() => _extraUnitsToday = sum);
    } catch (e) {
      debugPrint('Fetch extra units today error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestNotificationPermissions();
    _loadPersistedState();
    _fetchData();
    _fetchAssignments();
    _subscribeToAssignments();
    _setupLocationListeners();
    _fetchTodayExtraUnits();
    // Start a UI update timer to refresh time-based notifiers without full screen setState
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _currentTimeNotifier.value = TimeUtils.nowIst();
      if (_isTimerRunning && _startTime != null) {
        _elapsed = TimeUtils.nowUtc().difference(_startTime!.toUtc());
        _elapsedTimeNotifier.value = _elapsed;

        // Explicitly trigger a rebuild of the current frame if it's not happening
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        _elapsedTimeNotifier.notifyListeners();

        // Check shift end every 10 seconds while timer is running in foreground
        if (timer.tick % 10 == 0) {
          _checkShiftEndForeground();
        }
      }
    });
  }

  Future<void> _fetchAssignments() async {
    try {
      final response = await Supabase.instance.client
          .from('work_assignments')
          .select()
          .eq('worker_id', widget.employee.id)
          .eq('organization_code', widget.employee.organizationCode!)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _assignments = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching assignments: $e');
    }
  }

  void _subscribeToAssignments() {
    debugPrint(
      'Subscribing to work assignments for worker: ${widget.employee.id}',
    );
    _assignmentSubscription = Supabase.instance.client
        .channel('public:work_assignments:worker_id=${widget.employee.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'work_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'worker_id',
            value: widget.employee.id,
          ),
          callback: (payload) {
            debugPrint(
              'New assignment received via Realtime: ${payload.newRecord}',
            );
            _fetchAssignments();

            final assignment = payload.newRecord;
            final assignmentId =
                assignment['id']?.toString() ??
                TimeUtils.nowUtc().millisecondsSinceEpoch.toString();
            // Use a unique but stable notification ID
            final notificationId = assignmentId.hashCode;

            NotificationService.showNotification(
              id: notificationId,
              title: "New Work Assigned",
              body:
                  "A supervisor has assigned new work to you. Check the 'Pending Assignments' section.",
            );
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('Realtime subscription error: $error');
          }
          debugPrint('Realtime subscription status: $status');
        });
  }

  void _applyAssignment(Map<String, dynamic> assignment) {
    setState(() {
      try {
        _selectedMachine = _machines.firstWhere(
          (m) => m.id == assignment['machine_id'],
        );
        _selectedItem = _items.firstWhere((i) => i.id == assignment['item_id']);
        _selectedOperation = assignment['operation'];
        _activeAssignmentId = assignment['id'].toString();

        // Auto-set shift based on current time
        final detectedShift = _findShiftByTime(TimeUtils.nowIst());
        if (detectedShift.isNotEmpty) {
          _selectedShift = detectedShift['name'];
        } else {
          // Fallback or keep existing selection
          _selectedShift ??= 'General';
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Assignment applied')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error applying assignment: Machine or Item not found',
            ),
          ),
        );
      }
    });
  }

  Future<void> _requestNotificationPermissions() async {
    await NotificationService.requestPermissions();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final machineId = prefs.getString('persisted_machine_id');
      final itemId = prefs.getString('persisted_item_id');
      final operation = prefs.getString('persisted_operation');
      final shift = prefs.getString('persisted_shift');
      final startTimeStr = prefs.getString('persisted_start_time');
      final startTimeMs = prefs.getInt('persisted_start_time_ms');
      final currentLogId = prefs.getString('persisted_current_log_id');
      final isTimerRunning =
          prefs.getBool('persisted_is_timer_running') ?? false;
      final activeAssignmentId = prefs.getString(
        'persisted_active_assignment_id',
      );
      final extraEntriesJson = prefs.getString('persisted_extra_entries');

      if (mounted) {
        setState(() {
          _activeAssignmentId = activeAssignmentId;
          if (extraEntriesJson != null) {
            try {
              final List<dynamic> decoded = jsonDecode(extraEntriesJson);
              _extraEntries.clear();
              _extraEntries.addAll(
                decoded.map((e) => Map<String, String?>.from(e)),
              );
            } catch (e) {
              debugPrint('Error decoding extra entries: $e');
            }
          }
          if (machineId != null && _machines.isNotEmpty) {
            try {
              _selectedMachine = _machines.firstWhere((m) => m.id == machineId);
            } catch (_) {}
          }
          if (itemId != null && _items.isNotEmpty) {
            try {
              _selectedItem = _items.firstWhere((i) => i.id == itemId);
            } catch (_) {}
          }
          _selectedOperation = operation;
          _selectedShift = shift;
          if (currentLogId != null && currentLogId.startsWith('log_')) {
            // Migration: Old format log IDs are not valid UUIDs.
            // We clear it to avoid Supabase errors.
            prefs.remove('persisted_current_log_id');
          } else {
            _currentLogId = currentLogId;
          }

          if (isTimerRunning && (startTimeMs != null || startTimeStr != null)) {
            if (startTimeMs != null) {
              _startTime = DateTime.fromMillisecondsSinceEpoch(
                startTimeMs,
              ).toLocal();
            } else {
              _startTime = TimeUtils.parseToLocal(startTimeStr);
            }
            _isTimerRunning = true;
            _resumeTimer();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading persisted state: $e');
    }
  }

  void _resumeTimer() {
    setState(() {
      _isTimerRunning = true;
      if (_startTime != null) {
        _elapsed = TimeUtils.nowUtc().difference(_startTime!.toUtc());
        _elapsedTimeNotifier.value = _elapsed;
      }
    });
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedMachine != null) {
        await prefs.setString('persisted_machine_id', _selectedMachine!.id);
      } else {
        await prefs.remove('persisted_machine_id');
      }

      if (_selectedItem != null) {
        await prefs.setString('persisted_item_id', _selectedItem!.id);
      } else {
        await prefs.remove('persisted_item_id');
      }

      if (_selectedOperation != null) {
        await prefs.setString('persisted_operation', _selectedOperation!);
      } else {
        await prefs.remove('persisted_operation');
      }

      if (_selectedShift != null) {
        await prefs.setString('persisted_shift', _selectedShift!);
      } else {
        await prefs.remove('persisted_shift');
      }

      await prefs.setBool('persisted_is_timer_running', _isTimerRunning);
      if (_startTime != null) {
        await prefs.setString(
          'persisted_start_time',
          _startTime!.toIso8601String(),
        );
        await prefs.setInt(
          'persisted_start_time_ms',
          _startTime!.millisecondsSinceEpoch,
        );
      } else {
        await prefs.remove('persisted_start_time');
        await prefs.remove('persisted_start_time_ms');
      }

      if (_currentLogId != null) {
        await prefs.setString('persisted_current_log_id', _currentLogId!);
      } else {
        await prefs.remove('persisted_current_log_id');
      }

      if (_activeAssignmentId != null) {
        await prefs.setString(
          'persisted_active_assignment_id',
          _activeAssignmentId!,
        );
      } else {
        await prefs.remove('persisted_active_assignment_id');
      }

      // Persist extra entries
      if (_extraEntries.isNotEmpty) {
        await prefs.setString(
          'persisted_extra_entries',
          jsonEncode(_extraEntries),
        );
      } else {
        await prefs.remove('persisted_extra_entries');
      }
    } catch (e) {
      debugPrint('Error persisting state: $e');
    }
  }

  Future<void> _clearPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('persisted_machine_id');
      await prefs.remove('persisted_item_id');
      await prefs.remove('persisted_operation');
      await prefs.remove('persisted_shift');
      await prefs.remove('persisted_is_timer_running');
      await prefs.remove('persisted_start_time');
      await prefs.remove('persisted_start_time_ms');
      await prefs.remove('persisted_active_assignment_id');
      await prefs.remove('persisted_extra_entries');
    } catch (e) {
      debugPrint('Error clearing persisted state: $e');
    }
  }

  Future<void> _fetchData() async {
    try {
      final supabase = Supabase.instance.client;

      // Fetch Machines
      final machinesResponse = await supabase
          .from('machines')
          .select()
          .eq('organization_code', widget.employee.organizationCode!)
          .order('name', ascending: true);
      final machinesList = (machinesResponse as List).map((data) {
        return Machine(
          id: data['machine_id'],
          name: data['name'],
          type: (data['type'] ?? '').toString().toUpperCase(),
          items: [],
        );
      }).toList();

      // Fetch Items
      final itemsResponse = await supabase
          .from('items')
          .select()
          .eq('organization_code', widget.employee.organizationCode!)
          .order('name', ascending: true);
      final itemsList = (itemsResponse as List).map((data) {
        return Item(
          id: data['item_id'],
          name: data['name'],
          operations: List<String>.from(data['operations'] ?? []),
          operationDetails: (data['operation_details'] as List? ?? [])
              .map((od) => OperationDetail.fromJson(od))
              .toList(),
        );
      }).toList();

      final shiftsResponse = await supabase
          .from('shifts')
          .select()
          .eq('organization_code', widget.employee.organizationCode!)
          .order('name', ascending: true);

      // Deduplicate shifts by name to prevent dropdown crashes
      final List<Map<String, dynamic>> shiftsList = [];
      final Set<String> shiftNames = {};
      for (var s in (shiftsResponse as List)) {
        final name = s['name']?.toString() ?? '';
        if (name.isNotEmpty && !shiftNames.contains(name)) {
          shiftNames.add(name);
          shiftsList.add(Map<String, dynamic>.from(s));
        }
      }

      if (mounted) {
        setState(() {
          _machines = machinesList;
          _items = itemsList;
          _shifts = shiftsList;
          _isLoadingData = false;

          // Attempt to restore selections from persisted state if not already set
          if (_selectedMachine == null || _selectedItem == null) {
            _loadPersistedState();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
        setState(() => _isLoadingData = false);
      }
    }
  }

  void _setupLocationListeners() {
    // Sync initial values
    if (mounted) {
      setState(() {
        _isInside = NavigationHomeScreen.isInsideNotifier.value;
        _currentPosition = NavigationHomeScreen.currentPositionNotifier.value;
        _locationStatus = NavigationHomeScreen.locationStatusNotifier.value;
        _isLocationLoading = false;
      });
    }

    // Listen for changes
    NavigationHomeScreen.isInsideNotifier.addListener(_onLocationChanged);
    NavigationHomeScreen.currentPositionNotifier.addListener(
      _onPositionChanged,
    );
    NavigationHomeScreen.locationStatusNotifier.addListener(
      _onLocationStatusChanged,
    );
  }

  void _onPositionChanged() {
    if (mounted) {
      setState(() {
        _currentPosition = NavigationHomeScreen.currentPositionNotifier.value;
      });
    }
  }

  void _onLocationChanged() {
    if (mounted) {
      final isInside = NavigationHomeScreen.isInsideNotifier.value;
      setState(() {
        _isInside = isInside;
      });

      // Show warning if worker leaves factory while production is running
      if (_isTimerRunning && isInside == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'WARNING: You have left the factory while production is active! This has been logged as a violation.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _onLocationStatusChanged() {
    if (mounted) {
      setState(() {
        _locationStatus = NavigationHomeScreen.locationStatusNotifier.value;
        _isLocationLoading = false;
      });
    }
  }

  Future<void> _manualRefreshLocation() async {
    setState(() => _isLocationLoading = true);
    final result = await handleBackgroundLocation();
    final isInside = result['isInside'] as bool?;
    final position = result['position'] as Position?;

    if (mounted) {
      setState(() {
        _isInside = isInside;
        _currentPosition = position;
        if (isInside == null) {
          _locationStatus = 'Location error or not set';
        } else {
          _locationStatus = isInside ? 'Inside Factory ✅' : 'Outside Factory ❌';
        }
        _isLocationLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _currentTimeNotifier.dispose();
    _elapsedTimeNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_assignmentSubscription != null) {
      Supabase.instance.client.removeChannel(_assignmentSubscription!);
    }
    NavigationHomeScreen.isInsideNotifier.removeListener(_onLocationChanged);
    NavigationHomeScreen.currentPositionNotifier.removeListener(
      _onPositionChanged,
    );
    NavigationHomeScreen.locationStatusNotifier.removeListener(
      _onLocationStatusChanged,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistState();
      _sendBackgroundReminder();
    }
  }

  Future<void> _sendBackgroundReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final isTimerRunning = prefs.getBool('persisted_is_timer_running') ?? false;

    if (isTimerRunning) {
      await NotificationService.showNotification(
        id: TimeUtils.nowUtc().millisecond,
        title: "Production Still Running",
        body:
            "Your production timer is still active. Please remember to update or close your production when finished.",
      );
    }
  }

  Future<void> _checkShiftEndForeground() async {
    if (!_isTimerRunning || _selectedShift == null) return;

    try {
      final now = TimeUtils.nowIst();
      final shift = _shifts.firstWhere((s) => s['name'] == _selectedShift);
      final startDt = TimeUtils.parseShiftTime(shift['start_time']);
      final endDt = TimeUtils.parseShiftTime(shift['end_time']);

      if (startDt == null || endDt == null) return;

      DateTime startToday = DateTime(
        now.year,
        now.month,
        now.day,
        startDt.hour,
        startDt.minute,
      );
      DateTime endToday = DateTime(
        now.year,
        now.month,
        now.day,
        endDt.hour,
        endDt.minute,
      );
      DateTime effectiveEnd;
      if (endDt.isBefore(startDt)) {
        if (!now.isBefore(startToday)) {
          effectiveEnd = endToday.add(const Duration(days: 1));
        } else if (now.isBefore(endToday)) {
          effectiveEnd = endToday;
        } else {
          final diffToStart = startToday.difference(now);
          if (diffToStart.inMinutes > 0 && diffToStart.inMinutes <= 15) {
            await NotificationService.showNotification(
              id: TimeUtils.nowUtc().millisecond,
              title: "Shift Starting Soon",
              body:
                  "Your shift ($_selectedShift) starts in ${diffToStart.inMinutes} minutes.",
            );
          }
          return;
        }
      } else {
        if (now.isBefore(startToday)) {
          final diffToStart = startToday.difference(now);
          if (diffToStart.inMinutes > 0 && diffToStart.inMinutes <= 15) {
            await NotificationService.showNotification(
              id: TimeUtils.nowUtc().millisecond,
              title: "Shift Starting Soon",
              body:
                  "Your shift ($_selectedShift) starts in ${diffToStart.inMinutes} minutes.",
            );
          }
          return;
        }
        effectiveEnd = endToday;
      }
      final diff = effectiveEnd.difference(now);

      if (diff.inMinutes > 0 && diff.inMinutes <= 15) {
        await NotificationService.showNotification(
          id: TimeUtils.nowUtc().millisecond,
          title: "Shift Ending Soon",
          body:
              "Your shift ($_selectedShift) ends in ${diff.inMinutes} minutes. Please update and close your production tasks.",
        );
      } else if (diff.isNegative) {
        await NotificationService.showNotification(
          id: TimeUtils.nowUtc().millisecond,
          title: "Shift Ended",
          body:
              "Your shift ($_selectedShift) has ended, but production is still running. Please close your production tasks.",
        );
      }
    } catch (e) {
      debugPrint('Foreground shift reminder error: $e');
    }
  }

  bool _areAllEntriesComplete() {
    // ONLY base machine is strictly required to start
    if (_selectedMachine == null ||
        _selectedItem == null ||
        _selectedOperation == null) {
      return false;
    }

    // Extra machines: only block if PARTIALLY filled
    for (var entry in _extraEntries) {
      final hasMachine = entry['machineId'] != null;
      final hasItem = entry['itemId'] != null;
      final hasOp = entry['operation'] != null;

      // If they started filling a row, they must finish it
      if ((hasMachine || hasItem || hasOp) &&
          !(hasMachine && hasItem && hasOp)) {
        return false;
      }
    }

    return true;
  }

  Future<void> _startTimer() async {
    if (_isInside == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot start production while outside factory boundaries!',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Automatically remove completely empty extra entries
    setState(() {
      _extraEntries.removeWhere(
        (entry) =>
            entry['machineId'] == null &&
            entry['itemId'] == null &&
            entry['operation'] == null,
      );
    });
    _persistState();

    if (!_areAllEntriesComplete()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete or remove partial machine entries first.',
          ),
        ),
      );
      return;
    }

    final logId = const uuid.Uuid().v4();

    setState(() {
      _isTimerRunning = true;
      _startTime = TimeUtils.nowUtc();
      _elapsed = Duration.zero;
      _currentLogId = logId;
    });

    // Auto-select shift if not selected to ensure consistent attendance records
    if (_selectedShift == null) {
      final detectedShift = _findShiftByTime(_startTime!);
      if (detectedShift.isNotEmpty) {
        setState(() {
          _selectedShift = detectedShift['name'];
        });
      } else {
        setState(() {
          _selectedShift = 'General';
        });
      }
    }

    // Record attendance check-in
    await _updateAttendance(isCheckOut: false, eventTime: _startTime);

    // Trigger notification for production start
    await NotificationService.showNotification(
      id: TimeUtils.nowUtc().millisecond,
      title: "Production Started",
      body:
          "You have started production on ${_selectedMachine!.name} for ${_selectedItem!.name} (${_selectedOperation!}).",
    );

    // Save initial log for "In" time visibility
    try {
      // 0. ENFORCE ONE ACTIVE TASK: Close any existing active tasks for this worker
      await Supabase.instance.client
          .from('production_logs')
          .update({'is_active': false})
          .eq('worker_id', widget.employee.id)
          .eq('is_active', true);

      // 1. Update assignment status if exists
      if (_activeAssignmentId != null) {
        await Supabase.instance.client
            .from('work_assignments')
            .update({
              'status': 'started',
              // updated_at handled by DB now()
            })
            .eq('id', _activeAssignmentId!);
      }

      // Use LogService to let backend handle start_time and timestamp
      await LogService().startProductionLog(
        ProductionLog(
          id: logId,
          employeeId: widget.employee.id,
          machineId: _selectedMachine!.id,
          itemId: _selectedItem!.id,
          operation: _selectedOperation!,
          quantity: 0,
          startTime: null, // Let DB handle time
          timestamp: null, // Let DB handle time
          latitude: _currentPosition?.latitude ?? 0.0,
          longitude: _currentPosition?.longitude ?? 0.0,
          shiftName: _selectedShift ?? _getShiftName(_startTime!),
          performanceDiff: 0,
          organizationCode: widget.employee.organizationCode,
          remarks: null,
        ),
      );
    } catch (e) {
      debugPrint('Error saving initial log: $e');
    }

    _persistState();
  }

  String _getShiftName(DateTime time) {
    for (final shift in _shifts) {
      final startDt = TimeUtils.parseShiftTime(shift['start_time']);
      final endDt = TimeUtils.parseShiftTime(shift['end_time']);

      if (startDt != null && endDt != null) {
        final startMinutes = startDt.hour * 60 + startDt.minute;
        final endMinutes = endDt.hour * 60 + endDt.minute;
        final minutes = time.hour * 60 + time.minute;

        if (startMinutes < endMinutes) {
          if (minutes >= startMinutes && minutes < endMinutes) {
            return "${shift['name']} (${shift['start_time']} - ${shift['end_time']})";
          }
        } else {
          // Crosses midnight
          if (minutes >= startMinutes || minutes < endMinutes) {
            return "${shift['name']} (${shift['start_time']} - ${shift['end_time']})";
          }
        }
      }
    }

    // Fallback logic
    final minutes = time.hour * 60 + time.minute;
    final dayStart = 7 * 60 + 30; // 07:30 AM
    final dayEnd = 19 * 60 + 30; // 07:30 PM

    if (minutes >= dayStart && minutes < dayEnd) {
      return 'Day Shift (07:30 AM - 07:30 PM)';
    } else {
      return 'Night Shift (07:30 PM - 07:30 AM)';
    }
  }

  Map<String, dynamic> _findShiftByTime(DateTime time) {
    for (final shift in _shifts) {
      final startDt = TimeUtils.parseShiftTime(shift['start_time']);
      final endDt = TimeUtils.parseShiftTime(shift['end_time']);

      if (startDt != null && endDt != null) {
        final startMinutes = startDt.hour * 60 + startDt.minute;
        final endMinutes = endDt.hour * 60 + endDt.minute;
        final minutes = time.hour * 60 + time.minute;

        if (startMinutes < endMinutes) {
          if (minutes >= startMinutes && minutes < endMinutes) {
            return shift;
          }
        } else {
          // Crosses midnight
          if (minutes >= startMinutes || minutes < endMinutes) {
            return shift;
          }
        }
      }
    }
    return <String, dynamic>{};
  }

  Future<void> _updateAttendance({
    bool isCheckOut = false,
    DateTime? eventTime,
    String? overrideStatus,
  }) async {
    try {
      await _attendanceService.updateAttendance(
        workerId: widget.employee.id,
        organizationCode: widget.employee.organizationCode!,
        shifts: _shifts,
        selectedShiftName: _selectedShift,
        isCheckOut: isCheckOut,
        eventTime: eventTime,
        startTimeRef: _startTime,
        overrideStatus: overrideStatus,
      );
    } catch (e) {
      debugPrint('ATTENDANCE_DEBUG: ERROR updating attendance: $e');
    }
  }

  OperationDetail? _getCurrentOperationDetail() {
    if (_selectedItem == null || _selectedOperation == null) return null;
    try {
      return _selectedItem!.operationDetails.firstWhere(
        (d) => d.name == _selectedOperation,
      );
    } catch (e) {
      return null;
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return TimeUtils.formatTo12Hour(time, format: 'hh:mm:ss a');
  }

  void _stopTimerAndMarkAbsent() async {
    final endTime = TimeUtils.nowUtc();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Departure'),
        content: const Text(
          'You are marking yourself absent because you have left the factory. This will stop your current work and mark your attendance as "Absent" with a remark. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, I have left'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    try {
      // 1. Stop Timer
      _isTimerRunning = false;
      _uiUpdateTimer?.cancel();

      // 2. Finish the log via LogService (let backend handle end_time)
      final remark = 'left factory after starting work';
      if (_currentLogId != null) {
        try {
          await LogService().finishProductionLog(
            id: _currentLogId!,
            quantity: 0,
            performanceDiff: 0,
            latitude: _currentPosition?.latitude ?? 0.0,
            longitude: _currentPosition?.longitude ?? 0.0,
            remarks: remark,
          );
        } catch (e) {
          debugPrint('Error finishing log in markAbsent: $e');
          // Fallback to client-side log creation if RPC fails
          final log = ProductionLog(
            id: _currentLogId!,
            employeeId: widget.employee.id,
            machineId: _selectedMachine?.id ?? 'N/A',
            itemId: _selectedItem?.id ?? 'N/A',
            operation: _selectedOperation ?? 'N/A',
            quantity: 0,
            startTime: _startTime,
            endTime: endTime,
            timestamp: endTime,
            latitude: _currentPosition?.latitude ?? 0.0,
            longitude: _currentPosition?.longitude ?? 0.0,
            shiftName: _selectedShift ?? 'N/A',
            performanceDiff: 0,
            organizationCode: widget.employee.organizationCode,
            remarks: remark,
          );
          await LogService().addLog(log);
        }
      }

      // 3. Update Attendance to Absent
      await AttendanceService().updateAttendance(
        workerId: widget.employee.id,
        organizationCode: widget.employee.organizationCode!,
        shifts: _shifts,
        selectedShiftName: _selectedShift,
        isCheckOut: true,
        eventTime: endTime,
        startTimeRef: _startTime,
        overrideStatus: 'Absent',
      );

      // 4. Reset state
      _startTime = null;
      _elapsed = Duration.zero;
      _elapsedTimeNotifier.value = Duration.zero;
      _extraEntries.clear();
      _selectedMachine = null;
      _selectedItem = null;
      _selectedOperation = null;

      await _clearPersistedState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift ended and marked absent.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _stopTimerAndFinish() {
    // PREVENT SUBMISSION IF OUTSIDE
    if (_isInside == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'CANNOT SUBMIT: You are outside the factory boundary. Please return to the factory to submit your production.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    final endTime = TimeUtils.nowUtc();

    final qtyControllers = <TextEditingController>[];
    final remarksControllers = <TextEditingController>[];
    qtyControllers.add(TextEditingController());
    remarksControllers.add(TextEditingController());
    for (int i = 0; i < _extraEntries.length; i++) {
      qtyControllers.add(TextEditingController());
      remarksControllers.add(TextEditingController());
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final currentContext = context;
        final screenContext = this.context;
        return AlertDialog(
          title: const Text('Production Finished'),
          content: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedItem != null && _selectedOperation != null)
                    _buildOperationInfo(_selectedItem!, _selectedOperation!),
                  Text(
                    'Duration: ${_formatDuration(_elapsed)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: qtyControllers[0],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText:
                          'Quantity for ${_selectedMachine?.name ?? "Base Machine"}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarksControllers[0],
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Remarks (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.comment),
                    ),
                  ),
                  if (_extraEntries.isNotEmpty)
                    ..._extraEntries.asMap().entries.map((e) {
                      final i = e.key;
                      final data = e.value;
                      final item = _items.firstWhere(
                        (it) => it.id == data['itemId'],
                        orElse: () => _selectedItem!,
                      );
                      final opName = data['operation'] ?? _selectedOperation!;
                      final machine = _machines.firstWhere(
                        (m) => m.id == data['machineId'],
                        orElse: () => _selectedMachine!,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _buildOperationInfo(item, opName),
                          const SizedBox(height: 8),
                          TextField(
                            controller: qtyControllers[i + 1],
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Quantity for ${machine.name}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: remarksControllers[i + 1],
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Remarks (Optional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.comment),
                            ),
                          ),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _resumeTimer(); // Restart timer if cancelled
                Navigator.pop(currentContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                FocusScope.of(currentContext).unfocus();
                // Validate base quantity
                if (qtyControllers[0].text.trim().isEmpty) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter base machine quantity'),
                    ),
                  );
                  return;
                }
                // Collect extra entries data - Simple: only include complete entries, skip others
                final extraEntriesData = <Map<String, dynamic>>[];
                for (int i = 0; i < _extraEntries.length; i++) {
                  final data = _extraEntries[i];
                  final isComplete =
                      (data['machineId'] != null &&
                      data['itemId'] != null &&
                      data['operation'] != null);

                  // Only collect if complete AND has a quantity
                  if (isComplete) {
                    final qtyStr = qtyControllers[i + 1].text.trim();
                    if (qtyStr.isNotEmpty) {
                      final qty = int.tryParse(qtyStr) ?? 0;
                      final remark = remarksControllers[i + 1].text.isNotEmpty
                          ? remarksControllers[i + 1].text
                          : null;

                      extraEntriesData.add({
                        'machineId': data['machineId'],
                        'itemId': data['itemId'],
                        'operation': data['operation'],
                        'quantity': qty,
                        'remarks': remark,
                      });
                    }
                  }
                }

                final baseQty = int.tryParse(qtyControllers[0].text.trim());
                if (baseQty == null) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(content: Text('Invalid quantity')),
                  );
                  return;
                }

                // Target Validation
                final detail = _getCurrentOperationDetail();
                if (detail != null && detail.target > 0) {
                  final diff = baseQty - detail.target;

                  Navigator.pop(currentContext); // Close input dialog

                  // Show Summary/Confirmation Dialog
                  _showConfirmationDialog(
                    screenContext,
                    baseQty,
                    remarksControllers[0].text,
                    endTime,
                    detail,
                    diff,
                    extraEntriesData,
                  );
                } else {
                  Navigator.pop(currentContext);
                  // Even if no target, show confirmation
                  _showConfirmationDialog(
                    screenContext,
                    baseQty,
                    remarksControllers[0].text,
                    endTime,
                    null,
                    0,
                    extraEntriesData,
                  );
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  void _showConfirmationDialog(
    BuildContext context,
    int quantity,
    String remarks,
    DateTime endTime,
    OperationDetail? detail,
    int diff,
    List<Map<String, dynamic>> extraEntriesData,
  ) {
    final isDark = ThemeController.of(context)?.isDarkMode ?? false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Confirm Production',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: isDark ? FontWeight.bold : FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow(
                  'In Time',
                  TimeUtils.formatTo12Hour(_startTime, format: 'hh:mm a'),
                  isDark: isDark,
                ),
                _buildSummaryRow(
                  'Out Time',
                  TimeUtils.formatTo12Hour(endTime, format: 'hh:mm a'),
                  isDark: isDark,
                ),
                _buildSummaryRow(
                  'Total Work Hours',
                  _formatDuration(_elapsed),
                  isDark: isDark,
                ),
                const Divider(),
                Text(
                  'Base Machine (${_selectedMachine?.name})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                _buildSummaryRow(
                  'Produced Quantity',
                  quantity.toString(),
                  isDark: isDark,
                ),
                if (detail != null && detail.target > 0)
                  _buildSummaryRow(
                    'Target Status',
                    diff >= 0 ? 'Met (+$diff)' : 'Missed ($diff)',
                    color: diff >= 0 ? Colors.green : Colors.red,
                    isDark: isDark,
                  ),
                _buildSummaryRow(
                  'Remarks',
                  remarks.isNotEmpty ? remarks : 'None',
                  isDark: isDark,
                ),
                if (extraEntriesData.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Extra Machines',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...extraEntriesData.map((data) {
                    final machine = _machines.firstWhere(
                      (m) => m.id == data['machineId'],
                      orElse: () => Machine(
                        id: data['machineId'] ?? 'N/A',
                        name: 'N/A',
                        type: 'N/A',
                        items: [],
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            machine.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          _buildSummaryRow(
                            'Qty / Remarks',
                            '${data['quantity']} / ${data['remarks'] ?? "None"}',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Please confirm these details. You cannot edit them after saving.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
                    color: isDark ? Colors.white : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resumeTimer();
              },
              child: Text(
                'Edit / Cancel',
                style: TextStyle(
                  fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _saveLog(quantity, remarks, endTime, diff, extraEntriesData);
              },
              child: Text(
                'Confirm & Save',
                style: TextStyle(
                  fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? color,
    bool isDark = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontWeight: isDark ? FontWeight.bold : FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color ?? (isDark ? Colors.white : Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _saveLog(
    int quantity,
    String remarks,
    DateTime endTime,
    int performanceDiff,
    List<Map<String, dynamic>> extraEntriesData,
  ) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      // Re-fetch location for the record
      Position position;
      try {
        position = await _locationService.getCurrentLocation();
      } catch (e) {
        // Use last known position if fetch fails
        if (_currentPosition != null) {
          position = _currentPosition!;
        } else {
          throw Exception('Could not verify location');
        }
      }

      // CHECK BOUNDARY BEFORE SAVING
      if (_isInside == false) {
        // Worker is outside, mark absent and cancel registration
        final remark = 'left factory after starting work';

        if (_currentLogId != null) {
          try {
            await LogService().finishProductionLog(
              id: _currentLogId!,
              quantity: 0,
              performanceDiff: 0,
              latitude: position.latitude,
              longitude: position.longitude,
              remarks: remark,
            );
          } catch (e) {
            debugPrint('Error finishing log in boundary check: $e');
            // Fallback
            final log = ProductionLog(
              id: _currentLogId!,
              employeeId: widget.employee.id,
              machineId: _selectedMachine!.id,
              itemId: _selectedItem!.id,
              operation: _selectedOperation!,
              quantity: 0,
              startTime: _startTime,
              endTime: endTime,
              timestamp: endTime,
              latitude: position.latitude,
              longitude: position.longitude,
              shiftName:
                  _selectedShift ??
                  _getShiftName(
                    TimeUtils.parseToLocal(_startTime ?? TimeUtils.nowUtc()),
                  ),
              performanceDiff: 0,
              organizationCode: widget.employee.organizationCode,
              remarks: remark,
            );
            await LogService().addLog(log);
          }
        }

        // Update Attendance to Absent
        await _attendanceService.updateAttendance(
          workerId: widget.employee.id,
          organizationCode: widget.employee.organizationCode!,
          shifts: _shifts,
          selectedShiftName: _selectedShift,
          isCheckOut: true,
          eventTime: endTime,
          startTimeRef: _startTime,
          overrideStatus: 'Absent',
        );

        _isTimerRunning = false;
        _uiUpdateTimer?.cancel();
        _startTime = null;
        _elapsed = Duration.zero;
        _selectedMachine = null;
        _selectedItem = null;
        _selectedOperation = null;
        await _clearPersistedState();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Outside factory boundary! Work not registered. Marked as Absent.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.popUntil(context, (route) => route.isFirst);
        }
        return;
      }

      // 1. Prepare Logs
      final List<ProductionLog> allLogs = [];

      final baseLog = ProductionLog(
        id: (_currentLogId != null && !_currentLogId!.startsWith('log_'))
            ? _currentLogId!
            : const uuid.Uuid().v4(),
        employeeId: widget.employee.id,
        machineId: _selectedMachine!.id,
        itemId: _selectedItem!.id,
        operation: _selectedOperation!,
        quantity: quantity,
        startTime: _startTime,
        endTime: endTime,
        timestamp: endTime,
        latitude: position.latitude,
        longitude: position.longitude,
        shiftName:
            _selectedShift ??
            _getShiftName(
              TimeUtils.parseToLocal(_startTime ?? TimeUtils.nowUtc()),
            ),
        performanceDiff: performanceDiff,
        organizationCode: widget.employee.organizationCode,
        remarks: remarks.isNotEmpty ? remarks : null,
      );
      // Ensure we explicitly set is_active to false in the database via the service or RPC
      allLogs.add(baseLog);

      // 2. Prepare Extra Logs
      for (final extraData in extraEntriesData) {
        final extraLog = ProductionLog(
          id: const uuid.Uuid().v4(),
          employeeId: widget.employee.id,
          machineId: extraData['machineId'],
          itemId: extraData['itemId'],
          operation: extraData['operation'],
          quantity: extraData['quantity'],
          startTime: _startTime,
          endTime: endTime,
          timestamp: endTime,
          latitude: position.latitude,
          longitude: position.longitude,
          shiftName:
              _selectedShift ??
              _getShiftName(
                TimeUtils.parseToLocal(_startTime ?? TimeUtils.nowUtc()),
              ),
          performanceDiff: 0,
          organizationCode: widget.employee.organizationCode,
          remarks: extraData['remarks'],
        );
        allLogs.add(extraLog);
      }

      // 3. Save All Logs Bulk
      // For the base log, use LogService to let backend handle end_time
      try {
        await LogService().finishProductionLog(
          id: baseLog.id,
          quantity: baseLog.quantity,
          performanceDiff: baseLog.performanceDiff,
          latitude: baseLog.latitude,
          longitude: baseLog.longitude,
          remarks: baseLog.remarks,
        );

        // Save extra logs normally (they don't have start/end times usually, just a timestamp)
        if (allLogs.length > 1) {
          await LogService().addLogs(allLogs.sublist(1));
        }
      } catch (e) {
        debugPrint('Error saving final log via finishProductionLog: $e');
        // Fallback to LogService
        await LogService().addLogs(allLogs);
      }

      // Update assignment status if exists
      if (_activeAssignmentId != null) {
        try {
          await Supabase.instance.client
              .from('work_assignments')
              .update({
                'status': 'completed',
                // updated_at handled by DB
              })
              .eq('id', _activeAssignmentId!);
        } catch (e) {
          debugPrint('Error updating assignment status: $e');
        }
      }

      // Record attendance check-out
      await _updateAttendance(isCheckOut: true, eventTime: endTime);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Production Log Saved Successfully!')),
        );
        _resetForm();
        _fetchTodayExtraUnits();
        _fetchAssignments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving log: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _resetForm() {
    // Keep background tasks running for attendance tracking

    setState(() {
      _isTimerRunning = false;
      _startTime = null;
      _elapsed = Duration.zero;
      _currentLogId = null;
      _selectedOperation = null;
      _selectedItem = null;
      _selectedMachine = null;
      _activeAssignmentId = null;
      _extraEntries.clear(); // Clear extra machines after successful log
    });
    _clearPersistedState();
  }

  List<String> _getFilteredOpsForItem(Item? item, Machine? machine) {
    if (item == null) return [];
    List<String> ops = item.operations;

    // Logic for Gear 122 based on machine type
    if (item.id == 'GR-122' && machine != null) {
      if (machine.type == 'CNC') {
        ops = ops.where((op) => op.contains('CNC')).toList();
      } else if (machine.type == 'VMC') {
        ops = ops.where((op) => op.contains('VMC')).toList();
      }
    }
    return ops;
  }

  List<String> _getFilteredOperations() {
    return _getFilteredOpsForItem(_selectedItem, _selectedMachine);
  }

  Widget _buildOperationInfo(Item item, String opName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detail = item.operationDetails.firstWhere(
      (od) => od.name == opName,
      orElse: () => OperationDetail(name: opName, target: 0),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Item: ${item.name} (${item.id}) • Operation: $opName • Target: ${detail.target}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isDark ? FontWeight.bold : FontWeight.w600,
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if ((detail.imageUrl ?? '').isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.image,
                color: isDark ? Colors.blue.shade300 : Colors.blue,
              ),
              tooltip: 'View Operation Image',
              onPressed: () async {
                final uri = Uri.parse(detail.imageUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          if ((detail.pdfUrl ?? '').isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.picture_as_pdf,
                color: isDark ? Colors.red.shade300 : Colors.red,
              ),
              tooltip: 'Open Operation PDF',
              onPressed: () async {
                final uri = Uri.parse(detail.pdfUrl!);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    );
  }

  String _getShiftTimeLeft() {
    if (_selectedShift == null) return '';
    try {
      final now = TimeUtils.nowIst();
      final shift = _shifts.firstWhere((s) => s['name'] == _selectedShift);
      final startDt = TimeUtils.parseShiftTime(shift['start_time']);
      final endDt = TimeUtils.parseShiftTime(shift['end_time']);

      if (startDt == null || endDt == null) return '';

      DateTime shiftStartToday = DateTime(
        now.year,
        now.month,
        now.day,
        startDt.hour,
        startDt.minute,
      );
      DateTime shiftEndToday = DateTime(
        now.year,
        now.month,
        now.day,
        endDt.hour,
        endDt.minute,
      );
      DateTime effectiveEnd;

      if (endDt.isBefore(startDt)) {
        if (!now.isBefore(shiftStartToday)) {
          effectiveEnd = shiftEndToday.add(const Duration(days: 1));
        } else if (now.isBefore(shiftEndToday)) {
          effectiveEnd = shiftEndToday;
        } else {
          final diffToStart = shiftStartToday.difference(now);
          final hours = diffToStart.inHours;
          final minutes = diffToStart.inMinutes % 60;
          return 'Starts in $hours hrs $minutes mins';
        }
      } else {
        if (now.isBefore(shiftStartToday)) {
          final diff = shiftStartToday.difference(now);
          final hours = diff.inHours;
          final minutes = diff.inMinutes % 60;
          return 'Starts in $hours hrs $minutes mins';
        }
        effectiveEnd = shiftEndToday;
      }

      final diff = effectiveEnd.difference(now);
      if (diff.isNegative) {
        return 'Shift Ended';
      }

      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      return '$hours hrs $minutes mins left';
    } catch (e) {
      return '';
    }
  }

  Widget _buildOperationGuide(Item item, String operationName) {
    final isDark = ThemeController.of(context)?.isDarkMode ?? false;
    final detail = item.operationDetails.firstWhere(
      (d) => d.name == operationName,
      orElse: () => OperationDetail(name: operationName, target: 0),
    );

    bool hasImage =
        detail.imageUrl != null &&
        detail.imageUrl!.isNotEmpty &&
        detail.imageUrl != 'logo.png';
    bool hasPdf = detail.pdfUrl != null && detail.pdfUrl!.isNotEmpty;
    bool hasTarget = detail.target > 0;

    if (!hasImage && !hasPdf && !hasTarget) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF253840) : AppTheme.white,
        borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : AppTheme.grey.withValues(alpha: 0.2),
            offset: const Offset(1.1, 1.1),
            blurRadius: 10.0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Operation Guide',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF6C5CE7),
                  ),
                ),
                if (hasTarget)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isDark
                                  ? const Color(0xFFA29BFE)
                                  : const Color(0xFF6C5CE7))
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Target: ${detail.target}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFA29BFE)
                            : const Color(0xFF6C5CE7),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (hasImage || hasPdf) ...[
              const SizedBox(height: 12),
              if (hasImage)
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog.fullscreen(
                        child: Stack(
                          children: [
                            InteractiveViewer(
                              panEnabled: true,
                              minScale: 0.5,
                              maxScale: 5.0,
                              boundaryMargin: const EdgeInsets.all(
                                double.infinity,
                              ),
                              child: Center(
                                child: detail.imageUrl!.startsWith('http')
                                    ? Image.network(
                                        detail.imageUrl!,
                                        fit: BoxFit.contain,
                                      )
                                    : Image.asset(
                                        'assets/images/${detail.imageUrl!}',
                                        fit: BoxFit.contain,
                                      ),
                              ),
                            ),
                            Positioned(
                              top: 40,
                              left: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.black,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.grey[300]!,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: detail.imageUrl!.startsWith('http')
                          ? Image.network(detail.imageUrl!, fit: BoxFit.contain)
                          : Image.asset(
                              'assets/images/${detail.imageUrl!}',
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                ),
              if (hasImage && hasPdf) const SizedBox(height: 8),
              if (hasPdf) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showPdf = !_showPdf;
                    });
                  },
                  icon: Icon(
                    _showPdf ? Icons.visibility_off : Icons.picture_as_pdf,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(_showPdf ? 'Hide PDF' : 'Open PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (_showPdf) ...[
                  const SizedBox(height: 8),
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SfPdfViewer.network(
                        detail.pdfUrl!,
                        enableDoubleTapZooming: true,
                        interactionMode: PdfInteractionMode.pan,
                        enableTextSelection: true,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMachineEntryCard({
    required String title,
    required bool isDark,
    required Machine? selectedMachine,
    required Item? selectedItem,
    required String? selectedOperation,
    required Function(Machine?) onMachineChanged,
    required Function(Item?) onItemChanged,
    required Function(String?) onOperationChanged,
    required List<String> availableOperations,
    VoidCallback? onRemove,
    bool isBase = false,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF2C3E50) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                  ),
                ),
                if (!isBase && onRemove != null)
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                    onPressed: _isTimerRunning ? null : onRemove,
                    tooltip: 'Remove Machine',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (selectedMachine?.photoUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/${selectedMachine!.photoUrl}',
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 120,
                      width: double.infinity,
                      color: isDark ? Colors.black26 : Colors.grey[200],
                      child: const Icon(
                        Icons.precision_manufacturing,
                        size: 40,
                      ),
                    );
                  },
                ),
              ),
            ],
            const Divider(),
            const SizedBox(height: 8),
            DropdownButtonFormField<Machine>(
              decoration: const InputDecoration(
                labelText: 'Select Machine',
                prefixIcon: Icon(Icons.settings),
              ),
              dropdownColor: isDark ? const Color(0xFF263238) : Colors.white,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
              ),
              initialValue: _machines.contains(selectedMachine)
                  ? selectedMachine
                  : null,
              items: _machines.map((machine) {
                return DropdownMenuItem(
                  value: machine,
                  child: Text('${machine.name} (${machine.id})'),
                );
              }).toList(),
              onChanged: _isTimerRunning ? null : onMachineChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Item>(
              decoration: const InputDecoration(
                labelText: 'Select Item/Component',
                prefixIcon: Icon(Icons.inventory_2),
              ),
              dropdownColor: isDark ? const Color(0xFF263238) : Colors.white,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
              ),
              initialValue: _items.contains(selectedItem) ? selectedItem : null,
              items: _items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text('${item.name} (${item.id})'),
                );
              }).toList(),
              onChanged: _isTimerRunning ? null : onItemChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Select Operation',
                prefixIcon: Icon(Icons.build),
              ),
              dropdownColor: isDark ? const Color(0xFF263238) : Colors.white,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
              ),
              initialValue: availableOperations.contains(selectedOperation)
                  ? selectedOperation
                  : null,
              items: availableOperations.map((op) {
                return DropdownMenuItem(value: op, child: Text(op));
              }).toList(),
              onChanged: _isTimerRunning ? null : onOperationChanged,
            ),
            if (selectedItem != null && selectedOperation != null) ...[
              const SizedBox(height: 12),
              _buildOperationGuide(selectedItem, selectedOperation),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShiftSelector(bool isDark) {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Select Shift',
        prefixIcon: Icon(Icons.access_time),
      ),
      dropdownColor: isDark ? const Color(0xFF263238) : Colors.white,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontWeight: isDark ? FontWeight.bold : FontWeight.normal,
      ),
      initialValue: _shifts.any((s) => s['name'] == _selectedShift)
          ? _selectedShift
          : null,
      items: _shifts.map((s) {
        final name = s['name']?.toString() ?? '';
        final startTime = s['start_time']?.toString() ?? '';
        final endTime = s['end_time']?.toString() ?? '';
        final isEnded = TimeUtils.hasShiftEnded(endTime, startTime);

        return DropdownMenuItem(
          value: name,
          enabled: !isEnded,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name),
              if (isEnded)
                const Text(
                  ' (Ended)',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
      onChanged: _isTimerRunning
          ? null
          : (String? value) {
              setState(() {
                _selectedShift = value;
              });
              _persistState();
            },
    );
  }

  Widget _buildAssignmentsHeader() {
    if (_assignments.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 18,
                color: isDark ? Colors.blue.shade300 : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                'Assigned Tasks',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.blue.shade200 : Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final a = _assignments[index];
                return GestureDetector(
                  onTap: () => _applyAssignment(a),
                  child: Container(
                    width: 200,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.blue.shade900.withValues(alpha: 0.3)
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.blue.shade700
                            : Colors.blue.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a['operation']} - ${a['item_id']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Machine: ${a['machine_id']}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isDark
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isDark ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'By: ${a['assigned_by']}',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                fontWeight: isDark
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isDark ? Colors.white : Colors.black54,
                              ),
                            ),
                            Icon(
                              Icons.touch_app,
                              size: 14,
                              color: isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOutside = _isInside == false;

    return Container(
      color: isDark ? const Color(0xFF17262A) : Colors.white,
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: isOutside,
            child: Opacity(
              opacity: isOutside ? 0.6 : 1.0,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 24,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 40), // Space for menu icon
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome,',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isDark
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[600],
                                ),
                              ),
                              Text(
                                widget.employee.name,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF17262A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue),
                          onPressed: () {
                            _fetchData();
                            _fetchAssignments();
                            _fetchTodayExtraUnits();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Refreshing data...'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildAssignmentsHeader(),
                    const SizedBox(height: 10),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount:
                          MediaQuery.of(context).orientation ==
                              Orientation.landscape
                          ? 4
                          : 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio:
                          MediaQuery.of(context).orientation ==
                              Orientation.landscape
                          ? 2.5
                          : 2.0,
                      children: [
                        ValueListenableBuilder<DateTime>(
                          valueListenable: _currentTimeNotifier,
                          builder: (context, time, _) {
                            return _metricTile(
                              'Current Time',
                              _formatTime(time),
                              Colors.blue,
                              Icons.access_time,
                            );
                          },
                        ),
                        ValueListenableBuilder<Duration>(
                          valueListenable: _elapsedTimeNotifier,
                          builder: (context, elapsed, _) {
                            return _metricTile(
                              'Shift Timer',
                              _isTimerRunning
                                  ? _formatDuration(elapsed)
                                  : 'Not started',
                              Colors.orange,
                              Icons.timer,
                            );
                          },
                        ),
                        _metricTile(
                          'Location',
                          _locationStatus,
                          _locationStatus.contains('Inside')
                              ? Colors.green
                              : Colors.red,
                          Icons.place,
                        ),
                        _metricTile(
                          'Machines',
                          () {
                            int count = 1 + _extraEntries.length;
                            if (count == 1) {
                              return _selectedMachine?.name ?? 'None';
                            }
                            return '$count Machines Active';
                          }(),
                          Colors.blueGrey,
                          Icons.precision_manufacturing,
                        ),
                        _metricTile(
                          'Item',
                          () {
                            if (_extraEntries.isEmpty) {
                              return _selectedItem?.name ?? 'None';
                            }
                            return 'Multiple Items';
                          }(),
                          Colors.teal,
                          Icons.widgets,
                        ),
                        _metricTile(
                          'Operation',
                          () {
                            if (_extraEntries.isEmpty) {
                              return _selectedOperation ?? 'None';
                            }
                            return 'Multiple Ops';
                          }(),
                          Colors.purple,
                          Icons.build,
                        ),
                        _metricTile(
                          'Shift Name',
                          _selectedShift ?? 'None',
                          Colors.indigo,
                          Icons.fact_check,
                        ),
                        _metricTile(
                          'Extra Units (Today)',
                          '$_extraUnitsToday',
                          Colors.green,
                          Icons.trending_up,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Location Status Card
                    Card(
                      color: isDark
                          ? (_locationStatus.contains('Inside')
                                ? Colors.green.shade900.withValues(alpha: 0.3)
                                : Colors.red.shade900.withValues(alpha: 0.3))
                          : (_locationStatus.contains('Inside')
                                ? Colors.green.shade50
                                : Colors.red.shade50),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Current Location:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                if (_isLocationLoading)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  IconButton(
                                    icon: Icon(
                                      Icons.refresh,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black54,
                                    ),
                                    onPressed: _manualRefreshLocation,
                                    tooltip: 'Refresh Location',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_currentPosition != null)
                              Text(
                                '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontFamily: 'Monospace',
                                  fontWeight: isDark
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              _locationStatus,
                              style: TextStyle(
                                color: isDark
                                    ? (_locationStatus.contains('Inside')
                                          ? Colors.green.shade300
                                          : Colors.red.shade300)
                                    : (_locationStatus.contains('Inside')
                                          ? Colors.green[800]
                                          : Colors.red[800]),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_isLoadingData)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      _buildShiftSelector(isDark),
                      if (_selectedShift != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 16,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              ValueListenableBuilder<DateTime>(
                                valueListenable: _currentTimeNotifier,
                                builder: (context, _, child) {
                                  return Text(
                                    _getShiftTimeLeft(),
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox(height: 16),

                      _buildMachineEntryCard(
                        title: 'Base Machine',
                        isDark: isDark,
                        selectedMachine: _selectedMachine,
                        selectedItem: _selectedItem,
                        selectedOperation: _selectedOperation,
                        onMachineChanged: (newValue) {
                          setState(() {
                            _selectedMachine = newValue;
                            _selectedItem = null;
                            _selectedOperation = null;
                          });
                          _persistState();
                        },
                        onItemChanged: (newValue) {
                          setState(() {
                            _selectedItem = newValue;
                            _selectedOperation = null;
                          });
                          _persistState();
                        },
                        onOperationChanged: (newValue) {
                          setState(() {
                            _selectedOperation = newValue;
                          });
                          _persistState();
                        },
                        availableOperations: _getFilteredOperations(),
                        isBase: true,
                      ),

                      ..._extraEntries.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final data = entry.value;
                        final selMachine = _machines
                            .where((m) => m.id == data['machineId'])
                            .cast<Machine?>()
                            .firstOrNull;
                        final selItem = _items
                            .where((i) => i.id == data['itemId'])
                            .cast<Item?>()
                            .firstOrNull;
                        final selOp = data['operation'];

                        return _buildMachineEntryCard(
                          title: 'Extra Machine Entry ${idx + 1}',
                          isDark: isDark,
                          selectedMachine: selMachine,
                          selectedItem: selItem,
                          selectedOperation: selOp,
                          onMachineChanged: (newValue) {
                            setState(() {
                              _extraEntries[idx]['machineId'] = newValue?.id;
                              _extraEntries[idx]['itemId'] = null;
                              _extraEntries[idx]['operation'] = null;
                            });
                            _persistState();
                          },
                          onItemChanged: (newValue) {
                            setState(() {
                              _extraEntries[idx]['itemId'] = newValue?.id;
                              _extraEntries[idx]['operation'] = null;
                            });
                            _persistState();
                          },
                          onOperationChanged: (newValue) {
                            setState(() {
                              _extraEntries[idx]['operation'] = newValue;
                            });
                            _persistState();
                          },
                          availableOperations: _getFilteredOpsForItem(
                            selItem,
                            selMachine,
                          ),
                          onRemove: () {
                            setState(() {
                              _extraEntries.removeAt(idx);
                            });
                            _persistState();
                          },
                        );
                      }),
                      if (!_isTimerRunning && _extraEntries.length < 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (_extraEntries.length >= 3) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Maximum 4 machines allowed simultaneously',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _extraEntries.add({
                                  'machineId': null,
                                  'itemId': null,
                                  'operation': null,
                                });
                              });
                              _persistState();
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: Text(
                              'Add Machine (${_extraEntries.length + 2}/4)',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 30),

                    if (!_isTimerRunning)
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          onPressed: _areAllEntriesComplete()
                              ? _startTimer
                              : null,
                          child: const Text(
                            'Start Production Timer',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF253840)
                                  : AppTheme.white,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(24.0),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.3)
                                      : AppTheme.grey.withValues(alpha: 0.2),
                                  offset: const Offset(1.1, 1.1),
                                  blurRadius: 10.0,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Production In Progress',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF6C5CE7),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ValueListenableBuilder<Duration>(
                                  valueListenable: _elapsedTimeNotifier,
                                  builder: (context, elapsed, _) {
                                    final detail = _getCurrentOperationDetail();
                                    return Column(
                                      children: [
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            SizedBox(
                                              height: 180,
                                              width: 180,
                                              child: Builder(
                                                builder: (context) {
                                                  final now =
                                                      TimeUtils.nowIst();
                                                  final shift =
                                                      _findShiftByTime(now);
                                                  double progress = 0.0;
                                                  if (shift.isNotEmpty) {
                                                    try {
                                                      final startDt =
                                                          TimeUtils.parseShiftTime(
                                                            shift['start_time'],
                                                          );
                                                      final endDt =
                                                          TimeUtils.parseShiftTime(
                                                            shift['end_time'],
                                                          );

                                                      if (startDt != null &&
                                                          endDt != null) {
                                                        final startMinutes =
                                                            startDt.hour * 60 +
                                                            startDt.minute;
                                                        var endMinutes =
                                                            endDt.hour * 60 +
                                                            endDt.minute;
                                                        final nowMinutes =
                                                            now.hour * 60 +
                                                            now.minute;

                                                        if (endMinutes <
                                                            startMinutes) {
                                                          // Crosses midnight
                                                          endMinutes += 24 * 60;
                                                        }

                                                        var currentMinutes =
                                                            nowMinutes;
                                                        if (currentMinutes <
                                                                startMinutes &&
                                                            endMinutes >
                                                                24 * 60) {
                                                          currentMinutes +=
                                                              24 * 60;
                                                        }

                                                        progress =
                                                            (currentMinutes -
                                                                startMinutes) /
                                                            (endMinutes -
                                                                startMinutes);
                                                        progress = progress
                                                            .clamp(0.0, 1.0);
                                                      }
                                                    } catch (e) {
                                                      progress = 0.5;
                                                    }
                                                  }
                                                  return CircularProgressIndicator(
                                                    value: progress,
                                                    strokeWidth: 12,
                                                    backgroundColor: isDark
                                                        ? Colors.white
                                                              .withValues(
                                                                alpha: 0.1,
                                                              )
                                                        : AppTheme.grey
                                                              .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(
                                                          isDark
                                                              ? const Color(
                                                                  0xFFA29BFE,
                                                                )
                                                              : const Color(
                                                                  0xFF6C5CE7,
                                                                ),
                                                        ),
                                                  );
                                                },
                                              ),
                                            ),
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _formatDuration(elapsed),
                                                  style: TextStyle(
                                                    fontSize: 32,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark
                                                        ? Colors.white
                                                        : AppTheme.darkText,
                                                    fontFamily: 'Monospace',
                                                  ),
                                                ),
                                                Text(
                                                  'ELAPSED TIME',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark
                                                        ? Colors.white
                                                        : AppTheme.grey,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        if (detail != null && detail.target > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  (isDark
                                                          ? const Color(
                                                              0xFFA29BFE,
                                                            )
                                                          : const Color(
                                                              0xFF6C5CE7,
                                                            ))
                                                      .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.track_changes,
                                                  size: 16,
                                                  color: isDark
                                                      ? const Color(0xFFA29BFE)
                                                      : const Color(0xFF6C5CE7),
                                                ),
                                                const SizedBox(width: 8),
                                                Builder(
                                                  builder: (context) {
                                                    final now =
                                                        TimeUtils.nowIst();
                                                    final shift =
                                                        _findShiftByTime(now);
                                                    String progressText =
                                                        'Target Progress: 70%';
                                                    if (shift.isNotEmpty) {
                                                      try {
                                                        final startDt =
                                                            TimeUtils.parseShiftTime(
                                                              shift['start_time'],
                                                            );
                                                        final endDt =
                                                            TimeUtils.parseShiftTime(
                                                              shift['end_time'],
                                                            );

                                                        if (startDt != null &&
                                                            endDt != null) {
                                                          final startMinutes =
                                                              startDt.hour *
                                                                  60 +
                                                              startDt.minute;
                                                          var endMinutes =
                                                              endDt.hour * 60 +
                                                              endDt.minute;
                                                          final nowMinutes =
                                                              now.hour * 60 +
                                                              now.minute;

                                                          if (endMinutes <
                                                              startMinutes) {
                                                            endMinutes +=
                                                                24 * 60;
                                                          }

                                                          var currentMinutes =
                                                              nowMinutes;
                                                          if (currentMinutes <
                                                                  startMinutes &&
                                                              endMinutes >
                                                                  24 * 60) {
                                                            currentMinutes +=
                                                                24 * 60;
                                                          }

                                                          final progress =
                                                              (currentMinutes -
                                                                  startMinutes) /
                                                              (endMinutes -
                                                                  startMinutes);
                                                          progressText =
                                                              'Shift Progress: ${(progress.clamp(0.0, 1.0) * 100).toInt()}%';
                                                        }
                                                      } catch (_) {}
                                                    }
                                                    return Text(
                                                      progressText,
                                                      style: TextStyle(
                                                        color: isDark
                                                            ? const Color(
                                                                0xFFA29BFE,
                                                              )
                                                            : const Color(
                                                                0xFF6C5CE7,
                                                              ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: _stopTimerAndFinish,
                              child: const Text(
                                'Stop & Enter Quantity',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                    if (_isSaving)
                      const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isOutside)
            Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_off,
                      color: Colors.white,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'OUTSIDE FACTORY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You are outside the factory premises. Work registration is disabled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    if (_isTimerRunning) ...[
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _stopTimerAndMarkAbsent(),
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('End Shift (Mark Absent)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use this if you have left the factory without finishing work.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
