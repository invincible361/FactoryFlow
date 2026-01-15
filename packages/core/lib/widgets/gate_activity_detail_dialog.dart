import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../utils/time_utils.dart';

class GateActivityDetailDialog extends StatefulWidget {
  final String workerId;
  final String workerName;
  final String organizationCode;
  final bool isDarkMode;
  final DateTime? initialDate;

  const GateActivityDetailDialog({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.organizationCode,
    required this.isDarkMode,
    this.initialDate,
  });

  @override
  State<GateActivityDetailDialog> createState() =>
      _GateActivityDetailDialogState();
}

class _GateActivityDetailDialogState extends State<GateActivityDetailDialog> {
  final _supabase = Supabase.instance.client;
  late DateTime _selectedDate;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _productionLogs = [];
  bool _isLoading = true;
  Map<String, String> _machineNames = {};
  Map<String, String> _itemNames = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? TimeUtils.nowIst();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Create UTC start/end for the selected date to ensure we capture all events
      // We take the selected date (00:00 local), convert to UTC, and query.
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Convert to UTC ISO strings for query to match "Store in UTC" policy
      // This ensures we get the full local day's data regardless of timezone
      final startStr = startOfDay.toUtc().toIso8601String();
      final endStr = endOfDay.toUtc().toIso8601String();

      // Ensure dictionaries for machine/item names to avoid Postgrest relationship issues
      if (_machineNames.isEmpty) {
        final machinesResp = await _supabase
            .from('machines')
            .select('machine_id, name')
            .eq('organization_code', widget.organizationCode);
        for (final m in List<Map<String, dynamic>>.from(machinesResp)) {
          final id = m['machine_id']?.toString();
          final name = m['name']?.toString();
          if (id != null && name != null) _machineNames[id] = name;
        }
      }
      if (_itemNames.isEmpty) {
        final itemsResp = await _supabase
            .from('items')
            .select('item_id, name')
            .eq('organization_code', widget.organizationCode);
        for (final i in List<Map<String, dynamic>>.from(itemsResp)) {
          final id = i['item_id']?.toString();
          final name = i['name']?.toString();
          if (id != null && name != null) _itemNames[id] = name;
        }
      }

