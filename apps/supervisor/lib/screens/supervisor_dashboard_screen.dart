import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart' as uuid;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'help_screen.dart';

class SupervisorDashboardScreen extends StatefulWidget {
  final String organizationCode;
  final String supervisorName;
  final bool isDarkMode;
  const SupervisorDashboardScreen({
    super.key,
    required this.organizationCode,
    required this.supervisorName,
    this.isDarkMode = false,
  });

  @override
  State<SupervisorDashboardScreen> createState() =>
      _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _notifications = [];
  Map<String, bool> _workerLocationStatus = {};
  String _workerLocationFilter = 'All';
  bool _loading = true;
  bool _isExporting = false;
  String? _selectedWorkerId;
  DateTimeRange? _dateRange;
  String _reportType = 'Day';
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
    _fetchAssignmentData();
    _fetchNotifications();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      _updateStatus();
      _fetchNotifications();
      _updateWorkerLocations();
    });
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
          _orgRadius =
              (org['radius_meters'] ?? 500.0) *
              1.1; // Reduced buffer for better accuracy (was 1.5)
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
          .select(
            'worker_id, photo_url, avatar_url, image_url, imageurl, photourl, picture_url',
          )
          .eq('organization_code', widget.organizationCode)
          .eq('name', widget.supervisorName)
          .maybeSingle();
      if (resp != null) {
        setState(() {
          _selectedWorkerId = resp['worker_id']?.toString();
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

  Future<void> _updateWorkerLocations() async {
    try {
      final boundaryEvents = await _supabase
          .from('worker_boundary_events')
          .select('worker_id, type')
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(200);

      final Map<String, bool> locations = {};
      for (var event in (boundaryEvents as List)) {
        final id = event['worker_id'].toString();
        if (!locations.containsKey(id)) {
          locations[id] = event['type'] != 'exit';
        }
      }

      if (mounted) {
        setState(() {
          _workerLocationStatus = locations;
        });
      }
    } catch (e) {
      debugPrint('Error updating worker locations: $e');
    }
  }

  Future<void> _fetchAssignmentData() async {
    try {
      final workers = await _supabase
          .from('workers')
          .select()
          .eq('organization_code', widget.organizationCode)
          .neq('role', 'supervisor')
          .order('name');

      final machines = await _supabase
          .from('machines')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name');

      final items = await _supabase
          .from('items')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name');

      await _updateWorkerLocations();

      if (mounted) {
        setState(() {
          _workers = List<Map<String, dynamic>>.from(workers);
          _machines = List<Map<String, dynamic>>.from(machines);
          _items = List<Map<String, dynamic>>.from(items);
        });
      }
    } catch (e) {
      debugPrint('Error fetching assignment data: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchProductionForAttendance(
    String workerId,
    String date,
  ) async {
    try {
      // Filter by date in database for better performance and accuracy
      // We use start of day and end of day in ISO format
      final response = await _supabase
          .from('production_logs')
          .select('*, machines(name), items(name)')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('start_time', '${date}T00:00:00Z')
          .lte('start_time', '${date}T23:59:59Z')
          .order('start_time', ascending: true);

      final rawLogs = List<Map<String, dynamic>>.from(response);

      // Also try without 'Z' just in case
      if (rawLogs.isEmpty) {
        final altResponse = await _supabase
            .from('production_logs')
            .select('*, machines(name), items(name)')
            .eq('worker_id', workerId)
            .eq('organization_code', widget.organizationCode)
            .gte('start_time', '${date}T00:00:00')
            .lte('start_time', '${date}T23:59:59')
            .order('start_time', ascending: true);
        rawLogs.addAll(List<Map<String, dynamic>>.from(altResponse));
      }

      final filtered = rawLogs.map((log) {
        // Flatten machine and item names
        final machine = log['machines'] as Map<String, dynamic>?;
        final item = log['items'] as Map<String, dynamic>?;
        return {
          ...log,
          'machine_name': machine?['name'],
          'item_name': item?['name'],
        };
      }).toList();

      return filtered;
    } catch (e) {
      debugPrint('Error fetching production for attendance: $e');
      return [];
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Efficiency Report');
      final sheet = excel['Efficiency Report'];

      // Add Headers
      sheet.appendRow([
        TextCellValue('Date'),
        TextCellValue('Shift'),
        TextCellValue('Operator ID'),
        TextCellValue('Operator Name'),
        TextCellValue('In Time'),
        TextCellValue('Out Time'),
        TextCellValue('Machine'),
        TextCellValue('Item'),
        TextCellValue('Operation'),
        TextCellValue('Worker Qty'),
        TextCellValue('Verified Qty'),
        TextCellValue('Performance Diff'),
        TextCellValue('Remarks'),
      ]);

      // Handle Date Range based on report type if not manually set
      DateTime start = _dateRange?.start ?? DateTime.now();
      DateTime end = _dateRange?.end ?? DateTime.now();

      if (_dateRange == null) {
        if (_reportType == 'Week') {
          start = DateTime.now().subtract(const Duration(days: 7));
        } else if (_reportType == 'Month') {
          start = DateTime.now().subtract(const Duration(days: 30));
        } else {
          start = DateTime.now();
        }
        end = DateTime.now();
      }

      // Fetch attendance records for the selected date range or today
      var query = _supabase
          .from('attendance')
          .select('*, workers(name)')
          .eq('organization_code', widget.organizationCode);

      query = query
          .gte('date', DateFormat('yyyy-MM-dd').format(start))
          .lte('date', DateFormat('yyyy-MM-dd').format(end));

      final attendanceResponse = await query.order('date', ascending: false);
      final attendanceList = List<Map<String, dynamic>>.from(
        attendanceResponse,
      );

      for (var record in attendanceList) {
        final worker = record['workers'] as Map<String, dynamic>?;
        final workerName = worker?['name'] ?? 'Unknown';
        final workerId = record['worker_id'].toString();
        final dateStr = record['date'];
        final shiftName = record['shift_name'];

        final logs = await _fetchProductionForAttendance(workerId, dateStr);

        if (logs.isEmpty) {
          sheet.appendRow([
            TextCellValue(dateStr),
            TextCellValue(shiftName ?? 'N/A'),
            TextCellValue(workerId),
            TextCellValue(workerName),
            TextCellValue(TimeUtils.formatTo12Hour(record['check_in'])),
            TextCellValue(TimeUtils.formatTo12Hour(record['check_out'])),
            TextCellValue('N/A'),
            TextCellValue('N/A'),
            TextCellValue('N/A'),
            const IntCellValue(0),
            const IntCellValue(0),
            const IntCellValue(0),
            TextCellValue(record['remarks'] ?? ''),
          ]);
        } else {
          for (var log in logs) {
            sheet.appendRow([
              TextCellValue(dateStr),
              TextCellValue(shiftName ?? 'N/A'),
              TextCellValue(workerId),
              TextCellValue(workerName),
              TextCellValue(TimeUtils.formatTo12Hour(record['check_in'])),
              TextCellValue(TimeUtils.formatTo12Hour(record['check_out'])),
              TextCellValue(log['machine_name'] ?? log['machine_id'] ?? 'N/A'),
              TextCellValue(log['item_name'] ?? log['item_id'] ?? 'N/A'),
              TextCellValue(log['operation'] ?? 'N/A'),
              IntCellValue(log['quantity'] ?? 0),
              IntCellValue(log['supervisor_quantity'] ?? 0),
              IntCellValue(log['performance_diff'] ?? 0),
              TextCellValue(log['remarks'] ?? ''),
            ]);
          }
        }
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final fileName = 'Supervisor_Efficiency_Report_$timestamp.xlsx';

        if (kIsWeb) {
          await WebDownloadHelper.download(
            fileBytes,
            fileName,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
        } else {
          final directory = await getTemporaryDirectory();
          final file = io.File('${directory.path}/$fileName');
          await file.writeAsBytes(fileBytes);

          if (mounted) {
            await share_plus.Share.shareXFiles([
              share_plus.XFile(file.path),
            ], text: 'Worker Efficiency Report');
          }
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _showWorkerDetailsDialog(
    Map<String, dynamic> worker,
    Map<String, dynamic>? status,
  ) async {
    final workerId = worker['worker_id'].toString();
    final isDark = widget.isDarkMode;
    final isInside = status?['is_inside'] ?? false;

    // Fetch history
    final historyResponse = await _supabase
        .from('production_logs')
        .select()
        .eq('worker_id', workerId)
        .order('start_time', ascending: false)
        .limit(10);

    final history = List<Map<String, dynamic>>.from(historyResponse);

    // Calculate Efficiency (example: units per hour vs target)
    double totalEfficiency = 0;
    if (history.isNotEmpty) {
      int efficientLogs = 0;
      for (var log in history) {
        final diff = (log['performance_diff'] ?? 0) as int;
        if (diff >= 0) efficientLogs++;
      }
      totalEfficiency = (efficientLogs / history.length) * 100;
    }

    // Get latest location for map
    final lastLocation = await _supabase
        .from('worker_boundary_events')
        .select()
        .eq('worker_id', workerId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: isInside ? Colors.green : Colors.red,
                radius: 6,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  worker['name'] ?? 'Worker Details',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailRow(
                    'Location',
                    isInside ? 'Inside Factory ✅' : 'Outside Factory ❌',
                    isInside ? Colors.green : Colors.red,
                  ),
                  _detailRow(
                    'Efficiency',
                    '${totalEfficiency.toStringAsFixed(1)}%',
                    totalEfficiency > 80 ? Colors.green : Colors.orange,
                  ),
                  const Divider(height: 24),
                  Text(
                    'Current Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (lastLocation != null &&
                      lastLocation['latitude'] != null) ...[
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.map,
                            size: 40,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Lat: ${lastLocation['latitude']}, Lng: ${lastLocation['longitude']}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final lat = lastLocation['latitude'];
                              final lng = lastLocation['longitude'];
                              final url = Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                              );
                              final messenger = ScaffoldMessenger.of(context);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not open the map.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('View on Google Maps'),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    const Text('No location data available'),
                  const Divider(height: 24),
                  Text(
                    'Recent History',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (history.isEmpty)
                    const Text('No recent production logs')
                  else
                    ...history.map((log) {
                      final hasRemarks =
                          log['remarks'] != null &&
                          log['remarks'].toString().isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${log['operation']} (${log['item_id']})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Qty: ${log['quantity']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            if (hasRemarks)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Remark: ${log['remarks']}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.orangeAccent,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showAssignWorkDialog(preSelectedWorkerId: workerId);
              },
              child: const Text('Assign Work'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: widget.isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogProductionDialog({String? preSelectedWorkerId}) async {
    String? selectedWorkerId = preSelectedWorkerId;
    String? selectedMachineId;
    String? selectedItemId;
    String? selectedOperation;
    List<String> operations = [];
    final qtyController = TextEditingController();
    final remarksController = TextEditingController();
    final isDark = widget.isDarkMode;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              title: Text(
                'Log Production for Worker',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedWorkerId,
                      decoration: InputDecoration(
                        labelText: 'Select Worker',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                      ),
                      items: _workers.map((w) {
                        return DropdownMenuItem(
                          value: w['worker_id'].toString(),
                          child: Text(
                            w['name'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedWorkerId = val),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedMachineId,
                      decoration: InputDecoration(
                        labelText: 'Select Machine',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                      ),
                      items: _machines.map((m) {
                        return DropdownMenuItem(
                          value: m['machine_id'].toString(),
                          child: Text(
                            m['name'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedMachineId = val),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedItemId,
                      decoration: InputDecoration(
                        labelText: 'Select Item',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                      ),
                      items: _items.map((i) {
                        return DropdownMenuItem(
                          value: i['item_id'].toString(),
                          child: Text(
                            i['name'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedItemId = val;
                          selectedOperation = null;
                          final item = _items.firstWhere(
                            (it) => it['item_id'] == val,
                          );
                          operations = List<String>.from(
                            item['operations'] ?? [],
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedOperation,
                      decoration: InputDecoration(
                        labelText: 'Select Operation',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                      ),
                      items: operations.map((op) {
                        return DropdownMenuItem(
                          value: op,
                          child: Text(
                            op,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedOperation = val),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: remarksController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Remarks',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.blue[300] : Colors.blue,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                      (selectedWorkerId == null ||
                          selectedMachineId == null ||
                          selectedItemId == null ||
                          selectedOperation == null)
                      ? null
                      : () async {
                          try {
                            final qty = int.tryParse(qtyController.text) ?? 0;
                            if (qty <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please enter a valid quantity',
                                  ),
                                ),
                              );
                              return;
                            }

                            final log = ProductionLog(
                              id: const uuid.Uuid().v4(),
                              employeeId: selectedWorkerId!,
                              machineId: selectedMachineId!,
                              itemId: selectedItemId!,
                              operation: selectedOperation!,
                              quantity: qty,
                              timestamp: DateTime.now(),
                              startTime: DateTime.now(),
                              endTime: DateTime.now(),
                              latitude: _orgLat ?? 0.0,
                              longitude: _orgLng ?? 0.0,
                              organizationCode: widget.organizationCode,
                              remarks: remarksController.text,
                              createdBySupervisor: true,
                              supervisorId: widget.supervisorName,
                            );

                            await LogService().addLog(log);

                            if (!context.mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Production logged by supervisor',
                                ),
                              ),
                            );
                            _fetchLogs();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                  child: const Text('Log Production'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignWorkDialog({String? preSelectedWorkerId}) async {
    String? selectedWorkerId = preSelectedWorkerId;
    String? selectedMachineId;
    String? selectedItemId;
    String? selectedOperation;
    List<String> operations = [];
    final isDark = widget.isDarkMode;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              title: Text(
                'Assign Work',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedWorkerId,
                      decoration: InputDecoration(
                        labelText: 'Select Worker',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                        ),
                      ),
                      items: _workers.map((w) {
                        return DropdownMenuItem(
                          value: w['worker_id'].toString(),
                          child: Text(
                            w['name'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedWorkerId = val),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedMachineId,
                      decoration: InputDecoration(
                        labelText: 'Select Machine',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                        ),
                      ),
                      items: _machines.map((m) {
                        return DropdownMenuItem(
                          value: m['machine_id'].toString(),
                          child: Text(
                            m['name'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedMachineId = val),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedItemId,
                      decoration: InputDecoration(
                        labelText: 'Select Item',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                        ),
                      ),
                      items: _items.map((i) {
                        return DropdownMenuItem(
                          value: i['item_id'].toString(),
                          child: Text(
                            i['name'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedItemId = val;
                          selectedOperation = null;
                          final item = _items.firstWhere(
                            (it) => it['item_id'] == val,
                          );
                          operations = List<String>.from(
                            item['operations'] ?? [],
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: isDark ? Colors.grey[850] : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      initialValue: selectedOperation,
                      decoration: InputDecoration(
                        labelText: 'Select Operation',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                        ),
                      ),
                      items: operations.map((op) {
                        return DropdownMenuItem(
                          value: op,
                          child: Text(
                            op,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedOperation = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.blue[300] : Colors.blue,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? Colors.white10
                        : Colors.grey[300],
                  ),
                  onPressed:
                      (selectedWorkerId == null ||
                          selectedMachineId == null ||
                          selectedItemId == null ||
                          selectedOperation == null)
                      ? null
                      : () async {
                          try {
                            await _supabase.from('work_assignments').insert({
                              'organization_code': widget.organizationCode,
                              'worker_id': selectedWorkerId,
                              'machine_id': selectedMachineId,
                              'item_id': selectedItemId,
                              'operation': selectedOperation,
                              'assigned_by': widget.supervisorName,
                              'status': 'pending',
                            });
                            if (!context.mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Work assigned successfully'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                  child: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _fetchNotifications() async {
    try {
      final resp = await _supabase
          .from('notifications')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(resp);
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
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
    final isDark = widget.isDarkMode;
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
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            title: Text(
              'Verify Production',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    final worker = log['workers'] as Map<String, dynamic>?;
                    String workerName = worker?['name']?.toString() ?? '';
                    if (workerName.isEmpty) {
                      final localWorker = _workers.firstWhere(
                        (w) =>
                            w['worker_id'].toString() ==
                            log['worker_id'].toString(),
                        orElse: () => {},
                      );
                      workerName =
                          localWorker['name']?.toString() ??
                          log['worker_id']?.toString() ??
                          'Unknown';
                    }
                    return Text(
                      'Worker: $workerName',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    );
                  },
                ),
                Text(
                  'Machine: ${log['machine_id']}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                Text(
                  'Item: ${log['item_id']}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                Text(
                  'Operation: ${log['operation']}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Supervisor Quantity',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.black54,
                    ),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Supervisor Remark',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.black54,
                    ),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.blue[300] : Colors.blue,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
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
                      const SnackBar(
                        content: Text('Work completed and verified'),
                      ),
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
    final isDark = widget.isDarkMode;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 24,
            color: isDark ? Colors.blue[300] : Colors.black87,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey[400] : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
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
                : (_isInside! ? 'Inside Factory' : 'Off-site Active'),
            _isInside == true ? Colors.green.shade50 : Colors.blue.shade50,
            _isInside == true ? Icons.location_on : Icons.business_center,
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

  Widget _buildWorkerStatusTab() {
    final isDark = widget.isDarkMode;

    // Filter workers based on selected location filter
    final filteredWorkers = _workers.where((worker) {
      if (_workerLocationFilter == 'All') return true;
      final isInside =
          _workerLocationStatus[worker['worker_id'].toString()] ?? false;
      return _workerLocationFilter == 'Inside' ? isInside : !isInside;
    }).toList();

    return Column(
      children: [
        // Filter UI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Row(
            children: [
              Text(
                'Filter:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Inside', 'Outside'].map((filter) {
                      final isSelected = _workerLocationFilter == filter;
                      final count = filter == 'All'
                          ? _workers.length
                          : _workers.where((w) {
                              final inside =
                                  _workerLocationStatus[w['worker_id']
                                      .toString()] ??
                                  false;
                              return filter == 'Inside' ? inside : !inside;
                            }).length;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text('$filter ($count)'),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                            fontSize: 12,
                          ),
                          selectedColor: Colors.blue,
                          checkmarkColor: Colors.white,
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _workerLocationFilter = filter);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _fetchAssignmentData();
              await _updateStatus();
            },
            child: filteredWorkers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: isDark ? Colors.grey[700] : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No workers found for this filter',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredWorkers.length,
                    itemBuilder: (context, index) {
                      final worker = filteredWorkers[index];
                      return FutureBuilder<Map<String, dynamic>?>(
                        future: _getWorkerStatus(
                          worker['worker_id'].toString(),
                        ),
                        builder: (context, snapshot) {
                          final isLoading =
                              snapshot.connectionState ==
                              ConnectionState.waiting;
                          final status = snapshot.data;
                          // Use pre-fetched status if snapshot hasn't resolved yet
                          final isInside = status != null
                              ? (status['is_inside'] ?? false)
                              : (_workerLocationStatus[worker['worker_id']
                                        .toString()] ??
                                    false);

                          final currentTask = status?['current_task'];
                          final pendingTask = status?['pending_task'];
                          final awaitingVerification =
                              status?['awaiting_verification'];

                          return Card(
                            color: isDark ? Colors.grey[850] : Colors.white,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isInside
                                    ? (isDark
                                          ? Colors.green[700]!
                                          : Colors.green.shade200)
                                    : (isDark
                                          ? Colors.red[700]!
                                          : Colors.red.shade200),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              onTap: () =>
                                  _showWorkerDetailsDialog(worker, status),
                              leading: CircleAvatar(
                                backgroundColor: isInside
                                    ? (isDark
                                          ? Colors.green[900]
                                          : Colors.green.shade100)
                                    : (isDark
                                          ? Colors.red[900]
                                          : Colors.red.shade100),
                                child: Icon(
                                  isInside
                                      ? Icons.location_on
                                      : Icons.location_off,
                                  color: isInside
                                      ? (isDark
                                            ? Colors.green[300]
                                            : Colors.green)
                                      : (isDark ? Colors.red[300] : Colors.red),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      worker['name']?.toString() ??
                                          'Unknown Worker',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isInside
                                        ? 'Inside Factory'
                                        : 'Outside Factory',
                                    style: TextStyle(
                                      color: isInside
                                          ? (isDark
                                                ? Colors.green[300]
                                                : Colors.green)
                                          : (isDark
                                                ? Colors.red[300]
                                                : Colors.red),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (isLoading)
                                    SizedBox(
                                      height: 14,
                                      width: 100,
                                      child: LinearProgressIndicator(
                                        backgroundColor: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[200],
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              isDark
                                                  ? Colors.blue[300]!
                                                  : Colors.blue[400]!,
                                            ),
                                      ),
                                    )
                                  else if (awaitingVerification != null)
                                    Text(
                                      'Awaiting Verification: $awaitingVerification',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.purple[300]
                                            : Colors.purple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  else if (currentTask != null)
                                    Text(
                                      'Working on: $currentTask',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.blue[300]
                                            : Colors.blue,
                                      ),
                                    )
                                  else if (pendingTask != null)
                                    Text(
                                      'Assigned: $pendingTask',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.orange[300]
                                            : Colors.orange,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  else
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'IDLE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'No active/assigned task',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.assignment_add,
                                  color: isDark
                                      ? Colors.blue[300]
                                      : Colors.blue,
                                ),
                                onPressed: () {
                                  _showAssignWorkDialog(
                                    preSelectedWorkerId: worker['worker_id']
                                        .toString(),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _getWorkerStatus(String workerId) async {
    try {
      final boundaryEvent = await _supabase
          .from('worker_boundary_events')
          .select()
          .eq('worker_id', workerId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final activeLog = await _supabase
          .from('production_logs')
          .select()
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .filter('end_time', 'is', null)
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();

      final pendingAssignment = await _supabase
          .from('work_assignments')
          .select()
          .eq('worker_id', workerId)
          .eq('status', 'pending')
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final pendingVerification = await _supabase
          .from('production_logs')
          .select()
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .or('is_verified.is.false,is_verified.is.null')
          .not('end_time', 'is', null)
          .gt('quantity', 0)
          .order('end_time', ascending: false)
          .limit(1)
          .maybeSingle();

      String? awaitingVerificationStatus;

      if (pendingVerification != null) {
        awaitingVerificationStatus =
            "${pendingVerification['operation']} (${pendingVerification['item_id']})";
      }

      String? currentTaskWithDuration;
      final isInside = boundaryEvent == null || boundaryEvent['type'] != 'exit';

      if (activeLog != null && isInside) {
        final startTimeStr = activeLog['start_time'] ?? activeLog['created_at'];
        if (startTimeStr != null) {
          final startTime = DateTime.parse(startTimeStr);
          // If a task has been running for more than 12 hours without update,
          // it's likely a stale log from a previous day/shift
          if (DateTime.now().difference(startTime).inHours < 12) {
            final duration = DateTime.now().difference(startTime);
            final hours = duration.inHours;
            final minutes = duration.inMinutes.remainder(60);
            final durationStr = hours > 0
                ? '${hours}h ${minutes}m'
                : '${minutes}m';
            currentTaskWithDuration =
                "${activeLog['operation']} (${activeLog['item_id']}) — $durationStr";
          }
        } else {
          currentTaskWithDuration =
              "${activeLog['operation']} (${activeLog['item_id']})";
        }
      }

      return {
        'is_inside': isInside,
        'current_task': currentTaskWithDuration,
        'pending_task': pendingAssignment != null
            ? "${pendingAssignment['operation']} (${pendingAssignment['item_id']})"
            : null,
        'awaiting_verification': awaitingVerificationStatus,
      };
    } catch (e) {
      debugPrint('Error getting worker status: $e');
      return null;
    }
  }

  Widget _buildNotificationsTab() {
    final isDark = widget.isDarkMode;
    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      child: _notifications.isEmpty
          ? Center(
              child: Text(
                'No notifications yet',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _notifications.length,
              itemBuilder: (ctx, idx) {
                final n = _notifications[idx];
                final type = n['type'] ?? 'info';
                IconData icon = Icons.notifications;
                Color color = Colors.blue;

                if (type == 'out_of_bounds') {
                  icon = Icons.warning_amber_rounded;
                  color = Colors.red;
                } else if (type == 'return') {
                  icon = Icons.check_circle_outline;
                  color = Colors.green;
                }

                return Card(
                  color: isDark ? Colors.grey[850] : Colors.white,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.1),
                      child: Icon(icon, color: color),
                    ),
                    title: Text(
                      n['title'] ?? 'Notification',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n['body'] ?? '',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          TimeUtils.formatTo12Hour(
                            n['created_at'],
                            format: 'dd MMM, hh:mm a',
                          ),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[500] : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.of(context);
    final isDark = themeController?.isDarkMode ?? widget.isDarkMode;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supervisor Dashboard',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.supervisorName,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white70
                      : Colors.black.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          actions: [
            if (_isExporting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  ),
                ),
              )
            else ...[
              DropdownButton<String>(
                value: _reportType,
                underline: const SizedBox(),
                dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                style: TextStyle(
                  color: isDark ? Colors.blue[300] : Colors.blue,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                items: ['Day', 'Week', 'Month'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _reportType = newValue;
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Export Efficiency Report',
                onPressed: _exportToExcel,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _fetchLogs();
                _fetchAssignmentData();
                _updateStatus();
              },
            ),
          ],
          bottom: TabBar(
            indicatorColor: Colors.blue,
            labelColor: isDark ? Colors.blue[300] : Colors.blue,
            unselectedLabelColor: isDark ? Colors.grey[500] : Colors.grey[600],
            tabs: const [
              Tab(
                text: 'Verifications',
                icon: Icon(Icons.check_circle_outline),
              ),
              Tab(text: 'Workers', icon: Icon(Icons.people_outline)),
              Tab(text: 'Geofence', icon: Icon(Icons.security_rounded)),
              Tab(
                text: 'Out of Bounds',
                icon: Icon(Icons.location_on_outlined),
              ),
              Tab(
                text: 'Alerts',
                icon: Icon(Icons.notifications_active_outlined),
              ),
            ],
          ),
        ),
        drawer: AppSidebar(
          userName: widget.supervisorName,
          organizationCode: widget.organizationCode,
          profileImageUrl: _photoUrl,
          isDarkMode: isDark,
          currentThemeMode: themeController?.themeMode ?? AppThemeMode.auto,
          onThemeModeChanged: (mode) =>
              themeController?.onThemeModeChanged(mode),
          onLogout: () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/', (route) => false);
          },
          additionalItems: [
            ListTile(
              leading: Icon(
                Icons.help_outline,
                color: isDark ? Colors.blue[300] : Colors.blue,
              ),
              title: Text(
                'How to Use',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HelpScreen(isDarkMode: isDark),
                  ),
                );
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _fetchLogs,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildStatusHeader()),
                  if (_loading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_logs.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'All production logs verified!',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((ctx, idx) {
                          final log = _logs[idx];
                          final worker =
                              log['workers'] as Map<String, dynamic>?;

                          // Try to get name from join first, then from local _workers list, then fallback to ID
                          String workerName = worker?['name']?.toString() ?? '';
                          if (workerName.isEmpty) {
                            final localWorker = _workers.firstWhere(
                              (w) =>
                                  w['worker_id'].toString() ==
                                  log['worker_id'].toString(),
                              orElse: () => {},
                            );
                            workerName =
                                localWorker['name']?.toString() ??
                                log['worker_id']?.toString() ??
                                'Unknown';
                          }

                          return Card(
                            color: isDark ? Colors.grey[850] : Colors.white,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              title: Text(
                                '$workerName — ${log['operation']}',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Machine: ${log['machine_id']} | Item: ${log['item_id']}\nQty: ${log['quantity']}',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                  if (log['remarks'] != null &&
                                      log['remarks'].toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Remark: ${log['remarks']}',
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _verifyLog(log),
                                child: const Text('Verify'),
                              ),
                            ),
                          );
                        }, childCount: _logs.length),
                      ),
                    ),
                ],
              ),
            ),
            _buildWorkerStatusTab(),
            GeofenceTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDark,
            ),
            OutOfBoundsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDark,
            ),
            _buildNotificationsTab(),
          ],
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'log_btn',
              onPressed: () => _showLogProductionDialog(),
              icon: const Icon(Icons.edit_note),
              label: const Text('Log for Worker'),
              backgroundColor: Colors.teal,
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'assign_btn',
              onPressed: () => _showAssignWorkDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Assign Work'),
            ),
          ],
        ),
      ),
    );
  }
}
