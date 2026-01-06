import 'package:flutter/material.dart';
import 'dart:async';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:intl/intl.dart';

class ComparisonTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;

  const ComparisonTab({
    super.key,
    required this.organizationCode,
    required this.isDarkMode,
  });

  @override
  State<ComparisonTab> createState() => _ComparisonTabState();
}

class _ComparisonTabState extends State<ComparisonTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  DateTimeRange? _dateRange;
  String? _selectedWorkerId;
  List<Map<String, dynamic>> _workers = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _dateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 7)),
      end: DateTime.now(),
    );
    _fetchWorkers();
    _fetchLogs();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchLogs();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWorkers() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name');
      if (mounted) {
        setState(() => _workers = List<Map<String, dynamic>>.from(resp));
      }
    } catch (e) {
      debugPrint('Error fetching workers: $e');
    }
  }

  Future<void> _fetchLogs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    debugPrint('Fetching logs for org: ${widget.organizationCode}');
    try {
      var query = _supabase
          .from('production_logs')
          .select(
              '*, workers:worker_id(name), items:item_id(name), machines:machine_id(name)')
          .eq('organization_code', widget.organizationCode);

      if (_selectedWorkerId != null) {
        query = query.eq('worker_id', _selectedWorkerId!);
      }

      if (_dateRange != null) {
        query = query
            .gte('created_at', _dateRange!.start.toIso8601String())
            .lte('created_at',
                _dateRange!.end.add(const Duration(days: 1)).toIso8601String());
      }

      final response = await query.order('created_at', ascending: false);
      final rawLogs = List<Map<String, dynamic>>.from(response);
      debugPrint('Fetched ${rawLogs.length} logs');
      final enriched = await _enrichLogsWithNames(rawLogs);

      if (mounted) {
        setState(() {
          _logs = enriched;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching logs (direct join): $e');
      // Fallback if relationship fails (PGRST200)
      if (e.toString().contains('relationship') ||
          e.toString().contains('foreign') ||
          e.toString().contains('PGRST200')) {
        try {
          var fallbackQuery = _supabase
              .from('production_logs')
              .select()
              .eq('organization_code', widget.organizationCode);

          if (_selectedWorkerId != null) {
            fallbackQuery = fallbackQuery.eq('worker_id', _selectedWorkerId!);
          }

          if (_dateRange != null) {
            fallbackQuery = fallbackQuery
                .gte('created_at', _dateRange!.start.toIso8601String())
                .lte(
                    'created_at',
                    _dateRange!.end
                        .add(const Duration(days: 1))
                        .toIso8601String());
          }

          final fallbackResponse =
              await fallbackQuery.order('created_at', ascending: false);
          final enriched = await _enrichLogsWithNames(
            List<Map<String, dynamic>>.from(fallbackResponse),
          );
          if (mounted) {
            setState(() {
              _logs = enriched;
              _isLoading = false;
            });
          }
          return;
        } catch (_) {}
      }

      debugPrint('Error fetching logs: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
      final machinesResp = await _supabase
          .from('machines')
          .select('machine_id, name')
          .eq('organization_code', widget.organizationCode);

      final employeeMap = <String, String>{};
      final itemMap = <String, String>{};
      final machineMap = <String, String>{};

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
      for (final m in List<Map<String, dynamic>>.from(machinesResp)) {
        final id = m['machine_id']?.toString() ?? '';
        final name = m['name']?.toString() ?? '';
        if (id.isNotEmpty) machineMap[id] = name;
      }

      return rawLogs.map((log) {
        final wid = log['worker_id']?.toString() ?? '';
        final iid = log['item_id']?.toString() ?? '';
        final mid = log['machine_id']?.toString() ?? '';

        // Handle both joined and non-joined (fallback) cases
        final workerData = log['workers'] as Map<String, dynamic>?;
        final itemData = log['items'] as Map<String, dynamic>?;
        final machineData = log['machines'] as Map<String, dynamic>?;

        return {
          ...log,
          'workers': workerData ?? {'name': employeeMap[wid] ?? 'Unknown'},
          'items': itemData ?? {'name': itemMap[iid] ?? 'Unknown Item'},
          'machines': machineData ?? {'name': machineMap[mid] ?? 'N/A'},
        };
      }).toList();
    } catch (_) {
      return rawLogs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;

    return Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedWorkerId,
                  dropdownColor: cardColor,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Worker',
                    labelStyle: TextStyle(color: textColor.withOpacity(0.7)),
                    filled: true,
                    fillColor: widget.isDarkMode
                        ? Colors.white.withOpacity(0.05)
                        : Colors.grey.withOpacity(0.1),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Workers')),
                    ..._workers.map((w) => DropdownMenuItem(
                          value: w['worker_id'].toString(),
                          child: Text(w['name'] ?? 'Unknown'),
                        )),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedWorkerId = val);
                    _fetchLogs();
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    initialDateRange: _dateRange,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    setState(() => _dateRange = picked);
                    _fetchLogs();
                  }
                },
                icon: const Icon(Icons.date_range),
                label: Text(_dateRange == null
                    ? 'Select Date'
                    : '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.2),
                  foregroundColor: textColor,
                ),
              ),
            ],
          ),
        ),
        // Summary
        if (!_isLoading) _buildSummaryCards(),
        // Table
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? const Center(child: Text('No production logs found'))
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final workerQty =
                            (log['quantity'] as num? ?? 0).toInt();
                        final supervisorQty =
                            (log['supervisor_quantity'] as num? ?? 0).toInt();
                        final diff = workerQty - supervisorQty;
                        final isVerified = log['is_verified'] ?? false;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: cardColor,
                          child: ListTile(
                            title: Text(
                              '${log['workers']?['name'] ?? 'Unknown'} - ${log['items']?['name'] ?? 'Unknown Item'}',
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Date: ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.parse(log['created_at']).toLocal())}',
                                  style: TextStyle(
                                      color: textColor.withOpacity(0.6)),
                                ),
                                Text(
                                  'Machine: ${log['machines']?['name'] ?? 'N/A'}',
                                  style: TextStyle(
                                      color: textColor.withOpacity(0.6)),
                                ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Worker: $workerQty',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: textColor)),
                                Text(
                                    'Sup: ${isVerified ? supervisorQty : "Pending"}',
                                    style: TextStyle(
                                        color: isVerified
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.bold)),
                                if (isVerified && diff != 0)
                                  Text('Diff: ${diff > 0 ? "+$diff" : diff}',
                                      style: TextStyle(
                                          color: diff > 0
                                              ? Colors.red
                                              : Colors.blue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    int totalWorker = 0;
    int totalSupervisor = 0;
    int verifiedCount = 0;

    for (var log in _logs) {
      totalWorker += (log['quantity'] as num? ?? 0).toInt();
      if (log['is_verified'] == true) {
        totalSupervisor += (log['supervisor_quantity'] as num? ?? 0).toInt();
        verifiedCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _buildStatCard('Worker Output', totalWorker.toString(), Colors.blue),
          const SizedBox(width: 16),
          _buildStatCard(
              'Supervisor Verified', totalSupervisor.toString(), Colors.green),
          const SizedBox(width: 16),
          _buildStatCard('Pending', (_logs.length - verifiedCount).toString(),
              Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;
    return Expanded(
      child: Card(
        color:
            widget.isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 10, color: textColor.withOpacity(0.7))),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
