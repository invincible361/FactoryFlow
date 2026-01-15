import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:fl_chart/fl_chart.dart';

class VisualisationTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const VisualisationTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<VisualisationTab> createState() => _VisualisationTabState();
}

class _VisualisationTabState extends State<VisualisationTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _weekLogs = [];
  List<Map<String, dynamic>> _monthLogs = [];
  List<Map<String, dynamic>> _extraWeekLogs = [];
  List<Map<String, dynamic>> _summaryLogs = [];
  Map<String, List<FlSpot>> _comparativeSpots = {}; // workerId -> spots
  List<String> _comparativeWorkerIds = []; // To map index to workerId
  bool _isEmployeeScope = false;
  String _linePeriod = 'Week';
  int _currentOffset = 0;
  final PageController _pageController = PageController(initialPage: 500);
  List<FlSpot> _lineSpots = [];
  String _currentRangeTitle = '';

  // Machine/Item/Operation Visualisation State
  String _selectedMachineId = 'All';
  String _selectedItemId = 'All';
  String _selectedOperation = 'All';
  List<Map<String, dynamic>> _machinesList = [];
  List<Map<String, dynamic>> _itemsList = [];
  List<String> _operationsList = [];

  @override
  void initState() {
    super.initState();
    _fetchEmployeesForDropdown();
    _fetchFilterData();
    _fetchSummaryData();
    _refreshLineData();
  }

  List<Map<String, dynamic>> get _filteredSummaryLogs {
    return _summaryLogs.where((log) {
      bool machineMatch = _selectedMachineId == 'All' ||
          log['machine_id'].toString() == _selectedMachineId;
      bool itemMatch = _selectedItemId == 'All' ||
          log['item_id'].toString() == _selectedItemId;
      bool opMatch = _selectedOperation == 'All' ||
          log['operation'].toString() == _selectedOperation;
      return machineMatch && itemMatch && opMatch;
    }).toList();
  }

  Future<void> _fetchSummaryData() async {
    try {
      final nowUtc = TimeUtils.nowUtc();
      final start = DateTime(nowUtc.year, nowUtc.month, nowUtc.day)
          .subtract(const Duration(days: 30));

      final response = await _supabase
          .from('production_logs')
          .select('operation, item_id, machine_id, quantity, created_at')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', start.toIso8601String());

      if (mounted) {
        setState(() {
          _summaryLogs = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching summary data: $e');
    }
  }

  Future<void> _fetchFilterData() async {
    try {
      final machinesResp = await _supabase
          .from('machines')
          .select('machine_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name');
      final itemsResp = await _supabase
          .from('items')
          .select('item_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name');
      final logsResp = await _supabase
          .from('production_logs')
          .select('operation')
          .eq('organization_code', widget.organizationCode);

      final ops = (logsResp as List)
          .map((e) => e['operation']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      ops.sort();

      if (mounted) {
        setState(() {
          _machinesList = List<Map<String, dynamic>>.from(machinesResp);
          _itemsList = List<Map<String, dynamic>>.from(itemsResp);
          _operationsList = ops;
        });
      }
    } catch (e) {
      debugPrint('Error fetching filter data: $e');
    }
  }

  Future<void> _fetchEmployeesForDropdown() async {
    try {
      final response = await _supabase
          .from('workers')
          .select('worker_id, name, role')
          .eq('organization_code', widget.organizationCode)
          .neq('role', 'supervisor')
          .order('name');
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(response);
          if (_employees.isNotEmpty && _selectedEmployeeId == null) {
            _selectedEmployeeId = _employees.first['worker_id'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching employees for dropdown: $e');
    }
  }

  Widget _buildUsageChart({
    required String title,
    required List<Map<String, dynamic>> data,
    required String key,
    required Color barColor,
  }) {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;

    final top5 = data.take(5).toList();

    if (top5.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: subTextColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return _chartCard(
      title: title,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.5,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: top5.isEmpty
                    ? 10
                    : top5
                            .map((e) => (e['qty'] as num).toDouble())
                            .reduce((a, b) => a > b ? a : b) *
                        1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => cardBg,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        rod.toY.toStringAsFixed(0),
                        TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= top5.length) {
                          return const SizedBox.shrink();
                        }
                        final label = top5[index][key].toString();
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              label.length > 10
                                  ? '${label.substring(0, 8)}..'
                                  : label,
                              style: TextStyle(
                                color: subTextColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: top5.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: (entry.value['qty'] as num).toDouble(),
                        color: barColor,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...top5.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: barColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e[key].toString(),
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${e['qty']} units (${e['count']} logs)',
                      style: TextStyle(
                          color: subTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _chartCard({required String title, required Widget child}) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: const Color(0xFFA9DFD8).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFFA9DFD8),
      labelStyle: TextStyle(
        color: isSelected
            ? const Color(0xFFA9DFD8)
            : (widget.isDarkMode ? Colors.white70 : Colors.black54),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      backgroundColor: widget.isDarkMode ? Colors.white10 : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? const Color(0xFFA9DFD8) : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: subTextColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: cardBg,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _computeTopByKey(
      List<Map<String, dynamic>> logs, String key) {
    final Map<String, Map<String, dynamic>> aggregation = {};
    for (final log in logs) {
      final val = log[key] ?? 'Unknown';
      final qty = (log['quantity'] ?? 0) as int;
      if (!aggregation.containsKey(val)) {
        aggregation[val] = {
          key: val,
          'count': 0,
          'qty': 0,
        };
      }
      aggregation[val]!['count'] += 1;
      aggregation[val]!['qty'] += qty;
    }
    final list = aggregation.values.toList();
    list.sort((a, b) => b['qty'].compareTo(a['qty']));
    return list;
  }

  Future<void> _refreshLineData() async {
    try {
      final now = TimeUtils.nowUtc();
      DateTime start;
      DateTime end;

      if (_linePeriod == 'Day') {
        final date = now.add(Duration(days: _currentOffset));
        start = DateTime(date.year, date.month, date.day);
        end = start.add(const Duration(days: 1));
        _currentRangeTitle = DateFormat('MMM d, yyyy').format(start);
      } else if (_linePeriod == 'Week') {
        // Start of current week (Monday)
        final weekday = now.weekday; // 1 = Monday, ..., 7 = Sunday
        final currentWeekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        start = currentWeekStart.add(Duration(days: _currentOffset * 7));
        end = start.add(const Duration(days: 7));
        _currentRangeTitle =
            '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, yyyy').format(end.subtract(const Duration(seconds: 1)))}';
      } else if (_linePeriod == 'Month') {
        start = DateTime(now.year, now.month + _currentOffset, 1);
        end = DateTime(start.year, start.month + 1, 1);
        _currentRangeTitle = DateFormat('MMMM yyyy').format(start);
      } else {
        // Year
        start = DateTime(now.year + _currentOffset, 1, 1);
        end = DateTime(start.year + 1, 1, 1);
        _currentRangeTitle = DateFormat('yyyy').format(start);
      }

      var query = _supabase
          .from('production_logs')
          .select(
              'created_at, quantity, machine_id, item_id, operation, worker_id')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', start.toUtc().toIso8601String())
          .lt('created_at', end.toUtc().toIso8601String());

      if (_isEmployeeScope && _selectedEmployeeId != null) {
        query = query.eq('worker_id', _selectedEmployeeId!);
      }
      if (_selectedMachineId != 'All') {
        query = query.eq('machine_id', _selectedMachineId);
      }
      if (_selectedItemId != 'All') {
        query = query.eq('item_id', _selectedItemId);
      }
      if (_selectedOperation != 'All') {
        query = query.eq('operation', _selectedOperation);
      }

      final response = await query;
      final logs = List<Map<String, dynamic>>.from(response);

      // Comparative data
      final Map<String, Map<int, double>> workerGrouped = {};
      for (final log in logs) {
        final wId = log['worker_id']?.toString() ?? 'Unknown';
        final dt = DateTime.parse(log['created_at']).toUtc();
        int index;
        if (_linePeriod == 'Day') {
          index = dt.hour;
        } else if (_linePeriod == 'Week') {
          index = dt.difference(start).inDays;
        } else if (_linePeriod == 'Month') {
          index = dt.day - 1;
        } else {
          index = dt.month - 1;
        }

        workerGrouped.putIfAbsent(wId, () => {});
        workerGrouped[wId]![index] =
            (workerGrouped[wId]![index] ?? 0) + (log['quantity'] ?? 0);
      }

      final Map<String, List<FlSpot>> compSpots = {};
      int maxIdx;
      if (_linePeriod == 'Day') {
        maxIdx = 23;
      } else if (_linePeriod == 'Week') {
        maxIdx = 6;
      } else if (_linePeriod == 'Month') {
        maxIdx = end.subtract(const Duration(days: 1)).day - 1;
      } else {
        maxIdx = 11;
      }

      workerGrouped.forEach((wId, map) {
        final List<FlSpot> spots = [];
        for (int i = 0; i <= maxIdx; i++) {
          spots.add(FlSpot(i.toDouble(), map[i] ?? 0));
        }
        compSpots[wId] = spots;
      });

      // Total data for main line chart
      final Map<int, double> totalGrouped = {};
      for (final log in logs) {
        final dt = DateTime.parse(log['created_at']).toUtc();
        int index;
        if (_linePeriod == 'Day') {
          index = dt.hour;
        } else if (_linePeriod == 'Week') {
          index = dt.difference(start).inDays;
        } else if (_linePeriod == 'Month') {
          index = dt.day - 1;
        } else {
          index = dt.month - 1;
        }
        totalGrouped[index] =
            (totalGrouped[index] ?? 0) + (log['quantity'] ?? 0);
      }

      final List<FlSpot> mainSpots = [];
      for (int i = 0; i <= maxIdx; i++) {
        mainSpots.add(FlSpot(i.toDouble(), totalGrouped[i] ?? 0));
      }

      if (mounted) {
        setState(() {
          _lineSpots = mainSpots;
          _comparativeSpots = compSpots;
          _comparativeWorkerIds = compSpots.keys.toList();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing line data: $e');
    }
  }

  Future<void> _loadSelectedEmployeeCharts(String workerId) async {
    try {
      final now = DateTime.now();
      final startWeek = now.subtract(const Duration(days: 7));
      final startMonth = now.subtract(const Duration(days: 30));
      final startExtra = now.subtract(const Duration(days: 60));

      final weekResp = await _supabase
          .from('production_logs')
          .select('quantity, created_at')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', startWeek.toIso8601String());

      final monthResp = await _supabase
          .from('production_logs')
          .select('quantity, created_at')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', startMonth.toIso8601String());

      final extraResp = await _supabase
          .from('production_logs')
          .select('quantity, created_at')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', startExtra.toIso8601String());

      if (mounted) {
        setState(() {
          _weekLogs = List<Map<String, dynamic>>.from(weekResp);
          _monthLogs = List<Map<String, dynamic>>.from(monthResp);
          _extraWeekLogs = List<Map<String, dynamic>>.from(extraResp);
        });
      }
    } catch (e) {
      debugPrint('Error loading efficiency charts: $e');
    }
  }

  List<BarChartGroupData> _buildPeriodGroups(
      List<Map<String, dynamic>> logs, String period) {
    final Map<int, double> grouped = {};
    final now = DateTime.now();

    for (final log in logs) {
      final dt = DateTime.parse(log['created_at']).toLocal();
      int index;
      if (period == 'Week') {
        index = dt.difference(now.subtract(const Duration(days: 7))).inDays;
      } else {
        index = dt.difference(now.subtract(const Duration(days: 30))).inDays;
      }
      if (index >= 0) {
        grouped[index] = (grouped[index] ?? 0) + (log['quantity'] ?? 0);
      }
    }

    final int count = period == 'Week' ? 7 : 30;
    return List.generate(count, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: grouped[i] ?? 0,
            color: const Color(0xFFA9DFD8),
            width: period == 'Week' ? 12 : 4,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    });
  }

  List<BarChartGroupData> _buildExtraWeekGroups(
      List<Map<String, dynamic>> logs) {
    final Map<int, double> grouped = {};
    final now = DateTime.now();

    for (final log in logs) {
      final dt = DateTime.parse(log['created_at']).toLocal();
      final diff = now.difference(dt).inDays;
      final weekIndex = 7 - (diff ~/ 7) - 1;
      if (weekIndex >= 0 && weekIndex < 8) {
        grouped[weekIndex] = (grouped[weekIndex] ?? 0) + (log['quantity'] ?? 0);
      }
    }

    return List.generate(8, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: grouped[i] ?? 0,
            color: const Color(0xFFC2EBAE),
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    final topMachines = _computeTopByKey(_filteredSummaryLogs, 'machine_id');
    final topItems = _computeTopByKey(_filteredSummaryLogs, 'item_id');
    final topOps = _computeTopByKey(_filteredSummaryLogs, 'operation');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visual Analytics',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Monitor production performance across your organization',
            style: TextStyle(color: subTextColor, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Filters Section
          _chartCard(
            title: 'Filters',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterDropdown(
                        label: 'Machine',
                        value: _selectedMachineId,
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Machines')),
                          ..._machinesList.map((m) => DropdownMenuItem(
                                value: m['machine_id'].toString(),
                                child: Text(m['name'] ?? m['machine_id']),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedMachineId = v ?? 'All');
                          _refreshLineData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFilterDropdown(
                        label: 'Item',
                        value: _selectedItemId,
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Items')),
                          ..._itemsList.map((i) => DropdownMenuItem(
                                value: i['item_id'].toString(),
                                child: Text(i['name'] ?? i['item_id']),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedItemId = v ?? 'All');
                          _refreshLineData();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildFilterDropdown(
                  label: 'Operation',
                  value: _selectedOperation,
                  items: [
                    const DropdownMenuItem(
                        value: 'All', child: Text('All Operations')),
                    ..._operationsList.map((op) => DropdownMenuItem(
                          value: op,
                          child: Text(op),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedOperation = v ?? 'All');
                    _refreshLineData();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Top 5 Machines & Items
          Row(
            children: [
              Expanded(
                child: _buildUsageChart(
                  title: 'Top Machines (Last 30 Days)',
                  data: topMachines,
                  key: 'machine_id',
                  barColor: const Color(0xFFA9DFD8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildUsageChart(
                  title: 'Top Items (Last 30 Days)',
                  data: topItems,
                  key: 'item_id',
                  barColor: const Color(0xFFC2EBAE),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Top Operations
          _buildUsageChart(
            title: 'Operation Distribution (Last 30 Days)',
            data: topOps,
            key: 'operation',
            barColor: const Color(0xFFFFB347),
          ),
          const SizedBox(height: 20),

          // Production Trends
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: 'Organization Wide',
                      isSelected: !_isEmployeeScope,
                      onSelected: (v) {
                        setState(() {
                          _isEmployeeScope = false;
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Specific Employee',
                      isSelected: _isEmployeeScope,
                      onSelected: (v) {
                        setState(() {
                          _isEmployeeScope = true;
                        });
                        _refreshLineData();
                      },
                    ),
                    if (_isEmployeeScope) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: borderColor,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedEmployeeId,
                            hint: Text(
                              'Select employee',
                              style: TextStyle(
                                fontSize: 13,
                                color: subTextColor,
                              ),
                            ),
                            dropdownColor: cardBg,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
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
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: 'Daily',
                      isSelected: _linePeriod == 'Day',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Day';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Weekly',
                      isSelected: _linePeriod == 'Week',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Week';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Monthly',
                      isSelected: _linePeriod == 'Month',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Month';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Yearly',
                      isSelected: _linePeriod == 'Year',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Year';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _chartCard(
                title: 'Production Quantity Overview',
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: textColor),
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                        Text(
                          _currentRangeTitle,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right, color: textColor),
                          onPressed: _currentOffset >= 0
                              ? null
                              : () {
                                  _pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: MediaQuery.of(context).orientation ==
                              Orientation.landscape
                          ? 16 / 6
                          : 9 / 5,
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _currentOffset = index - 500;
                          });
                          _refreshLineData();
                        },
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: LineChart(
                              LineChartData(
                                lineTouchData: LineTouchData(
                                  enabled: true,
                                  handleBuiltInTouches: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (_) => cardBg,
                                    tooltipRoundedRadius: 8,
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots
                                          .map(
                                            (s) => LineTooltipItem(
                                              s.y.toStringAsFixed(0),
                                              TextStyle(
                                                color: textColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                          .toList();
                                    },
                                  ),
                                ),
                                gridData: const FlGridData(show: false),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 32,
                                      getTitlesWidget: (value, meta) {
                                        final v = value.toInt();
                                        String text = '';
                                        if (_linePeriod == 'Day') {
                                          if (v % 6 != 0) {
                                            return const SizedBox();
                                          }
                                          final hour =
                                              v % 12 == 0 ? 12 : v % 12;
                                          final amPm = v < 12 ? 'AM' : 'PM';
                                          text = '$hour$amPm';
                                        } else if (_linePeriod == 'Week') {
                                          final days = [
                                            'Mon',
                                            'Tue',
                                            'Wed',
                                            'Thu',
                                            'Fri',
                                            'Sat',
                                            'Sun'
                                          ];
                                          if (v >= 0 && v < 7) text = days[v];
                                        } else if (_linePeriod == 'Month') {
                                          if ((v + 1) % 5 != 0) {
                                            return const SizedBox();
                                          }
                                          text = '${v + 1}';
                                        } else {
                                          // Year
                                          final months = [
                                            'Jan',
                                            'Feb',
                                            'Mar',
                                            'Apr',
                                            'May',
                                            'Jun',
                                            'Jul',
                                            'Aug',
                                            'Sep',
                                            'Oct',
                                            'Nov',
                                            'Dec'
                                          ];
                                          if (v >= 0 && v < 12) {
                                            text = months[v];
                                          }
                                        }
                                        return SideTitleWidget(
                                          meta: meta,
                                          space: 10,
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: subTextColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          value.toInt().toString(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: subTextColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _lineSpots,
                                    isCurved: true,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFA9DFD8),
                                        Color(0xFFC2EBAE)
                                      ],
                                    ),
                                    barWidth: 3,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          const Color(0xFFA9DFD8)
                                              .withValues(alpha: 0.2),
                                          const Color(0xFFA9DFD8)
                                              .withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
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
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Comparative Production Chart
          if (_comparativeSpots.isNotEmpty)
            _chartCard(
              title: 'Comparative Production by Employee',
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 6
                        : 9 / 5,
                    child: LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((s) {
                                if (s.barIndex >=
                                    _comparativeWorkerIds.length) {
                                  return LineTooltipItem(
                                    'Unknown: ${s.y.toInt()}',
                                    TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  );
                                }
                                final workerId =
                                    _comparativeWorkerIds[s.barIndex];
                                final worker = _employees.firstWhere(
                                  (w) => w['worker_id'] == workerId,
                                  orElse: () => {'name': workerId},
                                );
                                return LineTooltipItem(
                                  '${worker['name']}: ${s.y.toInt()}',
                                  TextStyle(
                                    color: s.bar.gradient?.colors.first ??
                                        textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                String text = '';
                                if (_linePeriod == 'Day') {
                                  if (v % 6 != 0) return const SizedBox();
                                  final hour = v % 12 == 0 ? 12 : v % 12;
                                  final amPm = v < 12 ? 'AM' : 'PM';
                                  text = '$hour$amPm';
                                } else if (_linePeriod == 'Week') {
                                  final days = [
                                    'Mon',
                                    'Tue',
                                    'Wed',
                                    'Thu',
                                    'Fri',
                                    'Sat',
                                    'Sun'
                                  ];
                                  if (v >= 0 && v < 7) text = days[v];
                                } else if (_linePeriod == 'Month') {
                                  if ((v + 1) % 5 != 0) return const SizedBox();
                                  text = '${v + 1}';
                                } else {
                                  final months = [
                                    'Jan',
                                    'Feb',
                                    'Mar',
                                    'Apr',
                                    'May',
                                    'Jun',
                                    'Jul',
                                    'Aug',
                                    'Sep',
                                    'Oct',
                                    'Nov',
                                    'Dec'
                                  ];
                                  if (v >= 0 && v < 12) text = months[v];
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: _comparativeSpots.entries.map((entry) {
                          final wId = entry.key;
                          final spots = entry.value;
                          final color = Colors.primaries[
                              wId.hashCode % Colors.primaries.length];
                          return LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            barWidth: 2,
                            gradient: LinearGradient(
                              colors: [
                                color,
                                color.withValues(alpha: 0.7),
                              ],
                            ),
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: false),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: _comparativeSpots.keys.map((wId) {
                      final worker = _employees.firstWhere(
                        (w) => w['worker_id'] == wId,
                        orElse: () => {'name': wId},
                      );
                      final color = Colors
                          .primaries[wId.hashCode % Colors.primaries.length];
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            worker['name'] ?? wId,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          // Employee selection and graphs
          if (_employees.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Efficiency Analytics Filter',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: subTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedEmployeeId,
                      hint: Text(
                        'Select employee for efficiency graphs',
                        style: TextStyle(fontSize: 13, color: subTextColor),
                      ),
                      dropdownColor: cardBg,
                      isExpanded: true,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
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
                  ),
                ),
                const SizedBox(height: 16),
                _chartCard(
                  title: 'Weekly Production',
                  child: AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 5
                        : 9 / 4,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: _buildPeriodGroups(_weekLogs, 'Week'),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    'D${v + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _chartCard(
                  title: 'Monthly Production',
                  child: AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 5
                        : 9 / 4,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: _buildPeriodGroups(_monthLogs, 'Month'),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 5 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    '${v + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _chartCard(
                  title: 'Weekly Extra Work',
                  child: AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 5
                        : 9 / 4,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: _buildExtraWeekGroups(_extraWeekLogs),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    'W${v + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
