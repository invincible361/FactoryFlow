import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../main.dart';

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

  Machine? _selectedMachine;
  Item? _selectedItem;
  String? _selectedOperation;
  final List<Map<String, String?>> _extraEntries = [];
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _isSaving = false;

  // Data State
  List<Machine> _machines = [];
  List<Item> _items = [];
  bool _isLoadingData = true;
  List<Map<String, dynamic>> _shifts = [];
  String? _selectedShift;

  // Location State
  Position? _currentPosition;
  String _locationStatus = 'Checking location...';
  bool _isLocationLoading = false;
  bool? _isInside; // Track inside/outside state more robustly

  // Timer State
  Timer? _timer;
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  bool _isTimerRunning = false;
  String? _factoryName;
  String? _logoUrl;
  String? _currentLogId;
  String? _workerPhotoUrl;

  // Notifiers for lag optimization
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier<DateTime>(
    DateTime.now(),
  );
  final ValueNotifier<Duration> _elapsedTimeNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  Timer? _uiUpdateTimer;
  Widget _metricTile(String title, String value, Color color, IconData icon) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        return Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.all(isLandscape ? 8 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black87, size: isLandscape ? 20 : 24),
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
                        fontWeight: FontWeight.w600,
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

  int _extraUnitsToday = 0;

  Future<void> _fetchTodayExtraUnits() async {
    try {
      final now = DateTime.now();
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
    _checkLocation();
    _fetchOrganizationName();
    _fetchTodayExtraUnits();
    _fetchWorkerPhoto();
    // Check for updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context, 'worker');
    });
    // Start a UI update timer to refresh time-based notifiers without full screen setState
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _currentTimeNotifier.value = DateTime.now();
      if (_isTimerRunning && _startTime != null) {
        _elapsed = DateTime.now().difference(_startTime!);
        _elapsedTimeNotifier.value = _elapsed;

        // Explicitly trigger a rebuild of the current frame if it's not happening
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        _elapsedTimeNotifier.notifyListeners();

        // Check location and shift end every 60 seconds while timer is running in foreground
        if (timer.tick % 60 == 0) {
          _checkLocation();
          _checkShiftEndForeground();
        }
      }
    });
  }

  String? _getFirstNotEmpty(Map<String, dynamic> data, List<String> keys) {
    for (var key in keys) {
      final val = data[key]?.toString();
      if (val != null && val.trim().isNotEmpty) {
        return val;
      }
    }
    return null;
  }

  Future<void> _fetchWorkerPhoto() async {
    try {
      final resp = await Supabase.instance.client
          .from('workers')
          .select()
          .eq('worker_id', widget.employee.id)
          .eq('organization_code', widget.employee.organizationCode ?? '')
          .maybeSingle();
      if (resp != null && mounted) {
        setState(() {
          _workerPhotoUrl = _getFirstNotEmpty(resp, [
            'photo_url',
            'avatar_url',
            'image_url',
            'imageurl',
            'photourl',
            'picture_url',
          ]);
        });
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _requestNotificationPermissions() async {
    await NotificationService.requestPermissions();
  }

  Future<void> _initializeBackgroundTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('worker_id', widget.employee.id);
    await prefs.setString(
      'worker_name',
      widget.employee.name,
    ); // Store name for background tasks
    if (widget.employee.organizationCode != null) {
      await prefs.setString('org_code', widget.employee.organizationCode!);
    }

    // Workmanager periodic tasks are only supported on Android.
    // On iOS, we would need to use registerOneOffTask or a different background strategy.
    if (!kIsWeb && Platform.isAndroid) {
      debugPrint('ProductionEntry: Registering background tasks');
      await Workmanager().registerPeriodicTask(
        "1",
        syncLocationTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(seconds: 10),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      await Workmanager().registerPeriodicTask(
        "2",
        shiftEndReminderTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(networkType: NetworkType.connected),
      );

      await Workmanager().registerPeriodicTask(
        "3",
        checkForUpdateTask,
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 5),
        constraints: Constraints(networkType: NetworkType.connected),
      );
      debugPrint('ProductionEntry: Background tasks registered');
    } else if (!kIsWeb && Platform.isIOS) {
      // iOS specific background task registration if needed
      // For now, we skip to avoid the "unhandledMethod" crash
      debugPrint('Periodic tasks are not supported on iOS via Workmanager.');
    }
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

      if (mounted) {
        setState(() {
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
              try {
                _startTime = DateTime.parse(startTimeStr!).toLocal();
              } catch (_) {
                _startTime = TimeUtils.parseToLocal(startTimeStr);
              }
            }
            _isTimerRunning = true;
            _resumeTimer();
            _initializeBackgroundTasks();
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
        _elapsed = DateTime.now().difference(_startTime!);
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
    } catch (e) {
      debugPrint('Error clearing persisted state: $e');
    }
  }

  Future<void> _fetchOrganizationName() async {
    try {
      final resp = await Supabase.instance.client
          .from('organizations')
          .select('organization_name, factory_name, logo_url')
          .eq('organization_code', widget.employee.organizationCode ?? '')
          .maybeSingle();
      if (mounted && resp != null) {
        setState(() {
          final orgName = (resp['organization_name'] ?? '').toString();
          final facName = (resp['factory_name'] ?? '').toString();
          _factoryName = orgName.isNotEmpty ? orgName : facName;
          _logoUrl = (resp['logo_url'] ?? '').toString();
        });
      }
    } catch (e) {
      debugPrint('Fetch org name error: $e');
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

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _currentTimeNotifier.dispose();
    _elapsedTimeNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _quantityController.dispose();
    _remarksController.dispose();
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
      await _showLocalNotification(
        "Production Still Running",
        "Your production timer is still active. Please remember to update or close your production when finished.",
      );
    }
  }

  Future<void> _showLocalNotification(String title, String body) async {
    if (kIsWeb) return;

    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidDetails = AndroidNotificationDetails(
        'factory_flow_reminder',
        'Worker App Reminders',
        importance: Importance.max,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecond,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

  Future<void> _checkShiftEndForeground() async {
    if (!_isTimerRunning || _selectedShift == null) return;

    try {
      final now = DateTime.now();
      final shift = _shifts.firstWhere((s) => s['name'] == _selectedShift);
      final endTimeStr = shift['end_time'] as String;
      final format = DateFormat('hh:mm a');
      final endDt = format.parse(endTimeStr);

      DateTime shiftEndToday = DateTime(
        now.year,
        now.month,
        now.day,
        endDt.hour,
        endDt.minute,
      );

      final startDt = format.parse(shift['start_time'] as String);
      if (endDt.isBefore(startDt)) {
        if (now.hour >= startDt.hour) {
          shiftEndToday = shiftEndToday.add(const Duration(days: 1));
        }
      }

      final diff = shiftEndToday.difference(now);

      if (diff.inMinutes > 0 && diff.inMinutes <= 15) {
        await _showLocalNotification(
          "Shift Ending Soon",
          "Your shift ($_selectedShift) ends in ${diff.inMinutes} minutes. Please update and close your production tasks.",
        );
      } else if (diff.isNegative) {
        await _showLocalNotification(
          "Shift Ended",
          "Your shift ($_selectedShift) has ended, but production is still running. Please close your production tasks.",
        );
      }
    } catch (e) {
      debugPrint('Foreground shift reminder error: $e');
    }
  }

  Future<void> _checkLocation() async {
    setState(() {
      _isLocationLoading = true;
      _locationStatus = 'Fetching location...';
    });

    try {
      final position = await _locationService.getCurrentLocation(
        requestAlways: true,
      );
      bool isInside = false;
      try {
        final org = await Supabase.instance.client
            .from('organizations')
            .select()
            .eq('organization_code', widget.employee.organizationCode!)
            .maybeSingle();
        if (org != null) {
          final lat = (org['latitude'] ?? 0.0) * 1.0;
          final lng = (org['longitude'] ?? 0.0) * 1.0;
          final radius = (org['radius_meters'] ?? 500.0) * 1.0;

          if (lat == 0.0 && lng == 0.0) {
            debugPrint('Organization has no location set (0,0)');
          }

          isInside = _locationService.isInside(position, lat, lng, radius);
        } else {
          debugPrint(
            'Organization not found for code: ${widget.employee.organizationCode}',
          );
          isInside = false;
        }
      } catch (e) {
        debugPrint('Error fetching organization location: $e');
        isInside = false;
      }

      if (mounted) {
        final wasInside = _isInside;
        setState(() {
          _currentPosition = position;
          _isInside = isInside;
          _locationStatus = isInside ? 'Inside Factory ✅' : 'Outside Factory ❌';
        });

        // Log out-of-bounds event if production is running
        if (_isTimerRunning) {
          final prefs = await SharedPreferences.getInstance();
          final now = DateTime.now();

          // wasInside is null on first check, treat as true to avoid false exit log
          // or we can use the persisted 'was_inside' if available
          final effectiveWasInside =
              wasInside ?? prefs.getBool('was_inside') ?? true;

          if (effectiveWasInside && !isInside) {
            // Just moved out
            final eventId = const Uuid().v4();
            await Supabase.instance.client
                .from('production_outofbounds')
                .insert({
                  'id': eventId,
                  'worker_id': widget.employee.id,
                  'worker_name': widget.employee.name,
                  'organization_code': widget.employee.organizationCode,
                  'date': DateFormat('yyyy-MM-dd').format(now),
                  'exit_time': now.toUtc().toIso8601String(),
                  'exit_latitude': position.latitude,
                  'exit_longitude': position.longitude,
                });
            await _updateAttendance(isCheckOut: true, eventTime: now);
            await prefs.setString('active_boundary_event_id', eventId);
            await prefs.setBool('was_inside', false);
            await _showLocalNotification(
              "Return to Factory!",
              "You have left the factory area during production. Please return immediately.",
            );
          } else if (!effectiveWasInside && isInside) {
            // Just came back
            final eventId = prefs.getString('active_boundary_event_id');
            if (eventId != null) {
              final entryTime = DateTime.now();
              // Fetch exit time to calculate duration
              final event = await Supabase.instance.client
                  .from('production_outofbounds')
                  .select('exit_time')
                  .eq('id', eventId)
                  .maybeSingle();

              String? durationStr;
              if (event != null) {
                final exitTime = TimeUtils.parseToLocal(event['exit_time']);
                final diff = entryTime.difference(exitTime);
                durationStr = "${diff.inMinutes} mins";
              }

              await Supabase.instance.client
                  .from('production_outofbounds')
                  .update({
                    'entry_time': entryTime.toUtc().toIso8601String(),
                    'entry_latitude': position.latitude,
                    'entry_longitude': position.longitude,
                    'duration_minutes': durationStr,
                  })
                  .eq('id', eventId);
              await prefs.remove('active_boundary_event_id');
              await prefs.setBool('was_inside', true);
              await _showLocalNotification(
                "Back in Bounds",
                "You have returned to the factory premises.",
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationStatus = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
      }
    }
  }

  Future<void> _startTimer() async {
    if (_selectedMachine == null ||
        _selectedItem == null ||
        _selectedOperation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Machine, Item and Operation first.'),
        ),
      );
      return;
    }

    final logId = const Uuid().v4();

    setState(() {
      _isTimerRunning = true;
      _startTime = DateTime.now();
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

    // Start background tasks only when production starts
    await _initializeBackgroundTasks();

    // Check location immediately
    _checkLocation();

    // Record attendance check-in
    await _updateAttendance(isCheckOut: false, eventTime: _startTime);

    // Save initial log for "In" time visibility
    try {
      final initialLog = ProductionLog(
        id: logId,
        employeeId: widget.employee.id,
        machineId: _selectedMachine!.id,
        itemId: _selectedItem!.id,
        operation: _selectedOperation!,
        quantity: 0,
        timestamp: _startTime!,
        startTime: _startTime,
        endTime: null,
        latitude: _currentPosition?.latitude ?? 0.0,
        longitude: _currentPosition?.longitude ?? 0.0,
        shiftName: _selectedShift ?? _getShiftName(_startTime!),
        performanceDiff: 0,
        organizationCode: widget.employee.organizationCode,
        remarks: null,
      );
      await LogService().addLog(initialLog);
    } catch (e) {
      debugPrint('Error saving initial log: $e');
    }

    _persistState();
  }

  String _getShiftName(DateTime time) {
    // We will now try to fetch the actual shift name from the database based on the time
    // If not found, we fallback to the default logic
    final minutes = time.hour * 60 + time.minute;

    for (final shift in _shifts) {
      try {
        final startStr = shift['start_time'] as String;
        final endStr = shift['end_time'] as String;

        // Parse "hh:mm a" format
        final format = DateFormat('hh:mm a');
        final startDt = format.parse(startStr);
        final endDt = format.parse(endStr);

        final startMinutes = startDt.hour * 60 + startDt.minute;
        final endMinutes = endDt.hour * 60 + endDt.minute;

        if (startMinutes < endMinutes) {
          if (minutes >= startMinutes && minutes < endMinutes) {
            return "${shift['name']} ($startStr - $endStr)";
          }
        } else {
          // Crosses midnight
          if (minutes >= startMinutes || minutes < endMinutes) {
            return "${shift['name']} ($startStr - $endStr)";
          }
        }
      } catch (e) {
        debugPrint('Error parsing shift time: $e');
      }
    }

    // Fallback logic
    final dayStart = 7 * 60 + 30; // 450
    final dayEnd = 19 * 60 + 30; // 1170

    if (minutes >= dayStart && minutes < dayEnd) {
      return 'Day Shift (07:30 AM - 07:30 PM)';
    } else {
      return 'Night Shift (07:30 PM - 07:30 AM)';
    }
  }

  Map<String, dynamic> _findShiftByTime(DateTime time) {
    final minutes = time.hour * 60 + time.minute;
    for (final shift in _shifts) {
      try {
        final startStr = shift['start_time'] as String;
        final endStr = shift['end_time'] as String;
        final format = DateFormat('hh:mm a');
        final startDt = format.parse(startStr);
        final endDt = format.parse(endStr);
        final startMinutes = startDt.hour * 60 + startDt.minute;
        final endMinutes = endDt.hour * 60 + endDt.minute;

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
      } catch (e) {
        debugPrint('Error parsing shift for lookup: $e');
      }
    }
    return <String, dynamic>{};
  }

  Future<void> _updateAttendance({
    bool isCheckOut = false,
    DateTime? eventTime,
  }) async {
    try {
      final now = eventTime ?? DateTime.now();
      // Use start time for date key if checking out to ensure we update the same record
      final effectiveDate = (isCheckOut && _startTime != null)
          ? _startTime!
          : now;
      final dateStr = DateFormat('yyyy-MM-dd').format(effectiveDate);
      final supabase = Supabase.instance.client;

      // Determine shift name strictly
      String targetShiftName = _selectedShift ?? '';
      Map<String, dynamic> shift = {};

      if (targetShiftName.isNotEmpty) {
        shift = _shifts.firstWhere(
          (s) => s['name'] == targetShiftName,
          orElse: () => <String, dynamic>{},
        );
      }

      // If no valid shift selected/found, try to detect from time
      if (shift.isEmpty) {
        shift = _findShiftByTime(effectiveDate);
        if (shift.isNotEmpty) {
          targetShiftName = shift['name'];
        } else {
          targetShiftName = 'General'; // Fallback to avoid null
        }
      }

      final payload = {
        'worker_id': widget.employee.id,
        'organization_code': widget.employee.organizationCode,
        'date': dateStr,
        'shift_name': targetShiftName,
        'shift_start_time': shift['start_time'],
        'shift_end_time': shift['end_time'],
      };

      if (!isCheckOut) {
        // For Start Production, always record check_in if it's the first production of the shift
        final existing = await supabase
            .from('attendance')
            .select()
            .eq('worker_id', widget.employee.id)
            .eq('date', dateStr)
            .eq('organization_code', widget.employee.organizationCode!)
            .maybeSingle();

        if (existing == null) {
          payload['check_in'] = now.toUtc().toIso8601String();
          payload['status'] = 'On Time'; // Default status on check-in
          await supabase.from('attendance').insert(payload);
        } else if (existing['check_in'] == null) {
          // If record exists (e.g. from previous shift overlap) but check_in is missing
          await supabase
              .from('attendance')
              .update({
                'check_in': now.toUtc().toIso8601String(),
                'status': 'On Time',
                'shift_name': targetShiftName,
                'shift_start_time': shift['start_time'],
                'shift_end_time': shift['end_time'],
              })
              .eq('worker_id', widget.employee.id)
              .eq('date', dateStr)
              .eq('organization_code', widget.employee.organizationCode!);
        }
      } else {
        // For End Production, record/update check_out
        payload['check_out'] = now.toUtc().toIso8601String();

        if (shift.isNotEmpty) {
          try {
            final format = DateFormat('hh:mm a');
            final shiftEndDt = format.parse(shift['end_time']);
            final shiftStartDt = format.parse(shift['start_time']);

            DateTime shiftEndToday = DateTime(
              now.year,
              now.month,
              now.day,
              shiftEndDt.hour,
              shiftEndDt.minute,
            );

            if (shiftEndDt.isBefore(shiftStartDt)) {
              // Night shift logic: if now is after start or before end
              if (now.hour >= shiftStartDt.hour || now.hour < shiftEndDt.hour) {
                if (now.hour >= shiftStartDt.hour) {
                  shiftEndToday = shiftEndToday.add(const Duration(days: 1));
                }
              }
            }

            final diffMinutes = now.difference(shiftEndToday).inMinutes;
            final isEarly = diffMinutes < -15;
            final isOvertime = diffMinutes > 15;

            payload['is_early_leave'] = isEarly;
            payload['is_overtime'] = isOvertime;
            payload['status'] = (isEarly && isOvertime)
                ? 'Both'
                : (isEarly
                      ? 'Early Leave'
                      : (isOvertime ? 'Overtime' : 'On Time'));
          } catch (e) {
            debugPrint('Error calculating shift end for attendance: $e');
          }
        }

        final existing = await supabase
            .from('attendance')
            .select()
            .eq('worker_id', widget.employee.id)
            .eq('date', dateStr)
            .eq('organization_code', widget.employee.organizationCode!)
            .maybeSingle();

        if (existing == null) {
          await supabase.from('attendance').insert(payload);
        } else {
          await supabase
              .from('attendance')
              .update(payload)
              .eq('worker_id', widget.employee.id)
              .eq('date', dateStr)
              .eq('organization_code', widget.employee.organizationCode!);
        }
      }
    } catch (e) {
      debugPrint('Error updating attendance: $e');
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

  void _stopTimerAndFinish() {
    _timer?.cancel();
    final endTime = DateTime.now();

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
                    decoration: const InputDecoration(
                      labelText: 'Base Machine Quantity',
                      border: OutlineInputBorder(),
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
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(),
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
                // Validate extra entries (handle partial and complete states)
                for (int i = 0; i < _extraEntries.length; i++) {
                  final data = _extraEntries[i];
                  final hasMachine = data['machineId'] != null;
                  final hasItem = data['itemId'] != null;
                  final hasOp = data['operation'] != null;
                  final isComplete = hasMachine && hasItem && hasOp;
                  final isPartial =
                      (hasMachine || hasItem || hasOp) && !isComplete;
                  if (isPartial) {
                    ScaffoldMessenger.of(currentContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Please complete Extra Machine Entry ${i + 1} (select machine, item, and operation)',
                        ),
                      ),
                    );
                    return;
                  }
                  if (isComplete && qtyControllers[i + 1].text.trim().isEmpty) {
                    ScaffoldMessenger.of(currentContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Please enter quantity for Extra Machine Entry ${i + 1}',
                        ),
                      ),
                    );
                    return;
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
                  );
                }
                // Save extra entries logs
                for (int i = 0; i < _extraEntries.length; i++) {
                  final data = _extraEntries[i];
                  final isComplete =
                      (data['machineId'] != null &&
                      data['itemId'] != null &&
                      data['operation'] != null);
                  if (!isComplete) continue;
                  final qty =
                      int.tryParse(qtyControllers[i + 1].text.trim()) ?? 0;
                  final remark = remarksControllers[i + 1].text.isNotEmpty
                      ? remarksControllers[i + 1].text
                      : null;
                  final machine = _machines.firstWhere(
                    (m) => m.id == data['machineId'],
                    orElse: () => _selectedMachine!,
                  );
                  final item = _items.firstWhere(
                    (it) => it.id == data['itemId'],
                    orElse: () => _selectedItem!,
                  );
                  final op = data['operation'] ?? _selectedOperation!;
                  final log = ProductionLog(
                    id: const Uuid().v4(),
                    employeeId: widget.employee.id,
                    machineId: machine.id,
                    itemId: item.id,
                    operation: op,
                    quantity: qty,
                    timestamp: DateTime.now(),
                    startTime: _startTime,
                    endTime: endTime,
                    latitude: _currentPosition?.latitude ?? 0.0,
                    longitude: _currentPosition?.longitude ?? 0.0,
                    shiftName:
                        _selectedShift ??
                        _getShiftName(_startTime ?? DateTime.now()),
                    performanceDiff: 0,
                    organizationCode: widget.employee.organizationCode,
                    remarks: remark,
                  );
                  LogService().addLog(log);
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
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Production'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow(
                  'In Time',
                  TimeUtils.formatTo12Hour(_startTime, format: 'hh:mm a'),
                ),
                _buildSummaryRow(
                  'Out Time',
                  TimeUtils.formatTo12Hour(endTime, format: 'hh:mm a'),
                ),
                _buildSummaryRow('Total Work Hours', _formatDuration(_elapsed)),
                const Divider(),
                _buildSummaryRow('Produced Quantity', quantity.toString()),
                if (detail != null && detail.target > 0)
                  _buildSummaryRow(
                    'Target Status',
                    diff >= 0 ? 'Met (+$diff)' : 'Missed ($diff)',
                    color: diff >= 0 ? Colors.green : Colors.red,
                  ),
                const Divider(),
                _buildSummaryRow(
                  'Remarks',
                  remarks.isNotEmpty ? remarks : 'None',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please confirm these details. You cannot edit them after saving.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Re-open input dialog if they want to edit?
                // For now just cancel back to running timer is safer or just stop?
                // The user said "confirmation they can only see not edit".
                // So if they want to change, they probably need to go back.
                // But _stopTimerAndFinish has already stopped the timer visually (though _timer is active in background technically until cancel).
                // Actually _stopTimerAndFinish calls _timer?.cancel().
                // If they cancel here, we should probably resume.
                _resumeTimer();
              },
              child: const Text('Edit / Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _saveLog(quantity, remarks, endTime, diff);
              },
              child: const Text('Confirm & Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
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

      final log = ProductionLog(
        id: (_currentLogId != null && !_currentLogId!.startsWith('log_'))
            ? _currentLogId!
            : const Uuid().v4(),
        employeeId: widget.employee.id,
        machineId: _selectedMachine!.id,
        itemId: _selectedItem!.id,
        operation: _selectedOperation!,
        quantity: quantity,
        timestamp: DateTime.now(),
        startTime: _startTime,
        endTime: endTime,
        latitude: position.latitude,
        longitude: position.longitude,
        shiftName:
            _selectedShift ?? _getShiftName(_startTime ?? DateTime.now()),
        performanceDiff: performanceDiff,
        organizationCode: widget.employee.organizationCode,
        remarks: remarks.isNotEmpty ? remarks : null,
      );

      await LogService().addLog(log);

      // Record attendance check-out
      await _updateAttendance(isCheckOut: true, eventTime: endTime);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Production Log Saved Successfully!')),
        );
        _resetForm();
        _fetchTodayExtraUnits();
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
    _timer?.cancel();
    // Cancel background tasks when production finishes
    if (!kIsWeb) {
      Workmanager().cancelAll();
    }

    setState(() {
      _isTimerRunning = false;
      _startTime = null;
      _elapsed = Duration.zero;
      _currentLogId = null;
      _quantityController.clear();
      _remarksController.clear();
      _selectedOperation = null;
      _selectedItem = null;
      _selectedMachine = null;
    });
    _clearPersistedState();
  }

  List<String> _getFilteredOperations() {
    if (_selectedItem == null) return [];
    List<String> ops = _selectedItem!.operations;

    // Logic for Gear 122 based on machine type
    if (_selectedItem!.id == 'GR-122' && _selectedMachine != null) {
      if (_selectedMachine!.type == 'CNC') {
        ops = ops.where((op) => op.contains('CNC')).toList();
      } else if (_selectedMachine!.type == 'VMC') {
        ops = ops.where((op) => op.contains('VMC')).toList();
      }
    }
    return ops;
  }

  Widget _buildOperationInfo(Item item, String opName) {
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
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          if ((detail.imageUrl ?? '').isNotEmpty)
            IconButton(
              icon: const Icon(Icons.image, color: Colors.blue),
              tooltip: 'View Operation Image',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: SizedBox(
                      width: 500,
                      child: Image.network(
                        detail.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, st) =>
                            const Text('Image failed to load'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          if ((detail.pdfUrl ?? '').isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
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

  Widget _buildErrorWidget() {
    return Container(
      height: 250,
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 50, color: Colors.grey),
            Text('Could not load image'),
          ],
        ),
      ),
    );
  }

  String _getShiftTimeLeft() {
    if (_selectedShift == null) return '';
    try {
      final now = DateTime.now();
      final shift = _shifts.firstWhere((s) => s['name'] == _selectedShift);
      final startStr = shift['start_time'] as String;
      final endStr = shift['end_time'] as String;
      final format = DateFormat('hh:mm a');
      final startDt = format.parse(startStr);
      final endDt = format.parse(endStr);

      DateTime shiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        startDt.hour,
        startDt.minute,
      );
      DateTime shiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        endDt.hour,
        endDt.minute,
      );

      if (endDt.isBefore(startDt)) {
        // Night shift crossing midnight
        if (now.hour >= startDt.hour) {
          // We are in the evening part of the shift
          shiftEnd = shiftEnd.add(const Duration(days: 1));
        } else if (now.hour < endDt.hour ||
            (now.hour == endDt.hour && now.minute < endDt.minute)) {
          // We are in the morning part of the shift
          // shiftEnd is already today, which is correct
        } else {
          // It's after the shift ended in the morning but before it starts in the evening
          final shiftStartToday = DateTime(
            now.year,
            now.month,
            now.day,
            startDt.hour,
            startDt.minute,
          );
          final diffToStart = shiftStartToday.difference(now);
          final hours = diffToStart.inHours;
          final minutes = diffToStart.inMinutes % 60;
          return 'Starts in $hours hrs $minutes mins';
        }
      } else {
        // Regular day shift
        if (now.isBefore(shiftStart)) {
          final diff = shiftStart.difference(now);
          final hours = diff.inHours;
          final minutes = diff.inMinutes % 60;
          return 'Starts in $hours hrs $minutes mins';
        }
      }

      final diff = shiftEnd.difference(now);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_logoUrl != null && _logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      _logoUrl!,
                      height: 28,
                      width: 28,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.factory, size: 28),
                    ),
                  )
                else
                  Image.asset(
                    'assets/images/logo.png',
                    height: 28,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.factory, size: 28),
                  ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('Worker App', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                        ((_workerPhotoUrl ?? widget.employee.photoUrl) !=
                                null &&
                            ((_workerPhotoUrl ?? widget.employee.photoUrl)!)
                                .isNotEmpty)
                        ? NetworkImage(
                            (_workerPhotoUrl ?? widget.employee.photoUrl)!,
                          )
                        : null,
                    child:
                        (((_workerPhotoUrl ?? widget.employee.photoUrl) ==
                                null) ||
                            ((_workerPhotoUrl ?? widget.employee.photoUrl)!)
                                .isEmpty)
                        ? const Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.black54,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Welcome, ${widget.employee.name}${_factoryName != null && _factoryName!.isNotEmpty ? ' — $_factoryName' : ''}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              _fetchData();
              _fetchTodayExtraUnits();
              _fetchWorkerPhoto();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing data...')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Productivity',
            onPressed: _openProductivity,
          ),
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'Check for Updates',
            onPressed: () => UpdateService.checkForUpdates(context, 'worker'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              // Assuming navigating back to root handles logout or we push LoginScreen
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount:
                    MediaQuery.of(context).orientation == Orientation.landscape
                    ? 4
                    : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio:
                    MediaQuery.of(context).orientation == Orientation.landscape
                    ? 2.5
                    : 2.0,
                children: [
                  ValueListenableBuilder<DateTime>(
                    valueListenable: _currentTimeNotifier,
                    builder: (context, time, _) {
                      return _metricTile(
                        'Current Time',
                        _formatTime(time),
                        Colors.blue.shade100,
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
                        Colors.orange.shade100,
                        Icons.timer,
                      );
                    },
                  ),
                  _metricTile(
                    'Location',
                    _locationStatus,
                    _locationStatus.contains('Inside')
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    Icons.place,
                  ),
                  _metricTile(
                    'Machine',
                    _selectedMachine != null ? _selectedMachine!.name : 'None',
                    Colors.blueGrey.shade100,
                    Icons.precision_manufacturing,
                  ),
                  _metricTile(
                    'Item',
                    _selectedItem != null ? _selectedItem!.name : 'None',
                    Colors.teal.shade100,
                    Icons.widgets,
                  ),
                  _metricTile(
                    'Operation',
                    _selectedOperation ?? 'None',
                    Colors.purple.shade100,
                    Icons.build,
                  ),
                  _metricTile(
                    'Shift Name',
                    _selectedShift ?? 'None',
                    Colors.indigo.shade100,
                    Icons.fact_check,
                  ),
                  _metricTile(
                    'Extra Units (Today)',
                    '$_extraUnitsToday',
                    Colors.green.shade200,
                    Icons.trending_up,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Location Status Card
              Card(
                color: _locationStatus.contains('Inside')
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Current Location:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_isLocationLoading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _checkLocation,
                              tooltip: 'Refresh Location',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentPosition != null
                            ? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}'
                            : 'Unknown',
                        style: const TextStyle(fontFamily: 'Monospace'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _locationStatus,
                        style: TextStyle(
                          color: _locationStatus.contains('Inside')
                              ? Colors.green[800]
                              : Colors.red[800],
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
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Shift',
                    prefixIcon: Icon(Icons.access_time),
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
                ),
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
                DropdownButtonFormField<Machine>(
                  decoration: const InputDecoration(
                    labelText: 'Select Machine',
                    prefixIcon: Icon(Icons.settings),
                  ),
                  initialValue: _machines.contains(_selectedMachine)
                      ? _selectedMachine
                      : null,
                  items: _machines.map((machine) {
                    return DropdownMenuItem(
                      value: machine,
                      child: Text('${machine.name} (${machine.id})'),
                    );
                  }).toList(),
                  onChanged: _isTimerRunning
                      ? null
                      : (Machine? newValue) {
                          setState(() {
                            _selectedMachine = newValue;
                            _selectedItem = null;
                            _selectedOperation = null;
                          });
                          _persistState();
                        },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add another machine',
                    onPressed: _isTimerRunning
                        ? null
                        : () {
                            setState(() {
                              _extraEntries.add({
                                'machineId': null,
                                'itemId': null,
                                'operation': null,
                              });
                            });
                          },
                  ),
                ),
                if (_extraEntries.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _extraEntries.asMap().entries.map((entry) {
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
                      final ops = () {
                        if (selItem == null) return <String>[];
                        List<String> o = selItem.operations;
                        if (selItem.id == 'GR-122' && selMachine != null) {
                          if (selMachine.type == 'CNC') {
                            o = o.where((op) => op.contains('CNC')).toList();
                          } else if (selMachine.type == 'VMC') {
                            o = o.where((op) => op.contains('VMC')).toList();
                          }
                        }
                        return o;
                      }();
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Extra Machine Entry ${idx + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<Machine>(
                                decoration: InputDecoration(
                                  labelText: 'Machine ${idx + 2}',
                                  prefixIcon: const Icon(Icons.settings),
                                ),
                                initialValue: selMachine,
                                items: _machines.map((m) {
                                  return DropdownMenuItem(
                                    value: m,
                                    child: Text('${m.name} (${m.id})'),
                                  );
                                }).toList(),
                                onChanged: _isTimerRunning
                                    ? null
                                    : (Machine? v) {
                                        setState(() {
                                          data['machineId'] = v?.id;
                                          data['itemId'] = null;
                                          data['operation'] = null;
                                        });
                                      },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<Item>(
                                decoration: const InputDecoration(
                                  labelText: 'Select Item/Component',
                                  prefixIcon: Icon(Icons.inventory_2),
                                ),
                                initialValue: selItem,
                                items: _items.map((item) {
                                  return DropdownMenuItem(
                                    value: item,
                                    child: Text('${item.name} (${item.id})'),
                                  );
                                }).toList(),
                                onChanged: _isTimerRunning
                                    ? null
                                    : (Item? v) {
                                        setState(() {
                                          data['itemId'] = v?.id;
                                          data['operation'] = null;
                                        });
                                      },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Select Operation',
                                ),
                                initialValue: ops.contains(data['operation'])
                                    ? data['operation']
                                    : null,
                                items: ops
                                    .map(
                                      (op) => DropdownMenuItem(
                                        value: op,
                                        child: Text(op),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isTimerRunning
                                    ? null
                                    : (v) {
                                        setState(() {
                                          data['operation'] = v;
                                        });
                                      },
                              ),
                              if (selItem != null && data['operation'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: _buildOperationInfo(
                                    selItem,
                                    data['operation'] as String,
                                  ),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Remove',
                                  onPressed: _isTimerRunning
                                      ? null
                                      : () {
                                          setState(() {
                                            _extraEntries.removeAt(idx);
                                          });
                                        },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Item>(
                  decoration: const InputDecoration(
                    labelText: 'Select Item/Component',
                    prefixIcon: Icon(Icons.inventory_2),
                  ),
                  initialValue: _items.contains(_selectedItem)
                      ? _selectedItem
                      : null,
                  items: _items.map((item) {
                    return DropdownMenuItem(
                      value: item,
                      child: Text('${item.name} (${item.id})'),
                    );
                  }).toList(),
                  onChanged: _isTimerRunning
                      ? null
                      : (Item? newValue) {
                          setState(() {
                            _selectedItem = newValue;
                            _selectedOperation = null;
                          });
                          _persistState();
                        },
                ),
              ],
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Select Operation',
                ),
                initialValue:
                    _getFilteredOperations().contains(_selectedOperation)
                    ? _selectedOperation
                    : null,
                items: _getFilteredOperations().map((op) {
                  return DropdownMenuItem(value: op, child: Text(op));
                }).toList(),
                onChanged: _isTimerRunning
                    ? null
                    : (value) {
                        setState(() {
                          _selectedOperation = value;
                        });
                        _persistState();
                      },
              ),
              if (_selectedOperation != null) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final detail = _getCurrentOperationDetail();
                    if (detail != null &&
                        detail.imageUrl != null &&
                        detail.imageUrl!.isNotEmpty &&
                        detail.imageUrl != 'logo.png') {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Operation Image:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          detail.imageUrl!.startsWith('http')
                              ? Image.network(
                                  detail.imageUrl!,
                                  height:
                                      MediaQuery.of(context).orientation ==
                                          Orientation.landscape
                                      ? 150
                                      : 250,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return SizedBox(
                                          height:
                                              MediaQuery.of(
                                                    context,
                                                  ).orientation ==
                                                  Orientation.landscape
                                              ? 150
                                              : 250,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                            ),
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildErrorWidget();
                                  },
                                )
                              : Image.asset(
                                  'assets/images/${detail.imageUrl!}',
                                  height:
                                      MediaQuery.of(context).orientation ==
                                          Orientation.landscape
                                      ? 150
                                      : 250,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildErrorWidget();
                                  },
                                ),
                          if (detail.pdfUrl != null &&
                              detail.pdfUrl!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Center(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final url = Uri.parse(detail.pdfUrl!);
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } else {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not open document URL',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text('View Operation Document'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[700],
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          if (detail.target > 0)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.track_changes,
                                      color: Colors.blue,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'TARGET',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[700],
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        Text(
                                          '${detail.target} Units',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    } else if (detail != null && detail.target > 0) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.track_changes,
                                color: Colors.blue,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TARGET',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Text(
                                    '${detail.target} Units',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
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
                    onPressed:
                        (_selectedMachine != null &&
                            _selectedItem != null &&
                            _selectedOperation != null)
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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Production In Progress',
                            style: TextStyle(fontSize: 16, color: Colors.blue),
                          ),
                          const SizedBox(height: 10),
                          ValueListenableBuilder<Duration>(
                            valueListenable: _elapsedTimeNotifier,
                            builder: (context, elapsed, _) {
                              return Text(
                                _formatDuration(elapsed),
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Monospace',
                                ),
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
                          style: TextStyle(color: Colors.white, fontSize: 18),
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
    );
  }

  Future<List<Map<String, dynamic>>> _fetchEmployeeLogs(DateTime from) async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('production_logs')
        .select()
        .eq('worker_id', widget.employee.id)
        .eq('organization_code', widget.employee.organizationCode ?? '')
        .gte('created_at', from.toIso8601String())
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _fetchEmployeeAttendance(
    DateTime from,
  ) async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('attendance')
        .select()
        .eq('worker_id', widget.employee.id)
        .eq('organization_code', widget.employee.organizationCode ?? '')
        .gte('date', DateFormat('yyyy-MM-dd').format(from))
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  void _openProductivity() async {
    final now = DateTime.now();
    final dayFrom = DateTime(now.year, now.month, now.day);
    final weekFrom = now.subtract(const Duration(days: 6));
    final monthFrom = now.subtract(const Duration(days: 29));

    // Fetch logs
    final dayLogs = await _fetchEmployeeLogs(dayFrom);
    final weekLogs = await _fetchEmployeeLogs(weekFrom);
    final monthLogs = await _fetchEmployeeLogs(monthFrom);

    // Fetch attendance
    final dayAtt = await _fetchEmployeeAttendance(dayFrom);
    final weekAtt = await _fetchEmployeeAttendance(weekFrom);
    final monthAtt = await _fetchEmployeeAttendance(monthFrom);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String period = 'Week';
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<Map<String, dynamic>> logs;
            List<Map<String, dynamic>> att;
            if (period == 'Day') {
              logs = dayLogs;
              att = dayAtt;
            } else if (period == 'Month') {
              logs = monthLogs;
              att = monthAtt;
            } else {
              logs = weekLogs;
              att = weekAtt;
            }

            // Aggregate data by date
            final Map<String, Map<String, dynamic>> dailyData = {};

            // Initialize dailyData with attendance
            for (var a in att) {
              final dateStr = a['date']?.toString() ?? '';
              if (dateStr.isEmpty) continue;

              double hoursWorked = 0;
              if (a['check_in'] != null && a['check_out'] != null) {
                final cin = DateTime.tryParse(a['check_in'].toString());
                final cout = DateTime.tryParse(a['check_out'].toString());
                if (cin != null && cout != null) {
                  hoursWorked = cout.difference(cin).inMinutes / 60.0;
                }
              }

              dailyData[dateStr] = {
                'date': dateStr,
                'check_in': a['check_in'],
                'check_out': a['check_out'],
                'hours_worked': hoursWorked,
                'prod_time': 0.0,
                'surplus': 0,
                'deficit': 0,
                'total_qty': 0,
              };
            }

            // Add logs data
            for (var l in logs) {
              final createdAt = DateTime.tryParse(
                l['created_at']?.toString() ?? '',
              );
              if (createdAt == null) continue;
              final dateStr = DateFormat('yyyy-MM-dd').format(createdAt);

              dailyData.putIfAbsent(
                dateStr,
                () => {
                  'date': dateStr,
                  'check_in': null,
                  'check_out': null,
                  'hours_worked': 0.0,
                  'prod_time': 0.0,
                  'surplus': 0,
                  'deficit': 0,
                  'total_qty': 0,
                },
              );

              final data = dailyData[dateStr]!;

              // Production time
              if (l['startTime'] != null && l['endTime'] != null) {
                final start = DateTime.tryParse(l['startTime'].toString());
                final end = DateTime.tryParse(l['endTime'].toString());
                if (start != null && end != null) {
                  data['prod_time'] += end.difference(start).inMinutes / 60.0;
                }
              }

              // Surplus/Deficit
              final diff = (l['performance_diff'] ?? 0) as int;
              if (diff > 0) {
                data['surplus'] += diff;
              } else if (diff < 0) {
                data['deficit'] += diff.abs();
              }

              data['total_qty'] += (l['quantity'] ?? 0) as int;
            }

            final sortedDates = dailyData.keys.toList()
              ..sort((a, b) => b.compareTo(a));

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Worker Report',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      DropdownButton<String>(
                        value: period,
                        items: const [
                          DropdownMenuItem(value: 'Day', child: Text('Day')),
                          DropdownMenuItem(value: 'Week', child: Text('Week')),
                          DropdownMenuItem(
                            value: 'Month',
                            child: Text('Month'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null && context.mounted) {
                            setModalState(() => period = v);
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: sortedDates.isEmpty
                        ? const Center(
                            child: Text('No records found for this period.'),
                          )
                        : ListView.builder(
                            itemCount: sortedDates.length,
                            itemBuilder: (context, index) {
                              final date = sortedDates[index];
                              final data = dailyData[date]!;
                              final hoursWorked =
                                  data['hours_worked'] as double;
                              final prodTime = data['prod_time'] as double;
                              final surplus = data['surplus'] as int;
                              final deficit = data['deficit'] as int;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            TimeUtils.formatTo12Hour(
                                              date,
                                              format: 'EEE, MMM d, yyyy',
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (data['check_in'] != null)
                                            const Chip(
                                              label: Text(
                                                'Present',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              backgroundColor: Colors.green,
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            )
                                          else
                                            const Chip(
                                              label: Text(
                                                'Absent',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              backgroundColor: Colors.red,
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          _reportInfoTile(
                                            'Hours Worked',
                                            '${hoursWorked.toStringAsFixed(1)}h',
                                            Icons.work_outline,
                                          ),
                                          _reportInfoTile(
                                            'Prod. Time',
                                            '${prodTime.toStringAsFixed(1)}h',
                                            Icons.timer_outlined,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          _reportInfoTile(
                                            'Surplus',
                                            '+$surplus',
                                            Icons.trending_up,
                                            color: Colors.green,
                                          ),
                                          _reportInfoTile(
                                            'Deficit',
                                            '-$deficit',
                                            Icons.trending_down,
                                            color: Colors.red,
                                          ),
                                        ],
                                      ),
                                      if (data['check_in'] != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Attendance: ${TimeUtils.formatTo12Hour(data['check_in'], format: 'hh:mm a')} - '
                                          '${data['check_out'] != null ? TimeUtils.formatTo12Hour(data['check_out'], format: 'hh:mm a') : "Active"}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
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
          },
        );
      },
    );
  }

  Widget _reportInfoTile(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? Colors.blueGrey),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
