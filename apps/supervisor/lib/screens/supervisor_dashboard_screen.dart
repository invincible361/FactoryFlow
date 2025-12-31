import 'dart:async';
import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';

class SupervisorDashboardScreen extends StatefulWidget {
  final String organizationCode;
  final String supervisorName;
  const SupervisorDashboardScreen({
    super.key,
    required this.organizationCode,
    required this.supervisorName,
  });

  @override
  State<SupervisorDashboardScreen> createState() =>
      _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _selectedWorkerId;
  DateTimeRange? _dateRange;
  String? _photoUrl;
  String _currentShift = 'Detecting...';
  String _currentShiftTime = '';
  bool? _isInside;
  Timer? _statusTimer;
  double? _orgLat;
  double? _orgLng;
  double? _orgRadius;

  @override
  void initState() {
    super.initState();
    _fetchSupervisorPhoto();
    _fetchOrgConfig().then((_) => _updateStatus());
    _fetchLogs();
    _statusTimer = Timer.periodic(
      const Duration(minutes: 2),
      (t) => _updateStatus(),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrgConfig() async {
    try {
      final org = await _supabase
          .from('organizations')
          .select()
          .eq('organization_code', widget.organizationCode)
          .maybeSingle();
      if (org != null && mounted) {
        setState(() {
          _orgLat = (org['latitude'] ?? 0.0) * 1.0;
          _orgLng = (org['longitude'] ?? 0.0) * 1.0;
          _orgRadius = (org['radius_meters'] ?? 500.0) * 1.0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching org config: $e');
    }
  }

  Future<void> _updateStatus() async {
    if (!mounted) return;

    // 1. Update Shift
    try {
      final now = DateTime.now();
      final shiftsResp = await _supabase
          .from('shifts')
          .select()
          .eq('organization_code', widget.organizationCode);

      debugPrint(
        'DEBUG: Found ${shiftsResp.length} shifts for org ${widget.organizationCode}',
      );

      String foundShift = 'No Active Shift';
      String foundShiftTime = '';

      for (var s in (shiftsResp as List)) {
        try {
          final startStr = (s['start_time'] as String).trim();
          final endStr = (s['end_time'] as String).trim();
          debugPrint(
            'DEBUG: Checking shift "${s['name']}" : $startStr to $endStr',
          );

          // Try multiple formats
          DateTime? startTime;
          DateTime? endTime;
          DateTime? nowTimeParsed;

          // Re-ordered formats to prioritize AM/PM if present
          final formats = [
            DateFormat("hh:mm a"),
            DateFormat("h:mm a"),
            DateFormat("HH:mm"),
            DateFormat("H:mm"),
            DateFormat("HH:mm:ss"),
          ];

          for (var fmt in formats) {
            try {
              final sParsed = fmt.parse(startStr);
              final eParsed = fmt.parse(endStr);
              // If both parse successfully with the same format, we use it
              startTime = sParsed;
              endTime = eParsed;
              nowTimeParsed = fmt.parse(fmt.format(now));
              break;
            } catch (_) {
              continue;
            }
          }

          if (startTime != null && endTime != null && nowTimeParsed != null) {
            bool isActive = false;
            // Normalize all to the same date for comparison
            final baseDate = DateTime(2000, 1, 1);
            final start = DateTime(
              baseDate.year,
              baseDate.month,
              baseDate.day,
              startTime.hour,
              startTime.minute,
            );
            var end = DateTime(
              baseDate.year,
              baseDate.month,
              baseDate.day,
              endTime.hour,
              endTime.minute,
            );
            final current = DateTime(
              baseDate.year,
              baseDate.month,
              baseDate.day,
              nowTimeParsed.hour,
              nowTimeParsed.minute,
            );

            if (end.isBefore(start)) {
              // Overnight shift
              isActive =
                  current.isAfter(start) ||
                  current.isBefore(end) ||
                  current.isAtSameMomentAs(start) ||
                  current.isAtSameMomentAs(end);
              debugPrint(
                'DEBUG: Overnight shift check: $current vs $start-$end -> $isActive',
              );
            } else {
              isActive =
                  (current.isAfter(start) || current.isAtSameMomentAs(start)) &&
                  (current.isBefore(end) || current.isAtSameMomentAs(end));
              debugPrint(
                'DEBUG: Normal shift check: $current vs $start-$end -> $isActive',
              );
            }

            if (isActive) {
              foundShift = s['name'] ?? 'Unnamed Shift';
              foundShiftTime = '$startStr - $endStr';
              debugPrint('DEBUG: Found active shift: $foundShift');
              break;
            }
          } else {
            debugPrint(
              'DEBUG: Failed to parse times for shift ${s['name']}. Start: $startStr, End: $endStr',
            );
          }
        } catch (e) {
          debugPrint('Error parsing shift $s: $e');
        }
      }

      if (mounted) {
        setState(() {
          _currentShift = foundShift;
          _currentShiftTime = foundShiftTime;
        });
      }
    } catch (e) {
      debugPrint('Error updating shift: $e');
    }

    // 2. Update Location
    try {
      final pos = await LocationService().getCurrentLocation();
      if (_orgLat != null && _orgLng != null && _orgRadius != null) {
        final inside = LocationService().isInside(
          pos,
          _orgLat!,
          _orgLng!,
          _orgRadius!,
        );
        if (mounted) setState(() => _isInside = inside);
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
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

  Future<void> _fetchSupervisorPhoto() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select()
          .eq('organization_code', widget.organizationCode)
          .eq('name', widget.supervisorName)
          .maybeSingle();
      if (resp != null) {
        setState(() {
          _photoUrl = _getFirstNotEmpty(resp, [
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
      // ignore, fallback to icon
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _loading = true);
    try {
      var builder = _supabase
          .from('production_logs')
          .select('*, workers:worker_id(name)')
          .eq('organization_code', widget.organizationCode)
          .or('is_verified.is.false,is_verified.is.null')
          .gt('quantity', 0);
      if (_selectedWorkerId != null) {
        builder = builder.eq('worker_id', _selectedWorkerId!);
      }
      if (_dateRange != null) {
        builder = builder
            .gte('created_at', _dateRange!.start.toIso8601String())
            .lte('created_at', _dateRange!.end.toIso8601String());
      }
      final response = await builder.order('created_at', ascending: false);
      setState(() {
        _logs = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      try {
        // Fallback 1: remove relationship join, keep is_verified filter and quantity > 0
        var builder = _supabase
            .from('production_logs')
            .select()
            .eq('organization_code', widget.organizationCode)
            .or('is_verified.is.false,is_verified.is.null')
            .gt('quantity', 0);
        if (_selectedWorkerId != null) {
          builder = builder.eq('worker_id', _selectedWorkerId!);
        }
        if (_dateRange != null) {
          builder = builder
              .gte('created_at', _dateRange!.start.toIso8601String())
              .lte('created_at', _dateRange!.end.toIso8601String());
        }
        final response = await builder.order('created_at', ascending: false);
        setState(() {
          _logs = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      } catch (_) {
        try {
          // Fallback 2: remove is_verified filter in case column isn't present, still only quantity > 0
          var builder = _supabase
              .from('production_logs')
              .select()
              .eq('organization_code', widget.organizationCode)
              .gt('quantity', 0);
          if (_selectedWorkerId != null) {
            builder = builder.eq('worker_id', _selectedWorkerId!);
          }
          if (_dateRange != null) {
            builder = builder
                .gte('created_at', _dateRange!.start.toIso8601String())
                .lte('created_at', _dateRange!.end.toIso8601String());
          }
          final response = await builder.order('created_at', ascending: false);
          setState(() {
            _logs = List<Map<String, dynamic>>.from(response);
            _loading = false;
          });
        } catch (_) {
          setState(() => _loading = false);
        }
      }
    }
  }

  Future<void> _verifyLog(Map<String, dynamic> log) async {
    try {
      final qtyController = TextEditingController(
        text: (log['supervisor_quantity'] ?? log['quantity'] ?? 0).toString(),
      );
      final noteController = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Verify Production'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Worker: ${(log['workers']?['name'] ?? log['worker_id']).toString()}',
                ),
                Text('Machine: ${log['machine_id']}'),
                Text('Item: ${log['item_id']}'),
                Text('Operation: ${log['operation']}'),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Supervisor Quantity',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Supervisor Remark',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newQty = int.tryParse(qtyController.text);
                  if (mounted) Navigator.pop(ctx);
                  await LogService().verifyLog(
                    logId: log['id'].toString(),
                    supervisorName: widget.supervisorName,
                    note: noteController.text.isNotEmpty
                        ? noteController.text
                        : null,
                    supervisorQuantity: newQty,
                  );
                  await _fetchLogs();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Production verified')),
                    );
                  }
                },
                child: const Text('Verify'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _metricTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: Colors.black87),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.0,
        children: [
          _metricTile(
            'Current Shift',
            _currentShift,
            Colors.blue.shade50,
            Icons.schedule,
          ),
          _metricTile(
            'Shift Timings',
            _currentShiftTime.isEmpty ? 'N/A' : _currentShiftTime,
            Colors.orange.shade50,
            Icons.timer,
          ),
          _metricTile(
            'Location Status',
            _isInside == null
                ? 'Determining...'
                : (_isInside! ? 'Inside Factory' : 'Outside Factory'),
            _isInside == true ? Colors.green.shade50 : Colors.red.shade50,
            _isInside == true ? Icons.location_on : Icons.location_off,
          ),
          _metricTile(
            'Current Time',
            DateFormat('hh:mm a').format(DateTime.now()),
            Colors.teal.shade50,
            Icons.access_time,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor App'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey[300],
              backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                  ? NetworkImage(_photoUrl!)
                  : null,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 16, color: Colors.black54)
                  : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchLogs,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                ? const Center(child: Text('No pending logs to verify'))
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final worker = log['workers'] as Map<String, dynamic>?;
                      final workerName =
                          worker?['name'] ??
                          (log['worker_id']?.toString() ?? 'Unknown');
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text('$workerName — ${log['operation']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Machine: ${log['machine_id']} | Item: ${log['item_id']}',
                              ),
                              Text('Quantity: ${log['quantity']}'),
                              Text(
                                'Time: ${TimeUtils.formatTo12Hour(log['start_time'], format: 'hh:mm a')} - ${TimeUtils.formatTo12Hour(log['end_time'], format: 'hh:mm a')}',
                              ),
                              if ((log['remarks'] ?? '').toString().isNotEmpty)
                                Text('Remarks: ${log['remarks']}'),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _verifyLog(log),
                            child: const Text('Verify'),
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
}
