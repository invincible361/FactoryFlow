import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import '../models/item.dart';
import '../utils/time_utils.dart';
import 'dart:io' as io;

// Removed local TimeUtils.formatTo12Hour as we now use TimeUtils.formatTo12Hour

class AdminDashboardScreen extends StatefulWidget {
  final String organizationCode;
  const AdminDashboardScreen({super.key, required this.organizationCode});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _factoryName;
  String? _ownerUsername;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _fetchOrganization();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrganization() async {
    try {
      final resp = await Supabase.instance.client
          .from('organizations')
          .select()
          .eq('organization_code', widget.organizationCode)
          .maybeSingle();
      if (mounted && resp != null) {
        setState(() {
          final orgName = (resp['organization_name'] ?? '').toString();
          final facName = (resp['factory_name'] ?? '').toString();
          _factoryName = orgName.isNotEmpty ? orgName : facName;
          _ownerUsername = (resp['owner_username'] ?? '').toString();
          _logoUrl = (resp['logo_url'] ?? '').toString();
        });
      }
    } catch (e) {
      debugPrint('Fetch org error: $e');
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
                const Text('Admin Dashboard'),
              ],
            ),
            if (_ownerUsername != null && _factoryName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Welcome, ${_ownerUsername!} — ${_factoryName!}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Reports'),
            Tab(text: 'Employees'),
            Tab(text: 'Attendance'),
            Tab(text: 'Machines'),
            Tab(text: 'Items'),
            Tab(text: 'Shifts'),
            Tab(text: 'Security'),
            Tab(text: 'Out of Bounds'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ReportsTab(organizationCode: widget.organizationCode),
          EmployeesTab(organizationCode: widget.organizationCode),
          AttendanceTab(organizationCode: widget.organizationCode),
          MachinesTab(organizationCode: widget.organizationCode),
          ItemsTab(organizationCode: widget.organizationCode),
          ShiftsTab(organizationCode: widget.organizationCode),
          SecurityTab(organizationCode: widget.organizationCode),
          OutOfBoundsTab(organizationCode: widget.organizationCode),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. OUT OF BOUNDS TAB
// ---------------------------------------------------------------------------
class OutOfBoundsTab extends StatefulWidget {
  final String organizationCode;
  const OutOfBoundsTab({super.key, required this.organizationCode});

  @override
  State<OutOfBoundsTab> createState() => _OutOfBoundsTabState();
}

class _OutOfBoundsTabState extends State<OutOfBoundsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('production_outofbounds')
          .select('*')
          .eq('organization_code', widget.organizationCode)
          .order('exit_time', ascending: false);

      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch events error: $e');
      // Fallback if production_outofbounds doesn't exist yet
      try {
        final fallback = await _supabase
            .from('worker_boundary_events')
            .select('*')
            .eq('organization_code', widget.organizationCode)
            .order('exit_time', ascending: false);
        if (mounted) {
          setState(() {
            _events = List<Map<String, dynamic>>.from(fallback);
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_events.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No "Out of Bounds" events recorded.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEvents,
      child: ListView.builder(
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final workerName =
              event['worker_name'] ??
              (event['workers'] is Map
                  ? (event['workers'] as Map)['name']
                  : 'Unknown Worker');
          final exitTime = TimeUtils.parseToLocal(event['exit_time']);
          final entryTimeStr = event['entry_time'] as String?;
          final entryTime = entryTimeStr != null
              ? TimeUtils.parseToLocal(entryTimeStr)
              : null;
          final duration = event['duration_minutes'] ?? 'Still Out';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: entryTime == null
                    ? Colors.red.shade100
                    : Colors.green.shade100,
                child: Icon(
                  entryTime == null
                      ? Icons.exit_to_app
                      : Icons.assignment_turned_in,
                  color: entryTime == null ? Colors.red : Colors.green,
                ),
              ),
              title: Text(
                workerName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exited: ${DateFormat('hh:mm a (MMM dd)').format(exitTime)}',
                  ),
                  if (entryTime != null)
                    Text(
                      'Entered: ${DateFormat('hh:mm a (MMM dd)').format(entryTime)}',
                    ),
                  Text(
                    'Duration: $duration',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: entryTime == null ? Colors.red : Colors.blue,
                    ),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.map, color: Colors.indigo),
                onPressed: () {
                  // Optional: Open maps with exit/entry coordinates
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. ATTENDANCE TAB
// ---------------------------------------------------------------------------
class AttendanceTab extends StatefulWidget {
  final String organizationCode;
  const AttendanceTab({super.key, required this.organizationCode});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _attendance = [];
  bool _isLoading = true;
  bool _isExporting = false;

  // Filters
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  DateTimeRange? _selectedDateRange;

  Future<List<Map<String, dynamic>>> _fetchProductionForAttendance(
    String workerId,
    String date,
    String? shiftName,
  ) async {
    try {
      final response = await _supabase
          .from('production_logs')
          .select('*')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: true);

      final rawLogs = List<Map<String, dynamic>>.from(response);

      // Filter by date and shift in memory for accuracy
      final filtered = rawLogs.where((log) {
        final createdAt = TimeUtils.parseToLocal(log['created_at']);
        final logDate = DateFormat('yyyy-MM-dd').format(createdAt);
        final logShift = log['shift_name']?.toString();

        bool dateMatch = logDate == date;
        bool shiftMatch = shiftName == null || logShift == shiftName;

        return dateMatch && shiftMatch;
      }).toList();

      if (filtered.isEmpty) return [];

      // Fetch item and machine names
      final itemIds = filtered
          .map((l) => l['item_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final machineIds = filtered
          .map((l) => l['machine_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, String> itemMap = {};
      Map<String, String> machineMap = {};

      if (itemIds.isNotEmpty) {
        final itemsResp = await _supabase
            .from('items')
            .select('item_id, name')
            .filter('item_id', 'in', itemIds);
        for (var i in itemsResp) {
          itemMap[i['item_id'].toString()] = i['name'];
        }
      }

      if (machineIds.isNotEmpty) {
        final machinesResp = await _supabase
            .from('machines')
            .select('machine_id, name')
            .filter('machine_id', 'in', machineIds);
        for (var m in machinesResp) {
          machineMap[m['machine_id'].toString()] = m['name'];
        }
      }

      for (var log in filtered) {
        log['item_name'] = itemMap[log['item_id'].toString()] ?? 'Unknown';
        log['machine_name'] = machineMap[log['machine_id'].toString()] ?? 'N/A';
      }

      return filtered;
    } catch (e) {
      debugPrint('Error fetching production for attendance: $e');
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _fetchAttendance();
  }

  Future<void> _fetchEmployees() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name');
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp);
      });
    } catch (e) {
      debugPrint('Fetch employees error: $e');
    }
  }

  Future<void> _fetchAttendance() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase
          .from('attendance')
          .select('*, workers:worker_id(name)')
          .eq('organization_code', widget.organizationCode);

      if (_selectedEmployeeId != null) {
        query = query.eq('worker_id', _selectedEmployeeId!);
      }

      if (_selectedDateRange != null) {
        query = query
            .gte(
              'date',
              DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
            )
            .lte(
              'date',
              DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
            );
      }

      final response = await query
          .order('date', ascending: false)
          .order('check_in', ascending: false);

      if (mounted) {
        setState(() {
          _attendance = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch attendance error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange:
          _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _fetchAttendance();
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      // TODO: Implement attendance export
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance export not implemented yet'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _showAttendanceDetails(Map<String, dynamic> record) async {
    final worker = record['workers'] as Map<String, dynamic>?;
    final workerName = worker?['name'] ?? 'Unknown Worker';
    final workerId = record['worker_id'];
    final dateStr = record['date'];
    final shiftName = record['shift_name'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(workerName),
            Text(
              'Attendance Detail - $dateStr',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchProductionForAttendance(workerId, dateStr, shiftName),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final logs = snapshot.data ?? [];

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailSection('Shift Info', [
                      _detailRow('Shift Name', record['shift_name'] ?? 'N/A'),
                      _detailRow('Status', record['status'] ?? 'On Time'),
                      _detailRow(
                        'Check In',
                        TimeUtils.formatTo12Hour(record['check_in']),
                      ),
                      _detailRow(
                        'Check Out',
                        TimeUtils.formatTo12Hour(record['check_out']),
                      ),
                    ]),
                    const Divider(),
                    const Text(
                      'Production Activity',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (logs.isEmpty)
                      const Text(
                        'No production activity recorded for this shift.',
                      )
                    else
                      ...logs.map(
                        (log) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Item: ${log['item_name'] ?? 'Unknown'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('Operation: ${log['operation']}'),
                                Text(
                                  'Machine: ${log['machine_name'] ?? 'N/A'}',
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Qty: ${log['quantity']}'),
                                    Text(
                                      'Diff: ${log['performance_diff'] >= 0 ? "+" : ""}${log['performance_diff']}',
                                      style: TextStyle(
                                        color: log['performance_diff'] >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Time: ${TimeUtils.formatTo12Hour(log['start_time'], format: 'hh:mm a')} - ${TimeUtils.formatTo12Hour(log['end_time'], format: 'hh:mm a')}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (log['remarks'] != null)
                                  Text(
                                    'Remarks: ${log['remarks']}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Daily Attendance History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportToExcel,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Export Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedEmployeeId,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Employee',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Employees'),
                        ),
                        ..._employees.map((e) {
                          return DropdownMenuItem(
                            value: e['worker_id'].toString(),
                            child: Text(e['name'].toString()),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedEmployeeId = val);
                        _fetchAttendance();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _selectDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _selectedDateRange == null
                                    ? 'Select Dates'
                                    : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_selectedDateRange != null || _selectedEmployeeId != null)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      tooltip: 'Clear Filters',
                      onPressed: () {
                        setState(() {
                          _selectedEmployeeId = null;
                          _selectedDateRange = null;
                        });
                        _fetchAttendance();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _attendance.isEmpty
            ? const Center(child: Text('No attendance records found.'))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _attendance.length,
                itemBuilder: (context, index) {
                  final record = _attendance[index];
                  final worker = record['workers'] as Map<String, dynamic>?;
                  final workerName = worker?['name'] ?? 'Unknown Worker';
                  final status = record['status'] ?? 'On Time';

                  Color statusColor = Colors.green;
                  if (status.contains('Early Leave')) {
                    statusColor = Colors.orange;
                  }
                  if (status.contains('Overtime')) statusColor = Colors.blue;
                  if (status == 'Both') statusColor = Colors.purple;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      onTap: () => _showAttendanceDetails(record),
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.1),
                        child: Icon(Icons.person, color: statusColor),
                      ),
                      title: Text(
                        workerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Date: ${record['date']} | Shift: ${record['shift_name'] ?? 'N/A'}',
                          ),
                          Text(
                            'In: ${TimeUtils.formatTo12Hour(record['check_in'], format: 'hh:mm a')} | '
                            'Out: ${TimeUtils.formatTo12Hour(record['check_out'], format: 'hh:mm a')}',
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}

class ReportsTab extends StatefulWidget {
  final String organizationCode;
  const ReportsTab({super.key, required this.organizationCode});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _filter = 'All'; // All, Today, Week, Month
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _weekLogs = [];
  List<Map<String, dynamic>> _monthLogs = [];
  List<Map<String, dynamic>> _extraWeekLogs = [];
  int _extraUnitsToday = 0;
  bool _isEmployeeScope = false;
  String _linePeriod = 'Week';
  List<FlSpot> _lineSpots = [];

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
          padding: EdgeInsets.all(isLandscape ? 10 : 16),
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
                        fontSize: isLandscape ? 10 : 12,
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
                        fontSize: isLandscape ? 14 : 16,
                        fontWeight: FontWeight.bold,
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

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _fetchEmployeesForDropdown();
    _fetchExtraUnitsTodayOrg();
    _refreshLineData();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _buildQuery(isExport: false);
      final rawLogs = List<Map<String, dynamic>>.from(response);
      final enriched = await _enrichLogsWithNames(rawLogs);
      if (mounted) {
        setState(() {
          _logs = enriched;
          _isLoading = false;
        });
        // Update rolling 24h extra units after logs load
        _fetchExtraUnitsTodayOrg();
      }
    } catch (e) {
      // Fallback if relationship fails
      if (e.toString().contains('relationship') ||
          e.toString().contains('foreign') ||
          e.toString().contains('PGRST200')) {
        try {
          final fallbackResponse = await _supabase
              .from('production_logs')
              .select()
              .eq('organization_code', widget.organizationCode)
              .order('created_at', ascending: false)
              .limit(50);
          final enriched = await _enrichLogsWithNames(
            List<Map<String, dynamic>>.from(fallbackResponse),
          );
          if (mounted) {
            setState(() {
              _logs = enriched;
              _isLoading = false;
            });
          }
          // Successfully loaded fallback, so return without showing error
          return;
        } catch (_) {}
      }

      if (mounted) {
        // Suppress error if it's just empty/missing table, user prefers "No work done"
        // Only print debug info if it's NOT the relationship error we just tried to handle
        if (!e.toString().contains('PGRST200')) {
          debugPrint('Fetch logs error: $e');
        }

        String msg = e.toString();
        if (msg.contains('Load failed') || msg.contains('ClientException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Connection failed. Check your internet or ad-blocker.',
              ),
            ),
          );
        }

        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchEmployeesForDropdown() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp);
      });
    } catch (e) {
      debugPrint('Fetch employees for dropdown error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLogsFrom(
    DateTime from, {
    String? employeeId,
  }) async {
    if (employeeId != null) {
      final response = await _supabase
          .from('production_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .eq('worker_id', employeeId)
          .gte('created_at', from.toIso8601String())
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } else {
      final response = await _supabase
          .from('production_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', from.toIso8601String())
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<void> _loadSelectedEmployeeCharts(String employeeId) async {
    final now = DateTime.now();
    final weekFrom = now.subtract(const Duration(days: 6));
    final monthFrom = now.subtract(const Duration(days: 29));
    final extraFrom = now.subtract(const Duration(days: 7 * 8));
    try {
      final w = await _fetchLogsFrom(weekFrom, employeeId: employeeId);
      final m = await _fetchLogsFrom(monthFrom, employeeId: employeeId);
      final e = await _fetchLogsFrom(extraFrom, employeeId: employeeId);
      if (mounted) {
        setState(() {
          _weekLogs = w;
          _monthLogs = m;
          _extraWeekLogs = e;
        });
      }
    } catch (e) {
      debugPrint('Load employee charts error: $e');
    }
  }

  List<BarChartGroupData> _buildPeriodGroups(
    List<Map<String, dynamic>> logs,
    String period,
  ) {
    final now = DateTime.now();
    final List<BarChartGroupData> groups = [];
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
            barRods: [
              BarChartRodData(toY: buckets[i], color: Colors.blueAccent),
            ],
          ),
        );
      }
    } else {
      final days = period == 'Week' ? 7 : 30;
      final buckets = List<double>.filled(days, 0);
      for (final l in logs) {
        final t = DateTime.tryParse(
          (l['created_at'] ?? '').toString(),
        )?.toLocal();
        if (t != null) {
          final idx = now.difference(t).inDays;
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
            barRods: [
              BarChartRodData(toY: buckets[i], color: Colors.blueAccent),
            ],
          ),
        );
      }
    }
    return groups;
  }

  List<BarChartGroupData> _buildExtraWeekGroups(
    List<Map<String, dynamic>> logs,
  ) {
    final now = DateTime.now();
    final extraBuckets = List<double>.filled(8, 0);
    for (final l in logs) {
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
            DateTime(now.year, now.month, now.day).difference(wStart).inDays ~/
            7;
        final pos = 7 - weeksAgo;
        final diff = (l['performance_diff'] ?? 0) as int;
        if (diff > 0 && pos >= 0 && pos < 8) {
          extraBuckets[pos] += diff * 1.0;
        }
      }
    }
    return [
      for (int i = 0; i < extraBuckets.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: extraBuckets[i], color: Colors.green)],
        ),
    ];
  }

  // Build query based on filter
  Future<dynamic> _buildQuery({required bool isExport}) {
    var query = _supabase
        .from('production_logs')
        .select('*, remarks') // Explicitly select remarks to be safe
        .eq('organization_code', widget.organizationCode);

    // Apply Date Filters
    final now = DateTime.now();
    if (_filter == 'Today') {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());
    } else if (_filter == 'Week') {
      // Last 7 days
      final start = now.subtract(const Duration(days: 7));
      query = query.gte('created_at', start.toIso8601String());
    } else if (_filter == 'Month') {
      final start = DateTime(now.year, now.month, 1);
      query = query.gte('created_at', start.toIso8601String());
    }

    if (!isExport) {
      // Limit for display
      return query.order('created_at', ascending: false).limit(50);
    }
    // No limit for export
    return query.order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> _enrichLogsWithNames(
    List<Map<String, dynamic>> rawLogs,
  ) async {
    try {
      final employeesResp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode);
      final itemsResp = await _supabase
          .from('items')
          .select('item_id, name')
          .eq('organization_code', widget.organizationCode);
      final employeeMap = <String, String>{};
      final itemMap = <String, String>{};
      for (final w in List<Map<String, dynamic>>.from(employeesResp)) {
        final id = w['worker_id']?.toString() ?? '';
        final name = w['name']?.toString() ?? '';
        if (id.isNotEmpty) employeeMap[id] = name;
      }
      for (final it in List<Map<String, dynamic>>.from(itemsResp)) {
        final id = it['item_id']?.toString() ?? '';
        final name = it['name']?.toString() ?? '';
        if (id.isNotEmpty) itemMap[id] = name;
      }
      return rawLogs.map((log) {
        final wid = log['worker_id']?.toString() ?? '';
        final iid = log['item_id']?.toString() ?? '';
        return {
          ...log,
          'employeeName': employeeMap[wid] ?? 'Unknown',
          'itemName': itemMap[iid] ?? 'Unknown',
        };
      }).toList();
    } catch (_) {
      return rawLogs;
    }
  }

  // Aggregate logs: Employee -> Item -> Operation -> {qty, diff, employeeName}
  Map<String, Map<String, Map<String, Map<String, dynamic>>>>
  _getAggregatedData() {
    final Map<String, Map<String, Map<String, Map<String, dynamic>>>> data = {};

    for (var log in _logs) {
      final employeeId = log['worker_id'] as String;
      final employeeName = (log['employeeName'] ?? 'Unknown') as String;

      final item = log['item_id'] as String;
      final op = log['operation'] as String;
      final qty = log['quantity'] as int;
      final diff = (log['performance_diff'] ?? 0) as int;

      data.putIfAbsent(employeeId, () => {});
      data[employeeId]!.putIfAbsent(item, () => {});
      data[employeeId]![item]!.putIfAbsent(
        op,
        () => {'qty': 0, 'diff': 0, 'employeeName': employeeName},
      );

      final current = data[employeeId]![item]![op]!;
      data[employeeId]![item]![op] = {
        'qty': current['qty'] + qty,
        'diff': current['diff'] + diff,
        'employeeName': employeeName,
      };
    }
    return data;
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      // 1. Fetch ALL data based on current filter
      final response = await _buildQuery(isExport: true);
      final allLogsRaw = List<Map<String, dynamic>>.from(response);
      final allLogs = await _enrichLogsWithNames(allLogsRaw);

      if (allLogs.isEmpty) {
        throw Exception('No data to export for this period');
      }

      // 2. Create Excel
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Production Report'];

      // Headers
      sheetObject.appendRow([
        TextCellValue('Employee Name'),
        TextCellValue('Employee ID'),
        TextCellValue('Item ID'),
        TextCellValue('Operation'),
        TextCellValue('Total Quantity'),
        TextCellValue('Total Surplus/Deficit'),
        TextCellValue('Status'),
      ]);

      // 3. Process Data
      // Reuse logic to aggregate, but we need to do it on 'allLogs'
      // Temporarily swap _logs to use the helper (a bit hacky but efficient)
      final tempLogs = _logs;
      _logs = allLogs;
      final aggregated = _getAggregatedData();
      _logs = tempLogs; // Restore display logs

      // 4. Write Rows
      aggregated.forEach((employeeId, items) {
        items.forEach((itemId, ops) {
          ops.forEach((opName, data) {
            final qty = data['qty'];
            final diff = data['diff'];
            final eName = data['employeeName'];
            String status = diff >= 0 ? 'Surplus' : 'Deficit';

            sheetObject.appendRow([
              TextCellValue(eName),
              TextCellValue(employeeId),
              TextCellValue(itemId),
              TextCellValue(opName),
              IntCellValue(qty),
              IntCellValue(diff),
              TextCellValue(status),
            ]);
          });
        });
      });

      Sheet detailsSheet = excel['Detailed Logs'];
      detailsSheet.appendRow([
        TextCellValue('Employee Name'),
        TextCellValue('Employee ID'),
        TextCellValue('Item ID'),
        TextCellValue('Operation'),
        TextCellValue('Date'),
        TextCellValue('In Time'),
        TextCellValue('Out Time'),
        TextCellValue('Working Hours'),
        TextCellValue('Machine ID'),
        TextCellValue('Quantity'),
        TextCellValue('Surplus/Deficit'),
        TextCellValue('Status'),
        TextCellValue('Remarks'),
      ]);
      for (final log in allLogs) {
        final eName = (log['employeeName'] ?? 'Unknown').toString();
        final employeeId = (log['worker_id'] ?? '').toString();
        final itemId = (log['item_id'] ?? '').toString();
        final opName = (log['operation'] ?? '').toString();
        final qty = (log['quantity'] ?? 0) as int;
        final diff = (log['performance_diff'] ?? 0) as int;
        String status = diff >= 0 ? 'Surplus' : 'Deficit';
        final remarks = (log['remarks'] ?? '').toString();
        final createdAtStr = (log['created_at'] ?? '').toString();

        final startTimeStr = (log['start_time'] ?? '').toString();
        final endTimeStr = (log['end_time'] ?? '').toString();

        DateTime dt;
        try {
          dt = TimeUtils.parseToLocal(createdAtStr);
        } catch (_) {
          dt = DateTime.now();
        }

        String inTime = '-';
        String outTime = '-';
        String totalHours = '-';

        if (startTimeStr.isNotEmpty) {
          try {
            final st = TimeUtils.parseToLocal(startTimeStr);
            inTime = DateFormat('hh:mm a').format(st);
            if (endTimeStr.isNotEmpty) {
              final et = TimeUtils.parseToLocal(endTimeStr);
              outTime = DateFormat('hh:mm a').format(et);
              final duration = et.difference(st);
              final hours = duration.inHours;
              final minutes = duration.inMinutes.remainder(60);
              totalHours = '${hours}h ${minutes}m';
            }
          } catch (_) {}
        }

        final dateStr = DateFormat('yyyy-MM-dd').format(dt);
        final machineId = (log['machine_id'] ?? '').toString();
        detailsSheet.appendRow([
          TextCellValue(eName),
          TextCellValue(employeeId),
          TextCellValue(itemId),
          TextCellValue(opName),
          TextCellValue(dateStr),
          TextCellValue(inTime),
          TextCellValue(outTime),
          TextCellValue(totalHours),
          TextCellValue(machineId),
          IntCellValue(qty),
          IntCellValue(diff),
          TextCellValue(status),
          TextCellValue(remarks),
        ]);
      }

      // 5. Save & Share
      final bytes = excel.save();
      if (bytes == null) {
        throw Exception('Failed to generate Excel bytes');
      }
      if (kIsWeb) {
        final uint8 = Uint8List.fromList(bytes);
        final params = share_plus.ShareParams(
          files: [
            share_plus.XFile.fromData(
              uint8,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          fileNameOverrides: [
            'production_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          ],
          text: 'Production Report ($_filter)',
        );
        await share_plus.SharePlus.instance.share(params);
      } else {
        final directory = await getTemporaryDirectory();
        final path =
            '${directory.path}/production_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        final file = io.File(path);
        await file.writeAsBytes(bytes);
        final params = share_plus.ShareParams(
          files: [share_plus.XFile(path)],
          text: 'Production Report ($_filter)',
        );
        await share_plus.SharePlus.instance.share(params);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export successful!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _fetchExtraUnitsTodayOrg() async {
    try {
      final now = DateTime.now();
      final dayFrom = now.subtract(const Duration(hours: 24));
      final response = await _supabase
          .from('production_logs')
          .select('performance_diff, created_at, remarks')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', dayFrom.toIso8601String());
      int sum = 0;
      for (final l in List<Map<String, dynamic>>.from(response)) {
        final diff = (l['performance_diff'] ?? 0) as int;
        if (diff > 0) sum += diff;
      }
      if (mounted) setState(() => _extraUnitsToday = sum);
    } catch (e) {
      debugPrint('Fetch org extra units today error: $e');
    }
  }

  Future<void> _refreshLineData() async {
    try {
      final now = DateTime.now();
      DateTime from;
      int bucketsCount;
      if (_linePeriod == 'Day') {
        from = DateTime(now.year, now.month, now.day);
        bucketsCount = 24;
      } else if (_linePeriod == 'Week') {
        from = now.subtract(const Duration(days: 6));
        bucketsCount = 7;
      } else {
        from = now.subtract(const Duration(days: 29));
        bucketsCount = 30;
      }
      final logs = await _fetchLogsFrom(
        from,
        employeeId: _isEmployeeScope ? _selectedEmployeeId : null,
      );
      final buckets = List<double>.filled(bucketsCount, 0);
      for (final l in logs) {
        final t = DateTime.tryParse(
          (l['created_at'] ?? '').toString(),
        )?.toLocal();
        if (t == null) continue;
        int pos;
        if (_linePeriod == 'Day') {
          pos = t.hour;
        } else {
          final idx = now.difference(t).inDays;
          pos = bucketsCount - 1 - idx;
        }
        if (pos >= 0 && pos < bucketsCount) {
          buckets[pos] += (l['quantity'] ?? 0) * 1.0;
        }
      }
      final spots = <FlSpot>[];
      for (int i = 0; i < buckets.length; i++) {
        spots.add(FlSpot(i.toDouble(), buckets[i]));
      }
      if (mounted) setState(() => _lineSpots = spots);
    } catch (e) {
      if (mounted) setState(() => _lineSpots = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _fetchLogs(),
          _fetchEmployeesForDropdown(),
          _fetchExtraUnitsTodayOrg(),
          _refreshLineData(),
        ]);
      },
      child: ListView(
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text(
                  'Filter: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _filter,
                  items: ['All', 'Today', 'Week', 'Month'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() {
                        _filter = newValue;
                        _fetchLogs();
                      });
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.green),
                  onPressed: _isExporting ? null : _exportToExcel,
                  tooltip: 'Export to Excel',
                ),
                if (_isExporting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          // Metrics Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: GridView.count(
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
                  ? 2.8
                  : 2.2,
              children: [
                _metricTile(
                  'Extra Units (24h)',
                  '$_extraUnitsToday',
                  Colors.green.shade200,
                  Icons.trending_up,
                ),
                _metricTile(
                  'Employees',
                  '${_employees.length}',
                  Colors.blue.shade100,
                  Icons.people,
                ),
              ],
            ),
          ),
          // Line chart controls
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: !_isEmployeeScope,
                          onChanged: (v) {
                            setState(() {
                              _isEmployeeScope = false;
                            });
                            _refreshLineData();
                          },
                        ),
                        const Text('All employees'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _isEmployeeScope,
                          onChanged: (v) {
                            setState(() {
                              _isEmployeeScope = true;
                            });
                            _refreshLineData();
                          },
                        ),
                        const Text('Specific employee'),
                      ],
                    ),
                    if (_isEmployeeScope)
                      DropdownButton<String>(
                        value: _selectedEmployeeId,
                        hint: const Text('Select employee'),
                        items: _employees.map((w) {
                          final id = (w['worker_id'] ?? '').toString();
                          final name = (w['name'] ?? '').toString();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text('$name ($id)'),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() => _selectedEmployeeId = v);
                          _refreshLineData();
                        },
                      ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _linePeriod == 'Day',
                          onChanged: (v) {
                            setState(() => _linePeriod = 'Day');
                            _refreshLineData();
                          },
                        ),
                        const Text('Daily'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _linePeriod == 'Week',
                          onChanged: (v) {
                            setState(() => _linePeriod = 'Week');
                            _refreshLineData();
                          },
                        ),
                        const Text('Weekly'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _linePeriod == 'Month',
                          onChanged: (v) {
                            setState(() => _linePeriod = 'Month');
                            _refreshLineData();
                          },
                        ),
                        const Text('Monthly'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height:
                      MediaQuery.of(context).orientation ==
                          Orientation.landscape
                      ? 180
                      : 240,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots
                                .map(
                                  (s) => LineTooltipItem(
                                    s.y.toStringAsFixed(0),
                                    const TextStyle(color: Colors.white),
                                  ),
                                )
                                .toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            getTitlesWidget: (value, meta) {
                              final v = value.toInt();
                              if (_linePeriod == 'Day') {
                                if (v % 3 != 0) {
                                  return const SizedBox.shrink();
                                }
                                final hour = v % 12 == 0 ? 12 : v % 12;
                                final amPm = v < 12 ? 'AM' : 'PM';
                                return Text(
                                  '$hour $amPm',
                                  style: const TextStyle(fontSize: 10),
                                );
                              } else if (_linePeriod == 'Week') {
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
                            reservedSize: 40,
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _lineSpots,
                          isCurved: true,
                          color: Colors.blueAccent,
                          barWidth: 3,
                          dotData: FlDotData(show: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Employee selection and graphs
          if (_employees.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  const Text(
                    'Employee: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    value: _selectedEmployeeId,
                    hint: const Text('Select employee'),
                    items: _employees.map((w) {
                      final id = (w['worker_id'] ?? '').toString();
                      final name = (w['name'] ?? '').toString();
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text('$name ($id)'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedEmployeeId = v;
                      });
                      if (v != null) {
                        _loadSelectedEmployeeCharts(v);
                      }
                    },
                  ),
                ],
              ),
            ),
          if (_selectedEmployeeId != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Efficiency (Week)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height:
                        MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 180
                        : 240,
                    child: BarChart(
                      BarChartData(
                        barGroups: _buildPeriodGroups(_weekLogs, 'Week'),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
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
                                  '${v + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
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
                  const SizedBox(height: 12),
                  const Text(
                    'Efficiency (Month)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height:
                        MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 180
                        : 240,
                    child: BarChart(
                      BarChartData(
                        barGroups: _buildPeriodGroups(_monthLogs, 'Month'),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 5 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${v + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
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
                  const SizedBox(height: 12),
                  const Text(
                    'Weekly Extra Work',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height:
                        MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 150
                        : 200,
                    child: BarChart(
                      BarChartData(
                        barGroups: _buildExtraWeekGroups(_extraWeekLogs),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  'W${v + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
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
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _logs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: Text('No work done.')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final employeeName = log['employeeName'] ?? 'Unknown';
                      final itemName = log['itemName'] ?? 'Unknown';
                      final remarks = log['remarks'] as String?;

                      String workingHours = '';
                      String inOutTime = '';

                      if (log['start_time'] != null) {
                        final inT = TimeUtils.formatTo12Hour(
                          log['start_time'],
                          format: 'hh:mm a',
                        );
                        if (log['end_time'] != null) {
                          final outT = TimeUtils.formatTo12Hour(
                            log['end_time'],
                            format: 'hh:mm a',
                          );
                          inOutTime = 'In: $inT | Out: $outT';

                          try {
                            final st = TimeUtils.parseToLocal(
                              log['start_time'],
                            );
                            final et = TimeUtils.parseToLocal(log['end_time']);
                            final duration = et.difference(st);
                            final hours = duration.inHours;
                            final minutes = duration.inMinutes.remainder(60);
                            workingHours = 'Total: ${hours}h ${minutes}m';
                          } catch (_) {}
                        } else {
                          inOutTime = 'In: $inT | Out: -';
                        }
                      }

                      return ListTile(
                        title: Text('$employeeName - $itemName'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${log['operation']} | Qty: ${log['quantity']} | Diff: ${log['performance_diff']}',
                            ),
                            if (inOutTime.isNotEmpty)
                              Text(
                                inOutTime,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            if (workingHours.isNotEmpty)
                              Text(
                                workingHours,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 12,
                                ),
                              ),
                            if (remarks != null && remarks.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Remark: $remarks',
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Text(
                          TimeUtils.formatTo12Hour(
                            log['created_at'],
                            format: 'MM/dd hh:mm a',
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

// ---------------------------------------------------------------------------
// 2. WORKERS TAB
// ---------------------------------------------------------------------------
class EmployeesTab extends StatefulWidget {
  final String organizationCode;
  const EmployeesTab({super.key, required this.organizationCode});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _employeesList = [];
  bool _isLoading = true;

  final _employeeIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _panController = TextEditingController();
  final _aadharController = TextEditingController();
  final _ageController = TextEditingController();
  final _mobileController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('workers')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _employeesList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Error: $e';
        if (msg.contains('Load failed') || msg.contains('ClientException')) {
          msg = 'Connection failed. Check your internet or ad-blocker.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteEmployee(String employeeId) async {
    try {
      // First delete associated production logs
      await _supabase
          .from('production_logs')
          .delete()
          .eq('worker_id', employeeId);

      // Then delete the worker (table is still 'workers' in DB)
      await _supabase.from('workers').delete().eq('worker_id', employeeId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee and associated logs deleted')),
        );
        _fetchEmployees();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addEmployee() async {
    // Basic validation
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    final aadharRegex = RegExp(r'^[0-9]{12}$');

    final panValue = _panController.text.trim();
    if (panValue.isNotEmpty && !panRegex.hasMatch(panValue)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid PAN Card Format')),
        );
      }
      return;
    }

    if (!_aadharController.text.contains(aadharRegex)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid Aadhar Card Format (must be 12 digits)'),
          ),
        );
      }
      return;
    }

    try {
      await _supabase.from('workers').insert({
        'worker_id': _employeeIdController.text,
        'name': _nameController.text,
        'pan_card': panValue.isEmpty ? null : panValue,
        'aadhar_card': _aadharController.text,
        'age': int.tryParse(_ageController.text),
        'mobile_number': _mobileController.text,
        'username': _usernameController.text,
        'password': _passwordController.text, // Note: Should hash in real app
        'organization_code': widget.organizationCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Employee added!')));
        _clearControllers();
        _fetchEmployees();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editEmployee(Map<String, dynamic> employee) async {
    final nameEditController = TextEditingController(text: employee['name']);
    final panEditController = TextEditingController(text: employee['pan_card']);
    final aadharEditController = TextEditingController(
      text: employee['aadhar_card'],
    );
    final ageEditController = TextEditingController(
      text: employee['age']?.toString(),
    );
    final mobileEditController = TextEditingController(
      text: employee['mobile_number'],
    );
    final usernameEditController = TextEditingController(
      text: employee['username'],
    );
    final passwordEditController = TextEditingController(
      text: employee['password'],
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Employee: ${employee['worker_id']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameEditController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: panEditController,
                decoration: const InputDecoration(labelText: 'PAN Card'),
              ),
              TextField(
                controller: aadharEditController,
                decoration: const InputDecoration(labelText: 'Aadhar Card'),
              ),
              TextField(
                controller: ageEditController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age'),
              ),
              TextField(
                controller: mobileEditController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile Number'),
              ),
              TextField(
                controller: usernameEditController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: passwordEditController,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(ctx);
              try {
                await _supabase
                    .from('workers')
                    .update({
                      'name': nameEditController.text,
                      'pan_card': panEditController.text.isEmpty
                          ? null
                          : panEditController.text,
                      'aadhar_card': aadharEditController.text,
                      'age': int.tryParse(ageEditController.text),
                      'mobile_number': mobileEditController.text,
                      'username': usernameEditController.text,
                      'password': passwordEditController.text,
                    })
                    .eq('worker_id', employee['worker_id'])
                    .eq('organization_code', widget.organizationCode);

                if (mounted) {
                  nav.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Employee updated!')),
                  );
                  _fetchEmployees();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _clearControllers() {
    _employeeIdController.clear();
    _nameController.clear();
    _panController.clear();
    _aadharController.clear();
    _ageController.clear();
    _mobileController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchEmployees,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ExpansionTile(
              title: const Text('Add New Employee'),
              children: [
                TextField(
                  controller: _employeeIdController,
                  decoration: const InputDecoration(labelText: 'Employee ID'),
                ),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: _panController,
                  decoration: const InputDecoration(
                    labelText: 'PAN Card (Optional)',
                    hintText: 'ABCDE1234F',
                  ),
                ),
                TextField(
                  controller: _aadharController,
                  decoration: const InputDecoration(labelText: 'Aadhar Card'),
                ),
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Age'),
                ),
                TextField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile Number'),
                ),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _addEmployee,
                  child: const Text('Add Employee'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _employeesList.length,
                itemBuilder: (context, index) {
                  final employee = _employeesList[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        '${employee['name']} (${employee['worker_id']})',
                      ),
                      subtitle: Text('Mobile: ${employee['mobile_number']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editEmployee(employee),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _deleteEmployee(employee['worker_id']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. MACHINES TAB
// ---------------------------------------------------------------------------
class MachinesTab extends StatefulWidget {
  final String organizationCode;
  const MachinesTab({super.key, required this.organizationCode});

  @override
  State<MachinesTab> createState() => _MachinesTabState();
}

class _MachinesTabState extends State<MachinesTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;

  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String _type = 'CNC';

  Map<String, dynamic>? _editingMachine;

  @override
  void initState() {
    super.initState();
    _fetchMachines();
  }

  void _editMachine(Map<String, dynamic> machine) {
    setState(() {
      _editingMachine = machine;
      _idController.text = machine['machine_id'];
      _nameController.text = machine['name'];
      _type = machine['type'];
    });
  }

  Future<void> _updateMachine() async {
    if (_editingMachine == null) return;
    try {
      await _supabase
          .from('machines')
          .update({'name': _nameController.text, 'type': _type})
          .eq('machine_id', _editingMachine!['machine_id'])
          .eq('organization_code', widget.organizationCode);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Machine updated!')));
        _clearForm();
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _clearForm() {
    setState(() {
      _editingMachine = null;
      _idController.clear();
      _nameController.clear();
      _type = 'CNC';
    });
  }

  Future<void> _fetchMachines() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('machines')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _machines = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteMachine(String id) async {
    try {
      await _supabase
          .from('machines')
          .delete()
          .eq('machine_id', id)
          .eq('organization_code', widget.organizationCode);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Machine deleted')));
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addMachine() async {
    try {
      await _supabase.from('machines').insert({
        'machine_id': _idController.text,
        'name': _nameController.text,
        'type': _type,
        'organization_code': widget.organizationCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Machine added!')));
        _idController.clear();
        _nameController.clear();
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          ExpansionTile(
            title: Text(
              _editingMachine == null ? 'Add New Machine' : 'Edit Machine',
            ),
            initiallyExpanded: _editingMachine != null,
            children: [
              TextField(
                controller: _idController,
                enabled: _editingMachine == null,
                decoration: const InputDecoration(labelText: 'Machine ID'),
              ),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Machine Name'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                items: ['CNC', 'VMC']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setState(() => _type = val!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _editingMachine == null
                        ? _addMachine
                        : _updateMachine,
                    child: Text(
                      _editingMachine == null
                          ? 'Add Machine'
                          : 'Update Machine',
                    ),
                  ),
                  if (_editingMachine != null) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _clearForm,
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
          const SizedBox(height: 20),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _machines.length,
                  itemBuilder: (context, index) {
                    final machine = _machines[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.precision_manufacturing),
                        title: Text(
                          '${machine['name']} (${machine['machine_id']})',
                        ),
                        subtitle: Text('Type: ${machine['type']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editMachine(machine),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  _deleteMachine(machine['machine_id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. ITEMS TAB
// ---------------------------------------------------------------------------
class ItemsTab extends StatefulWidget {
  final String organizationCode;
  const ItemsTab({super.key, required this.organizationCode});

  @override
  State<ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<ItemsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _isLoadingItems = true;

  // New Item Controllers
  final _itemIdController = TextEditingController();
  final _itemNameController = TextEditingController();
  List<OperationDetail> _operations = [];

  // Operation Controllers
  final _opNameController = TextEditingController();
  final _opTargetController = TextEditingController();
  PlatformFile? _opFile;

  Map<String, dynamic>? _editingItem;

  Future<String?> _uploadToBucketWithAutoCreate(
    String bucket,
    String fileName,
    Uint8List bytes,
    String contentType,
  ) async {
    try {
      try {
        await _supabase.storage
            .from(bucket)
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      } on StorageException catch (se) {
        if (se.message.contains('Bucket not found') || se.statusCode == '404') {
          // Attempt to create the bucket if it's missing
          await _supabase.storage.createBucket(
            bucket,
            const BucketOptions(public: true),
          );

          // Retry the upload
          await _supabase.storage
              .from(bucket)
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: true,
                ),
              );
        } else {
          rethrow;
        }
      }
      return _supabase.storage.from(bucket).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error for bucket $bucket: $e');
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final response = await _supabase
          .from('items')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(response);
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoadingItems = false);
      }
    }
  }

  void _editItem(Map<String, dynamic> item) {
    setState(() {
      _editingItem = item;
      _itemIdController.text = item['item_id'];
      _itemNameController.text = item['name'];
      _operations = (item['operation_details'] as List? ?? [])
          .map(
            (op) => OperationDetail(
              name: op['name'],
              target: op['target'],
              existingUrl: op['imageUrl'],
              existingPdfUrl: op['pdfUrl'],
            ),
          )
          .toList();
    });
  }

  Future<void> _updateItem() async {
    if (_editingItem == null) return;
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Updating...')));

      List<Map<String, dynamic>> opJson = [];
      for (var op in _operations) {
        String? imageUrl = op.existingUrl;
        String? pdfUrl = op.existingPdfUrl;

        if (op.newFile != null) {
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}_${op.newFile!.name}';
          final bytes =
              op.newFile!.bytes ??
              await io.File(op.newFile!.path!).readAsBytes();

          final isPdf = op.newFile!.name.toLowerCase().endsWith('.pdf');
          final bucket = isPdf ? 'operation_documents' : 'operation_images';
          final contentType = isPdf ? 'application/pdf' : 'image/jpeg';

          final publicUrl = await _uploadToBucketWithAutoCreate(
            bucket,
            fileName,
            bytes,
            contentType,
          );

          if (isPdf) {
            pdfUrl = publicUrl;
          } else {
            imageUrl = publicUrl;
          }
        }

        opJson.add({
          'name': op.name,
          'target': op.target,
          'imageUrl': imageUrl,
          'pdfUrl': pdfUrl,
        });
      }

      final opNames = _operations.map((o) => o.name).toList();

      await _supabase
          .from('items')
          .update({
            'name': _itemNameController.text,
            'operation_details': opJson,
            'operations': opNames,
          })
          .eq('item_id', _editingItem!['item_id'])
          .eq('organization_code', widget.organizationCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item Updated Successfully!')),
        );
        _clearItemForm();
        _fetchItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _clearItemForm() {
    setState(() {
      _editingItem = null;
      _itemIdController.clear();
      _itemNameController.clear();
      _operations = [];
      _opNameController.clear();
      _opTargetController.clear();
      _opFile = null;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null) {
      setState(() {
        _opFile = result.files.first;
      });
    }
  }

  void _addOperation() {
    if (_opNameController.text.isEmpty) return;

    setState(() {
      _operations.add(
        OperationDetail(
          name: _opNameController.text,
          target: int.tryParse(_opTargetController.text) ?? 0,
          newFile: _opFile,
        ),
      );
      _opNameController.clear();
      _opTargetController.clear();
      _opFile = null;
    });
  }

  Future<void> _addItem() async {
    if (_itemIdController.text.isEmpty || _itemNameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill item details')));
      return;
    }
    if (_operations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one operation')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading...')));

      // 1. Upload files first and get URLs
      List<Map<String, dynamic>> opJson = [];
      for (var op in _operations) {
        String? imageUrl;
        String? pdfUrl;
        if (op.newFile != null) {
          try {
            final isPdf = op.newFile!.name.toLowerCase().endsWith('.pdf');
            final bucket = isPdf ? 'operation_documents' : 'operation_images';
            final contentType = isPdf ? 'application/pdf' : 'image/jpeg';
            final fileName =
                '${DateTime.now().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}_${op.newFile!.name}';

            final bytes =
                op.newFile!.bytes ??
                await io.File(op.newFile!.path!).readAsBytes();

            final publicUrl = await _uploadToBucketWithAutoCreate(
              bucket,
              fileName,
              bytes,
              contentType,
            );

            if (isPdf) {
              pdfUrl = publicUrl;
            } else {
              imageUrl = publicUrl;
            }
          } catch (e) {
            debugPrint('File upload failed: $e');
            rethrow; // Rethrow to show in UI
          }
        }
        opJson.add({
          'name': op.name,
          'target': op.target,
          'imageUrl': imageUrl,
          'pdfUrl': pdfUrl,
        });
      }

      // 2. Insert Item
      final opNames = _operations.map((o) => o.name).toList();

      await _supabase.from('items').insert({
        'item_id': _itemIdController.text,
        'name': _itemNameController.text,
        'operation_details': opJson,
        'operations': opNames,
        'organization_code': widget.organizationCode,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item Added Successfully!')),
        );
        _itemIdController.clear();
        _itemNameController.clear();
        setState(() => _operations = []);
        _fetchItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await _supabase
          .from('items')
          .delete()
          .eq('item_id', id)
          .eq('organization_code', widget.organizationCode);
      if (mounted) {
        _fetchItems();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text(
            _editingItem == null ? 'Add New Item' : 'Edit Item',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _itemIdController,
            enabled: _editingItem == null,
            decoration: const InputDecoration(labelText: 'Item ID (e.g. 5001)'),
          ),
          TextField(
            controller: _itemNameController,
            decoration: const InputDecoration(
              labelText: 'Item Name (e.g. Shirt)',
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'Operations',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _opNameController,
                  decoration: const InputDecoration(
                    labelText: 'Operation Name (e.g. Collar)',
                  ),
                ),
                TextField(
                  controller: _opTargetController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Target Quantity',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Pick Image/PDF'),
                    ),
                    const SizedBox(width: 10),
                    if (_opFile != null)
                      Expanded(
                        child: Text(
                          _opFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _addOperation,
                  child: const Text('Add Operation'),
                ),
              ],
            ),
          ),

          // Operation List Preview
          if (_operations.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._operations.map(
              (op) => ListTile(
                title: Text(op.name),
                subtitle: Text('Target: ${op.target}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (op.imageUrl != null || op.existingUrl != null)
                      const Icon(Icons.image, color: Colors.blue),
                    if (op.pdfUrl != null || op.existingPdfUrl != null)
                      const Icon(Icons.picture_as_pdf, color: Colors.red),
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _operations.remove(op);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _editingItem == null ? _addItem : _updateItem,
                child: Text(
                  _editingItem == null
                      ? 'Save Item to Database'
                      : 'Update Item',
                ),
              ),
              if (_editingItem != null) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _clearItemForm,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Existing Items',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          _isLoadingItems
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? const Center(child: Text('No items found.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    // Count operations if possible
                    final ops = item['operation_details'] as List? ?? [];
                    return Card(
                      child: ListTile(
                        title: Text('${item['name']} (${item['item_id']})'),
                        subtitle: Text('${ops.length} Operations'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editItem(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteItem(item['item_id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. SHIFTS TAB
// ---------------------------------------------------------------------------
class ShiftsTab extends StatefulWidget {
  final String organizationCode;
  const ShiftsTab({super.key, required this.organizationCode});

  @override
  State<ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<ShiftsTab> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  List<Map<String, dynamic>> _shifts = [];
  bool _isLoading = true;
  Map<String, dynamic>? _editingShift;

  @override
  void initState() {
    super.initState();
    _fetchShifts();
  }

  Future<void> _fetchShifts() async {
    setState(() => _isLoading = true);
    try {
      final resp = await _supabase
          .from('shifts')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      setState(() {
        _shifts = List<Map<String, dynamic>>.from(resp);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch shifts error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrUpdateShift() async {
    if (_nameController.text.isEmpty ||
        _startController.text.isEmpty ||
        _endController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    try {
      final data = {
        'name': _nameController.text,
        'start_time': _startController.text,
        'end_time': _endController.text,
        'organization_code': widget.organizationCode,
      };

      if (_editingShift == null) {
        await _supabase.from('shifts').insert(data);
      } else {
        await _supabase
            .from('shifts')
            .update(data)
            .eq('id', _editingShift!['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _editingShift == null ? 'Shift added!' : 'Shift updated!',
            ),
          ),
        );
        _clearForm();
        _fetchShifts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _editShift(Map<String, dynamic> shift) {
    setState(() {
      _editingShift = shift;
      _nameController.text = shift['name'] ?? '';
      _startController.text = shift['start_time'] ?? '';
      _endController.text = shift['end_time'] ?? '';
    });
  }

  Future<void> _deleteShift(dynamic id) async {
    try {
      await _supabase.from('shifts').delete().eq('id', id);
      _fetchShifts();
    } catch (e) {
      debugPrint('Delete shift error: $e');
    }
  }

  void _clearForm() {
    setState(() {
      _editingShift = null;
      _nameController.clear();
      _startController.clear();
      _endController.clear();
    });
  }

  Future<void> _selectTime(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final now = DateTime.now();
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      setState(() {
        controller.text = DateFormat('hh:mm a').format(dt);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text(
            _editingShift == null ? 'Add New Shift' : 'Edit Shift',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Shift Name (e.g. Morning)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  readOnly: true,
                  onTap: () => _selectTime(context, _startController),
                  decoration: const InputDecoration(
                    labelText: 'Start Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _endController,
                  readOnly: true,
                  onTap: () => _selectTime(context, _endController),
                  decoration: const InputDecoration(
                    labelText: 'End Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _addOrUpdateShift,
                child: Text(
                  _editingShift == null ? 'Add Shift' : 'Update Shift',
                ),
              ),
              if (_editingShift != null) ...[
                const SizedBox(width: 10),
                TextButton(onPressed: _clearForm, child: const Text('Cancel')),
              ],
            ],
          ),
          const Divider(height: 32, thickness: 2),
          const Text(
            'Existing Shifts',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _shifts.isEmpty
              ? const Center(child: Text('No shifts found.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _shifts.length,
                  itemBuilder: (context, index) {
                    final shift = _shifts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: const Icon(
                            Icons.schedule,
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          shift['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Time: ${shift['start_time']} - ${shift['end_time']}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit Shift',
                              onPressed: () => _editShift(shift),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Shift',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Shift'),
                                    content: const Text(
                                      'Are you sure you want to delete this shift?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          _deleteShift(shift['id']);
                                          Navigator.pop(context);
                                        },
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. SECURITY TAB
// ---------------------------------------------------------------------------
class SecurityTab extends StatefulWidget {
  final String organizationCode;
  const SecurityTab({super.key, required this.organizationCode});

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  bool _missingTable = false;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('owner_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('login_time', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          _missingTable = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _missingTable = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_missingTable) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.security, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No login security available.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Make sure the "owner_logs" table exists in Supabase.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_logs.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No login history found.',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                '(Make sure "owner_logs" table exists in Supabase)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        final timeStr = log['login_time'] as String?;
        final time =
            DateTime.tryParse(timeStr ?? '')?.toLocal() ?? DateTime.now();
        final device = log['device_name'] ?? 'Unknown';
        final os = log['os_version'] ?? 'Unknown';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.security, color: Colors.blue),
            title: Text('Logged in at ${TimeUtils.formatTo12Hour(time)}'),
            subtitle: Text('Device: $device\nOS: $os'),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