      // Fetch gate events (new unified table)
      final gateEventsResponse = await _supabase
          .from('gate_events')
          .select()
          .eq('worker_id', widget.workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('timestamp', startStr)
          .lt('timestamp', endStr)
          .order('timestamp', ascending: false);

      // Fetch gate events (legacy table for compatibility)
      final legacyEventsResponse = await _supabase
          .from('worker_boundary_events')
          .select()
          .eq('worker_id', widget.workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', startStr)
          .lt('created_at', endStr)
          .order('created_at', ascending: false);

      // Fetch production logs
      final logsResponse = await _supabase
          .from('production_logs')
          .select(
            'id, worker_id, machine_id, item_id, operation, quantity, is_active, start_time, end_time, created_at, remarks',
          )
          .eq('worker_id', widget.workerId)
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', startStr)
          .lt('created_at', endStr)
          .order('created_at', ascending: false);

      if (mounted) {
        final List<Map<String, dynamic>> gateEvents =
            List<Map<String, dynamic>>.from(gateEventsResponse).map((e) {
              return {
                ...e,
                'type': e['event_type'],
                'created_at': e['timestamp'],
              };
            }).toList();

        final List<Map<String, dynamic>> legacyEvents =
            List<Map<String, dynamic>>.from(legacyEventsResponse);

        final allEvents = [...gateEvents, ...legacyEvents];
        allEvents.sort((a, b) => b['created_at'].compareTo(a['created_at']));

        setState(() {
          _events = allEvents;
          _productionLogs = List<Map<String, dynamic>>.from(logsResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: TimeUtils.nowIst(),
      builder: (context, child) {
        return Theme(
          data: widget.isDarkMode ? ThemeData.dark() : ThemeData.light(),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;
    final subTextColor = widget.isDarkMode ? Colors.white70 : Colors.black54;
    final cardColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey[100]!;

    // Calculate gate stats
    int entryCount = 0;
    int exitCount = 0;
    for (var e in _events) {
      final type = e['type']?.toString().toLowerCase();
      if (type == 'entry') entryCount++;
      if (type == 'exit') exitCount++;
    }

    return Dialog(
      backgroundColor: widget.isDarkMode
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500, // Fixed width for tablet/desktop, adaptive for mobile
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.workerName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Worker Activity History',
                        style: TextStyle(fontSize: 14, color: subTextColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: subTextColor),
                ),
              ],
            ),
            const Divider(),

            // Date Selection
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        DateFormat('MMM dd, yyyy').format(_selectedDate),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Show gate stats here for quick glance
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMiniStat(
                        'Entries',
                        entryCount.toString(),
                        Colors.green,
                      ),
                      const SizedBox(width: 8),
                      _buildMiniStat('Exits', exitCount.toString(), Colors.red),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Tabs for Gate vs Production
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: textColor,
                      unselectedLabelColor: subTextColor,
                      indicatorColor: Colors.teal,
                      tabs: const [
                        Tab(text: 'Gate Activity'),
                        Tab(text: 'Production Logs'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : TabBarView(
                              children: [
                                _buildGateActivityList(
                                  subTextColor,
                                  cardColor,
                                  textColor,
                                ),
                                _buildProductionList(
                                  subTextColor,
                                  cardColor,
                                  textColor,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGateActivityList(
    Color subTextColor,
    Color cardColor,
    Color textColor,
  ) {
    if (_events.isEmpty) {
      return Center(
        child: Text(
          'No gate activity recorded for this date.',
          style: TextStyle(color: subTextColor),
        ),
      );
    }

    return ListView.builder(
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        final type = event['type']?.toString() ?? 'unknown';
        final isEntry = type == 'entry';
        final isPeriodic = type == 'periodic';
        final timestamp = event['created_at'];

        Color iconColor = Colors.grey;
        IconData iconData = Icons.info_outline;

        if (isEntry) {
          iconColor = Colors.green;
          iconData = Icons.login;
        } else if (type == 'exit') {
          iconColor = Colors.red;
          iconData = Icons.logout;
        } else if (isPeriodic) {
          iconColor = Colors.blue;
          iconData = Icons.access_time;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: iconColor.withValues(alpha: 0.1),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            title: Text(
              type.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              TimeUtils.formatFull(timestamp),
              style: TextStyle(color: subTextColor, fontSize: 12),
            ),
            trailing: event['remarks'] != null
                ? Tooltip(
                    message: event['remarks'],
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildProductionList(
    Color subTextColor,
    Color cardColor,
    Color textColor,
  ) {
    if (_productionLogs.isEmpty) {
      return Center(
        child: Text(
          'No production logs recorded for this date.',
          style: TextStyle(color: subTextColor),
        ),
      );
    }

    return ListView.builder(
      itemCount: _productionLogs.length,
      itemBuilder: (context, index) {
        final log = _productionLogs[index];
        final machineName =
            _machineNames[log['machine_id']?.toString()] ??
            log['machine_id']?.toString() ??
            'Unknown Machine';
        final itemName =
            _itemNames[log['item_id']?.toString()] ??
            log['item_id']?.toString() ??
            'Unknown Item';
        final operation = log['operation'] ?? 'Unknown Operation';
        final isActive = log['is_active'] == true;
        final startTime = log['start_time'] ?? log['created_at'];
        final endTime = log['end_time'];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(color: Colors.blue.withValues(alpha: 0.5))
                : null,
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isActive
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              child: Icon(
                isActive ? Icons.engineering : Icons.check_circle_outline,
                color: isActive ? Colors.blue : Colors.grey,
                size: 20,
              ),
            ),
            title: Text(
              '$itemName - $operation',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Machine: $machineName',
                  style: TextStyle(color: subTextColor, fontSize: 12),
                ),
                Text(
                  isActive
                      ? 'Started: ${TimeUtils.formatFull(startTime)}'
                      : 'Ended: ${TimeUtils.formatFull(endTime ?? startTime)}',
                  style: TextStyle(color: subTextColor, fontSize: 12),
                ),
              ],
            ),
            trailing: isActive
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  )
                : Text(
                    'Qty: ${log['quantity']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
