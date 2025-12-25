import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/item.dart';
import 'dart:io'
    show File; // Show File only for non-web logic if strictly needed

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
    _tabController = TabController(length: 6, vsync: this);
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
            Tab(text: 'Workers'),
            Tab(text: 'Machines'),
            Tab(text: 'Items'),
            Tab(text: 'Shifts'),
            Tab(text: 'Security'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ReportsTab(organizationCode: widget.organizationCode),
          WorkersTab(organizationCode: widget.organizationCode),
          MachinesTab(organizationCode: widget.organizationCode),
          ItemsTab(organizationCode: widget.organizationCode),
          ShiftsTab(organizationCode: widget.organizationCode),
          SecurityTab(organizationCode: widget.organizationCode),
        ],
      ),
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
  List<Map<String, dynamic>> _workers = [];
  String? _selectedWorkerId;
  List<Map<String, dynamic>> _weekLogs = [];
  List<Map<String, dynamic>> _monthLogs = [];
  List<Map<String, dynamic>> _extraWeekLogs = [];
  int _extraUnitsToday = 0;
  bool _isWorkerScope = false;
  String _linePeriod = 'Week';
  List<FlSpot> _lineSpots = [];

  Widget _metricTile(String title, String value, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _fetchWorkersForDropdown();
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

  Future<void> _fetchWorkersForDropdown() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode);
      setState(() {
        _workers = List<Map<String, dynamic>>.from(resp);
      });
    } catch (e) {
      debugPrint('Fetch workers for dropdown error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLogsFrom(
    DateTime from, {
    String? workerId,
  }) async {
    if (workerId != null) {
      final response = await _supabase
          .from('production_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .eq('worker_id', workerId)
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

  Future<void> _loadSelectedWorkerCharts(String workerId) async {
    final now = DateTime.now();
    final weekFrom = now.subtract(const Duration(days: 6));
    final monthFrom = now.subtract(const Duration(days: 29));
    final extraFrom = now.subtract(const Duration(days: 7 * 8));
    try {
      final w = await _fetchLogsFrom(weekFrom, workerId: workerId);
      final m = await _fetchLogsFrom(monthFrom, workerId: workerId);
      final e = await _fetchLogsFrom(extraFrom, workerId: workerId);
      if (mounted) {
        setState(() {
          _weekLogs = w;
          _monthLogs = m;
          _extraWeekLogs = e;
        });
      }
    } catch (e) {
      debugPrint('Load worker charts error: $e');
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
      final workersResp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode);
      final itemsResp = await _supabase
          .from('items')
          .select('item_id, name')
          .eq('organization_code', widget.organizationCode);
      final workerMap = <String, String>{};
      final itemMap = <String, String>{};
      for (final w in List<Map<String, dynamic>>.from(workersResp)) {
        final id = w['worker_id']?.toString() ?? '';
        final name = w['name']?.toString() ?? '';
        if (id.isNotEmpty) workerMap[id] = name;
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
          'workerName': workerMap[wid] ?? 'Unknown',
          'itemName': itemMap[iid] ?? 'Unknown',
        };
      }).toList();
    } catch (_) {
      return rawLogs;
    }
  }

  // Aggregate logs: Worker -> Item -> Operation -> {qty, diff, workerName}
  Map<String, Map<String, Map<String, Map<String, dynamic>>>>
  _getAggregatedData() {
    final Map<String, Map<String, Map<String, Map<String, dynamic>>>> data = {};

    for (var log in _logs) {
      final worker = log['worker_id'] as String;
      final workerName = (log['workerName'] ?? 'Unknown') as String;

      final item = log['item_id'] as String;
      final op = log['operation'] as String;
      final qty = log['quantity'] as int;
      final diff = (log['performance_diff'] ?? 0) as int;

      data.putIfAbsent(worker, () => {});
      data[worker]!.putIfAbsent(item, () => {});
      data[worker]![item]!.putIfAbsent(
        op,
        () => {'qty': 0, 'diff': 0, 'workerName': workerName},
      );

      final current = data[worker]![item]![op]!;
      data[worker]![item]![op] = {
        'qty': current['qty'] + qty,
        'diff': current['diff'] + diff,
        'workerName': workerName,
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
        TextCellValue('Worker Name'),
        TextCellValue('Worker ID'),
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
      aggregated.forEach((workerId, items) {
        items.forEach((itemId, ops) {
          ops.forEach((opName, data) {
            final qty = data['qty'];
            final diff = data['diff'];
            final wName = data['workerName'];
            String status = diff >= 0 ? 'Surplus' : 'Deficit';

            sheetObject.appendRow([
              TextCellValue(wName),
              TextCellValue(workerId),
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
        TextCellValue('Worker Name'),
        TextCellValue('Worker ID'),
        TextCellValue('Item ID'),
        TextCellValue('Operation'),
        TextCellValue('Date'),
        TextCellValue('Time'),
        TextCellValue('Machine ID'),
        TextCellValue('Quantity'),
        TextCellValue('Surplus/Deficit'),
        TextCellValue('Status'),
        TextCellValue('Remarks'),
      ]);
      for (final log in allLogs) {
        final wName = (log['workerName'] ?? 'Unknown').toString();
        final workerId = (log['worker_id'] ?? '').toString();
        final itemId = (log['item_id'] ?? '').toString();
        final opName = (log['operation'] ?? '').toString();
        final qty = (log['quantity'] ?? 0) as int;
        final diff = (log['performance_diff'] ?? 0) as int;
        String status = diff >= 0 ? 'Surplus' : 'Deficit';
        final remarks = (log['remarks'] ?? '').toString();
        final createdAtStr = (log['created_at'] ?? '').toString();
        DateTime dt;
        try {
          dt = DateTime.parse(createdAtStr).toLocal();
        } catch (_) {
          dt = DateTime.now();
        }
        final dateStr = DateFormat('yyyy-MM-dd').format(dt);
        final timeStr = DateFormat('HH:mm').format(dt);
        final machineId = (log['machine_id'] ?? '').toString();
        detailsSheet.appendRow([
          TextCellValue(wName),
          TextCellValue(workerId),
          TextCellValue(itemId),
          TextCellValue(opName),
          TextCellValue(dateStr),
          TextCellValue(timeStr),
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
        final file = File(path);
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
          .select('performance_diff, created_at')
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
        workerId: _isWorkerScope ? _selectedWorkerId : null,
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
          _fetchWorkersForDropdown(),
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
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _metricTile(
                  'Extra Units (24h)',
                  '$_extraUnitsToday',
                  Colors.green.shade200,
                  Icons.trending_up,
                ),
                _metricTile(
                  'Workers',
                  '${_workers.length}',
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
                          value: !_isWorkerScope,
                          onChanged: (v) {
                            setState(() {
                              _isWorkerScope = false;
                            });
                            _refreshLineData();
                          },
                        ),
                        const Text('All workers'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _isWorkerScope,
                          onChanged: (v) {
                            setState(() {
                              _isWorkerScope = true;
                            });
                            _refreshLineData();
                          },
                        ),
                        const Text('Specific worker'),
                      ],
                    ),
                    if (_isWorkerScope)
                      DropdownButton<String>(
                        value: _selectedWorkerId,
                        hint: const Text('Select worker'),
                        items: _workers.map((w) {
                          final id = (w['worker_id'] ?? '').toString();
                          final name = (w['name'] ?? '').toString();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text('$name ($id)'),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() => _selectedWorkerId = v);
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
                  height: 240,
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
                                return Text(
                                  '${v}h',
                                  style: const TextStyle(fontSize: 11),
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
          // Worker selection and graphs
          if (_workers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  const Text(
                    'Worker: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    value: _selectedWorkerId,
                    hint: const Text('Select worker'),
                    items: _workers.map((w) {
                      final id = (w['worker_id'] ?? '').toString();
                      final name = (w['name'] ?? '').toString();
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text('$name ($id)'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedWorkerId = v;
                      });
                      if (v != null) {
                        _loadSelectedWorkerCharts(v);
                      }
                    },
                  ),
                ],
              ),
            ),
          if (_selectedWorkerId != null)
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
                    height: 240,
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
                    height: 240,
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
                    height: 200,
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
                      final timestamp = DateTime.parse(
                        log['created_at'],
                      ).toLocal();
                      final workerName = log['workerName'] ?? 'Unknown';
                      final itemName = log['itemName'] ?? 'Unknown';
                      final remarks = log['remarks'] as String?;
                      return ListTile(
                        title: Text('$workerName - $itemName'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${log['operation']} | Qty: ${log['quantity']} | Diff: ${log['performance_diff']}',
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
                          DateFormat('MM/dd HH:mm').format(timestamp),
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
class WorkersTab extends StatefulWidget {
  final String organizationCode;
  const WorkersTab({super.key, required this.organizationCode});

  @override
  State<WorkersTab> createState() => _WorkersTabState();
}

class _WorkersTabState extends State<WorkersTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = true;

  final _workerIdController = TextEditingController();
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
    _fetchWorkers();
  }

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('workers')
          .select()
          .eq('organization_code', widget.organizationCode);
      if (mounted) {
        setState(() {
          _workers = List<Map<String, dynamic>>.from(response);
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

  Future<void> _deleteWorker(String workerId) async {
    try {
      // First delete associated production logs
      await _supabase
          .from('production_logs')
          .delete()
          .eq('worker_id', workerId);

      // Then delete the worker
      await _supabase.from('workers').delete().eq('worker_id', workerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker and associated logs deleted')),
        );
        _fetchWorkers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addWorker() async {
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
        'worker_id': _workerIdController.text,
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
        ).showSnackBar(const SnackBar(content: Text('Worker added!')));
        _clearControllers();
        _fetchWorkers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _clearControllers() {
    _workerIdController.clear();
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
      onRefresh: _fetchWorkers,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ExpansionTile(
              title: const Text('Add New Worker'),
              children: [
                TextField(
                  controller: _workerIdController,
                  decoration: const InputDecoration(labelText: 'Worker ID'),
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
                  onPressed: _addWorker,
                  child: const Text('Add Worker'),
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
                itemCount: _workers.length,
                itemBuilder: (context, index) {
                  final worker = _workers[index];
                  return Card(
                    child: ListTile(
                      title: Text('${worker['name']} (${worker['worker_id']})'),
                      subtitle: Text('Mobile: ${worker['mobile_number']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteWorker(worker['worker_id']),
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

  @override
  void initState() {
    super.initState();
    _fetchMachines();
  }

  Future<void> _fetchMachines() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('machines')
          .select()
          .eq('organization_code', widget.organizationCode);
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
      child: Column(
        children: [
          ExpansionTile(
            title: const Text('Add New Machine'),
            children: [
              TextField(
                controller: _idController,
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
              ElevatedButton(
                onPressed: _addMachine,
                child: const Text('Add Machine'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
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
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _deleteMachine(machine['machine_id']),
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
  picker.XFile? _opImage;

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
          .eq('organization_code', widget.organizationCode);
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

  Future<void> _pickImage() async {
    final imagePicker = picker.ImagePicker();
    final picked = await imagePicker.pickImage(
      source: picker.ImageSource.gallery,
    );
    if (picked != null) {
      setState(() {
        _opImage = picked;
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
          imageFile: _opImage,
        ),
      );
      _opNameController.clear();
      _opTargetController.clear();
      _opImage = null;
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

      // 1. Upload images first and get URLs
      List<Map<String, dynamic>> opJson = [];
      for (var op in _operations) {
        String? imageUrl;
        if (op.imageFile != null) {
          try {
            // Ensure bucket exists (attempt to create if missing)
            try {
              final fileName =
                  '${DateTime.now().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}.jpg';
              final bytes = await op.imageFile!.readAsBytes();

              await _supabase.storage
                  .from('operation_images')
                  .uploadBinary(
                    fileName,
                    bytes,
                    fileOptions: const FileOptions(
                      contentType: 'image/jpeg',
                      upsert: true,
                    ),
                  );
              imageUrl = _supabase.storage
                  .from('operation_images')
                  .getPublicUrl(fileName);
            } catch (e) {
              final errStr = e.toString();
              // Check for RLS (403) or Bucket Missing (404)
              if (errStr.contains('403') ||
                  errStr.contains('row-level security') ||
                  errStr.contains('Unauthorized')) {
                if (mounted) _showRLSErrorDialog(context);
              } else if (errStr.contains('Bucket not found') ||
                  errStr.contains('404')) {
                try {
                  debugPrint('Bucket not found, attempting to create...');
                  // Try creating bucket
                  await _supabase.storage.createBucket(
                    'operation_images',
                    const BucketOptions(public: true),
                  );

                  // Retry upload
                  final fileName =
                      '${DateTime.now().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}.jpg';
                  final bytes = await op.imageFile!.readAsBytes();
                  await _supabase.storage
                      .from('operation_images')
                      .uploadBinary(
                        fileName,
                        bytes,
                        fileOptions: const FileOptions(
                          contentType: 'image/jpeg',
                          upsert: true,
                        ),
                      );
                  imageUrl = _supabase.storage
                      .from('operation_images')
                      .getPublicUrl(fileName);
                } catch (createErr) {
                  debugPrint('Failed to create bucket/upload: $createErr');
                  if (createErr.toString().contains('403') ||
                      createErr.toString().contains('row-level security') ||
                      createErr.toString().contains('Unauthorized')) {
                    if (mounted) _showRLSErrorDialog(context);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Error: "operation_images" bucket missing. Please create it in Supabase Storage.',
                        ),
                        duration: Duration(seconds: 5),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else {
                debugPrint('Image upload failed: $e');
              }
            }
          } catch (e) {
            debugPrint('Image upload critical error: $e');
          }
        }
        opJson.add({
          'name': op.name,
          'target': op.target,
          'imageUrl': imageUrl,
        });
      }

      // 2. Insert Item
      // Note: 'operation' column seems to be required by schema (singular).
      // We populate it with a comma-separated string of operations.
      // We also populate 'operations' (plural array) if it exists.
      final opNames = _operations.map((o) => o.name).toList();

      await _supabase.from('items').insert({
        'item_id': _itemIdController.text,
        'name': _itemNameController.text,
        'operation_details': opJson,
        'operations': opNames, // Standard array column
        'organization_code': widget.organizationCode,
        // 'operation': opNames.join(', '), // Removed due to PGRST204 (column missing)
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

  void _showRLSErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Error (RLS)'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The server rejected the image upload due to Row-Level Security (RLS) policies.',
              ),
              SizedBox(height: 10),
              Text(
                'To fix this, go to your Supabase Dashboard -> SQL Editor and run:',
              ),
              SizedBox(height: 10),
              SelectableText(
                '''insert into storage.buckets (id, name, public) values ('operation_images', 'operation_images', true);
create policy "Public Access" on storage.objects for select using ( bucket_id = 'operation_images' );
create policy "Authenticated Insert" on storage.objects for insert with check ( bucket_id = 'operation_images' );''',
                style: TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor: Color(0xFFEEEEEE),
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Alternatively, go to Storage -> Create "operation_images" bucket (Public) -> Add Policy for INSERT.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(String id) async {
    try {
      await _supabase.from('items').delete().eq('item_id', id);
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
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: ListView(
              children: [
                const Text(
                  'Add New Item',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _itemIdController,
                  decoration: const InputDecoration(
                    labelText: 'Item ID (e.g. 5001)',
                  ),
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Target Quantity',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image),
                            label: const Text('Pick Image'),
                          ),
                          const SizedBox(width: 10),
                          if (_opImage != null)
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: kIsWeb
                                  ? Image.network(
                                      _opImage!.path,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(_opImage!.path),
                                      fit: BoxFit.cover,
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
                      trailing: op.imageUrl != null
                          ? const Icon(Icons.image, color: Colors.blue)
                          : null,
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _addItem,
                  child: const Text('Save Item to Database'),
                ),
              ],
            ),
          ),
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Existing Items',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          Expanded(
            flex: 4,
            child: _isLoadingItems
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? const Center(child: Text('No items found.'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      // Count operations if possible
                      final ops = item['operation_details'] as List? ?? [];
                      return Card(
                        child: ListTile(
                          title: Text('${item['name']} (${item['item_id']})'),
                          subtitle: Text('${ops.length} Operations'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteItem(item['item_id']),
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

  Future<void> _addShift() async {
    try {
      await _supabase.from('shifts').insert({
        'name': _nameController.text,
        'start_time': _startController.text,
        'end_time': _endController.text,
        'organization_code': widget.organizationCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Shift added!')));
        _nameController.clear();
        _startController.clear();
        _endController.clear();
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
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Shift Name (e.g. Morning)',
            ),
          ),
          TextField(
            controller: _startController,
            decoration: const InputDecoration(
              labelText: 'Start Time (e.g. 08:00)',
            ),
          ),
          TextField(
            controller: _endController,
            decoration: const InputDecoration(
              labelText: 'End Time (e.g. 16:00)',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _addShift, child: const Text('Add Shift')),
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
      );
    }

    if (_logs.isEmpty) {
      return const Center(
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
            title: Text(
              'Logged in at ${DateFormat('yyyy-MM-dd HH:mm:ss').format(time)}',
            ),
            subtitle: Text('Device: $device\nOS: $os'),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
