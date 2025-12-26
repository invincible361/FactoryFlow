import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/machine.dart';
import '../models/production_log.dart';
import '../models/employee.dart';
import '../models/item.dart';
import '../services/location_service.dart';
import '../services/log_service.dart';

class ProductionEntryScreen extends StatefulWidget {
  final Employee employee;
  const ProductionEntryScreen({super.key, required this.employee});

  @override
  State<ProductionEntryScreen> createState() => _ProductionEntryScreenState();
}

class _ProductionEntryScreenState extends State<ProductionEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final LocationService _locationService = LocationService();

  Machine? _selectedMachine;
  Item? _selectedItem;
  String? _selectedOperation;
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

  // Timer State
  Timer? _timer;
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  bool _isTimerRunning = false;
  String? _factoryName;
  String? _logoUrl;
  String? _currentLogId;
  Widget _metricTile(String title, String value, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
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
    _fetchData();
    _checkLocation();
    _fetchOrganizationName();
    _fetchTodayExtraUnits();
    // Start a timer to refresh the current time display
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final machineId = prefs.getString('persisted_machine_id');
      final itemId = prefs.getString('persisted_item_id');
      final operation = prefs.getString('persisted_operation');
      final shift = prefs.getString('persisted_shift');
      final startTimeStr = prefs.getString('persisted_start_time');
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

          if (isTimerRunning && startTimeStr != null) {
            _startTime = DateTime.parse(startTimeStr);
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
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
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
      } else {
        await prefs.remove('persisted_start_time');
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
          .eq('organization_code', widget.employee.organizationCode!);
      final machinesList = (machinesResponse as List).map((data) {
        return Machine(
          id: data['machine_id'],
          name: data['name'],
          type: data['type'] == 'CNC' ? MachineType.cnc : MachineType.vmc,
          items:
              [], // Will link items later if needed, or keep empty for now as selection is separate
        );
      }).toList();

      // Fetch Items
      final itemsResponse = await supabase
          .from('items')
          .select()
          .eq('organization_code', widget.employee.organizationCode!);
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
          .eq('organization_code', widget.employee.organizationCode!);
      final shiftsList = List<Map<String, dynamic>>.from(shiftsResponse);

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
    _timer?.cancel();
    _quantityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _checkLocation() async {
    setState(() {
      _isLocationLoading = true;
      _locationStatus = 'Fetching location...';
    });

    try {
      final position = await _locationService.getCurrentLocation();
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
          isInside = _locationService.isInside(position, lat, lng, radius);
        } else {
          isInside = false;
        }
      } catch (_) {
        isInside = false;
      }

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _locationStatus = isInside ? 'Inside Factory ✅' : 'Outside Factory ❌';
        });
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
        remarks: 'Production started...',
      );
      await LogService().addLog(initialLog);
    } catch (e) {
      debugPrint('Error saving initial log: $e');
    }

    _persistState();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
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
            return shift['name'] + ' (' + startStr + ' - ' + endStr + ')';
          }
        } else {
          // Crosses midnight
          if (minutes >= startMinutes || minutes < endMinutes) {
            return shift['name'] + ' (' + startStr + ' - ' + endStr + ')';
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

  void _stopTimerAndFinish() {
    _timer?.cancel();
    final endTime = DateTime.now();

    // Show dialog to enter quantity
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final currentContext = context;
        return AlertDialog(
          title: const Text('Production Finished'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Duration: ${_formatDuration(_elapsed)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Enter Quantity Produced',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _remarksController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  hintText: 'Add any issues or notes here...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.comment),
                ),
              ),
            ],
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
                if (_quantityController.text.isEmpty) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(content: Text('Please enter quantity')),
                  );
                  return;
                }
                final quantity = int.tryParse(_quantityController.text);
                if (quantity == null) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(content: Text('Invalid quantity')),
                  );
                  return;
                }

                // Target Validation
                final detail = _getCurrentOperationDetail();
                if (detail != null && detail.target > 0) {
                  final diff = quantity - detail.target;
                  final isTargetMet = diff >= 0;

                  Navigator.pop(currentContext); // Close input dialog

                  // Show Result Dialog
                  showDialog(
                    context: currentContext,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: Text(
                        isTargetMet ? 'Target Met! 🎉' : 'Target Missed ⚠️',
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          isTargetMet
                              ? const Icon(
                                  Icons.sentiment_very_satisfied,
                                  size: 60,
                                  color: Colors.green,
                                )
                              : const Icon(
                                  Icons.sentiment_dissatisfied,
                                  size: 60,
                                  color: Colors.orange,
                                ),
                          const SizedBox(height: 16),
                          Text(
                            isTargetMet
                                ? 'Produced: $quantity (Target: ${detail.target})\nSurplus: +$diff'
                                : 'Produced: $quantity (Target: ${detail.target})\nDeficit: $diff',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isTargetMet ? Colors.green : Colors.red,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _saveLog(endTime, diff);
                          },
                          child: const Text('Save Log'),
                        ),
                      ],
                    ),
                  );
                } else {
                  Navigator.pop(currentContext);
                  _saveLog(endTime, 0);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _saveLog(DateTime endTime, int performanceDiff) async {
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
        quantity: int.parse(_quantityController.text),
        timestamp: DateTime.now(),
        startTime: _startTime,
        endTime: endTime,
        latitude: position.latitude,
        longitude: position.longitude,
        shiftName:
            _selectedShift ?? _getShiftName(_startTime ?? DateTime.now()),
        performanceDiff: performanceDiff,
        organizationCode: widget.employee.organizationCode,
        remarks: _remarksController.text.isNotEmpty
            ? _remarksController.text
            : null,
      );

      await LogService().addLog(log);

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
      if (_selectedMachine!.type == MachineType.cnc) {
        ops = ops.where((op) => op.contains('CNC')).toList();
      } else if (_selectedMachine!.type == MachineType.vmc) {
        ops = ops.where((op) => op.contains('VMC')).toList();
      }
    }
    return ops;
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
                const Text('Log Production'),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                'Welcome, ${widget.employee.name}${_factoryName != null && _factoryName!.isNotEmpty ? ' — $_factoryName' : ''}',
                style: const TextStyle(fontSize: 12),
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
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.0,
                children: [
                  _metricTile(
                    'Current Time',
                    DateFormat('hh:mm:ss a').format(DateTime.now()),
                    Colors.blue.shade100,
                    Icons.access_time,
                  ),
                  _metricTile(
                    'Shift Timer',
                    _isTimerRunning
                        ? '${_elapsed.inHours}h ${_elapsed.inMinutes % 60}m'
                        : 'Not started',
                    Colors.orange.shade100,
                    Icons.timer,
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
                DropdownButtonFormField<Machine>(
                  decoration: const InputDecoration(
                    labelText: 'Select Machine',
                  ),
                  initialValue: _selectedMachine,
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
                const SizedBox(height: 16),
                DropdownButtonFormField<Item>(
                  decoration: const InputDecoration(
                    labelText: 'Select Item/Component',
                  ),
                  initialValue: _selectedItem,
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Select Shift'),
                  initialValue: _selectedShift,
                  items: _shifts.map((s) {
                    final name = s['name']?.toString() ?? '';
                    return DropdownMenuItem(value: name, child: Text(name));
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
              ],
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Select Operation',
                ),
                initialValue: _selectedOperation,
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
                                  height: 250,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return SizedBox(
                                          height: 250,
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
                                  height: 250,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildErrorWidget();
                                  },
                                ),
                          if (detail.target > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Target: ${detail.target}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                        ],
                      );
                    } else if (detail != null && detail.target > 0) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Target: ${detail.target}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
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
                          Text(
                            _formatDuration(_elapsed),
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Monospace',
                            ),
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

  void _openProductivity() async {
    final now = DateTime.now();
    final dayFrom = DateTime(now.year, now.month, now.day);
    final weekFrom = now.subtract(const Duration(days: 6));
    final monthFrom = now.subtract(const Duration(days: 29));
    final dayLogs = await _fetchEmployeeLogs(dayFrom);
    final weekLogs = await _fetchEmployeeLogs(weekFrom);
    final monthLogs = await _fetchEmployeeLogs(monthFrom);
    final extraWeeks = await _fetchEmployeeLogs(
      now.subtract(const Duration(days: 7 * 8)),
    );
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String period = 'Week';
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<Map<String, dynamic>> logs;
            if (period == 'Day') {
              logs = dayLogs;
            } else if (period == 'Month') {
              logs = monthLogs;
            } else {
              logs = weekLogs;
            }
            List<BarChartGroupData> groups = [];
            if (period == 'Day') {
              final buckets = List<double>.filled(24, 0);
              for (final l in logs) {
                final t = DateTime.tryParse(
                  (l['created_at'] ?? '').toString(),
                )?.toLocal();
                if (t != null) {
                  buckets[t.hour] += (l['quantity'] ?? 0) * 1.0;
                }
              }
              for (int i = 0; i < buckets.length; i++) {
                groups.add(
                  BarChartGroupData(
                    x: i,
                    barRods: [BarChartRodData(toY: buckets[i])],
                  ),
                );
              }
            } else {
              int days = period == 'Week' ? 7 : 30;
              final buckets = List<double>.filled(days, 0);
              for (final l in logs) {
                final t = DateTime.tryParse(
                  (l['created_at'] ?? '').toString(),
                )?.toLocal();
                if (t != null) {
                  final idx = period == 'Week'
                      ? now.difference(t).inDays
                      : now.difference(t).inDays;
                  final pos = days - 1 - idx;
                  if (pos >= 0 && pos < days) {
                    buckets[pos] += (l['quantity'] ?? 0) * 1.0;
                  }
                }
              }
              for (int i = 0; i < buckets.length; i++) {
                groups.add(
                  BarChartGroupData(
                    x: i,
                    barRods: [BarChartRodData(toY: buckets[i])],
                  ),
                );
              }
            }

            final extraBuckets = List<double>.filled(8, 0);
            for (final l in extraWeeks) {
              final t = DateTime.tryParse(
                (l['created_at'] ?? '').toString(),
              )?.toLocal();
              if (t != null) {
                final wStart = DateTime(
                  t.year,
                  t.month,
                  t.day,
                ).subtract(Duration(days: t.weekday - 1));
                final weeksAgo =
                    DateTime(
                      now.year,
                      now.month,
                      now.day,
                    ).difference(wStart).inDays ~/
                    7;
                final pos = 7 - weeksAgo;
                final diff = (l['performance_diff'] ?? 0) as int;
                if (diff > 0 && pos >= 0 && pos < 8) {
                  extraBuckets[pos] += diff * 1.0;
                }
              }
            }
            final extraGroups = [
              for (int i = 0; i < extraBuckets.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(toY: extraBuckets[i], color: Colors.green),
                  ],
                ),
            ];

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Productivity',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      DropdownButton<String>(
                        value: period,
                        items: const [
                          DropdownMenuItem<String>(
                            value: 'Day',
                            child: Text('Day'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'Week',
                            child: Text('Week'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'Month',
                            child: Text('Month'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => period = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 240,
                    child: BarChart(
                      BarChartData(
                        barGroups: groups,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if (period == 'Day') {
                                  if (v % 3 != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  final hour = v % 12 == 0 ? 12 : v % 12;
                                  final amPm = v < 12 ? 'AM' : 'PM';
                                  return Text(
                                    '$hour $amPm',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                } else if (period == 'Week') {
                                  if ((v + 1) % 2 != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(
                                    '${v + 1}',
                                    style: const TextStyle(fontSize: 11),
                                  );
                                } else {
                                  if ((v + 1) % 5 != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(
                                    '${v + 1}',
                                    style: const TextStyle(fontSize: 11),
                                  );
                                }
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Weekly Extra Work',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        barGroups: extraGroups,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  'W${v + 1}',
                                  style: const TextStyle(fontSize: 11),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                      ),
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
}
