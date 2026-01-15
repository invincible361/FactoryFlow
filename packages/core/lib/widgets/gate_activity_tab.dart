import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../utils/time_utils.dart';
import 'gate_activity_detail_dialog.dart';

class GateActivityTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;

  const GateActivityTab({
    super.key,
    required this.organizationCode,
    required this.isDarkMode,
  });

  @override
  State<GateActivityTab> createState() => _GateActivityTabState();
}

class _GateActivityTabState extends State<GateActivityTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _gateActivityStats = [];
  bool _isLoading = true;
  String _sortBy = 'last_event'; // 'name', 'entries', 'status'
  DateTime _selectedDate = TimeUtils.nowIst();

  Timer? _refreshTimer;
  RealtimeChannel? _realtimeChannel;
  Map<String, String> _machineNames = {};
  Map<String, String> _itemNames = {};

  @override
  void initState() {
    super.initState();
    _fetchGateActivityStats();
    _setupRealtime();
    // Refresh stats every 30 seconds for real-time visibility
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchGateActivityStats();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = _supabase.channel('gate_activity_tab');

    _realtimeChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'production_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            debugPrint('Realtime: production_logs change detected');
            _fetchGateActivityStats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'worker_boundary_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            debugPrint('Realtime: worker_boundary_events change detected');
            _fetchGateActivityStats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'gate_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            debugPrint('Realtime: gate_events change detected');
            _fetchGateActivityStats();
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('Realtime subscription error: $error');
          }
          debugPrint('Realtime subscription status: $status');
          if (status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            // Attempt to reconnect after a delay
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) _setupRealtime();
            });
          }
        });
  }

  void _sortStats() {
    setState(() {
      if (_sortBy == 'name') {
        _gateActivityStats.sort((a, b) {
          final nameA = a['workers']?['name']?.toString().toLowerCase() ?? '';
          final nameB = b['workers']?['name']?.toString().toLowerCase() ?? '';
          return nameA.compareTo(nameB);
        });
      } else if (_sortBy == 'entries') {
        _gateActivityStats.sort((a, b) {
          final countA = (a['entry_count'] ?? 0) as int;
          final countB = (b['entry_count'] ?? 0) as int;
          return countB.compareTo(countA);
        });
      } else if (_sortBy == 'status') {
        _gateActivityStats.sort((a, b) {
          // Status logic: Inside first
          final aIsInside = (a['entry_count'] ?? 0) > (a['exit_count'] ?? 0);
          final bIsInside = (b['entry_count'] ?? 0) > (b['exit_count'] ?? 0);
          if (aIsInside == bIsInside) return 0;
          return aIsInside ? -1 : 1;
        });
      } else {
        // last_event (default)
        _gateActivityStats.sort((a, b) {
          final timeA = a['last_event_time']?.toString() ?? '';
          final timeB = b['last_event_time']?.toString() ?? '';
          return timeB.compareTo(timeA);
        });
      }
    });
  }

  Future<void> _fetchGateActivityStats() async {
    try {
      final selectedUtc = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedUtc);
      final yesterdayStr = DateFormat(
        'yyyy-MM-dd',
      ).format(selectedUtc.subtract(const Duration(days: 1)));

      // Ensure dictionaries
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

      // Try with join first
      try {
        final response = await _supabase
            .from('daily_geofence_summaries')
            .select('*, workers(name, role)')
            .eq('organization_code', widget.organizationCode)
            .or('date.eq.$dateStr,date.eq.$yesterdayStr')
            .order('last_event_time', ascending: false);

        // Fetch active production logs
        final activeLogsResponse = await _supabase
            .from('production_logs')
            .select('worker_id, machine_id, item_id')
            .eq('organization_code', widget.organizationCode)
            .eq('is_active', true);

        final activeLogs = List<Map<String, dynamic>>.from(activeLogsResponse);
        final activeLogMap = {
          for (var log in activeLogs) log['worker_id']: log,
        };

        if (mounted) {
          final stats = List<Map<String, dynamic>>.from(response);

          // Filter out entries where the worker's role is not 'worker'
          final filteredStats = stats.where((stat) {
            final worker = stat['workers'] as Map<String, dynamic>?;
            if (worker != null && worker.containsKey('role')) {
              return worker['role']?.toString().toLowerCase() == 'worker';
            }
            return true;
          }).toList();

          final targetY = _selectedDate.year;
          final targetM = _selectedDate.month;
          final targetD = _selectedDate.day;
          final sameLocalDay = filteredStats.where((s) {
            final ts = s['last_event_time'];
            if (ts == null) return false;
            final dt = TimeUtils.parseToLocal(ts.toString());
            return dt.year == targetY &&
                dt.month == targetM &&
                dt.day == targetD;
          }).toList();

          // Merge active log info
          for (var stat in sameLocalDay) {
            final workerId = stat['worker_id'];
            if (activeLogMap.containsKey(workerId)) {
              stat['active_log'] = activeLogMap[workerId];
            }
          }

          if (sameLocalDay.isNotEmpty) {
            setState(() {
              _gateActivityStats = sameLocalDay;
              _isLoading = false;
              _sortStats();
            });
          } else {
            setState(() {
              _gateActivityStats = [];
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        debugPrint('Gate Activity fetch error (join): $e');
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Gate Activity fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_gateActivityStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.door_front_door_outlined,
              size: 64,
              color: widget.isDarkMode ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              'No gate activity for ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
              style: TextStyle(
                color: widget.isDarkMode ? Colors.white54 : Colors.black54,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _gateActivityStats.length,
            itemBuilder: (context, index) {
              final stat = _gateActivityStats[index];
              return _buildStatCard(stat);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: widget.isDarkMode ? Colors.black26 : Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2023),
                  lastDate: TimeUtils.nowIst(),
                  builder: (context, child) {
                    return Theme(
                      data: widget.isDarkMode
                          ? ThemeData.dark()
                          : ThemeData.light(),
                      child: child!,
                    );
                  },
                );
                if (picked != null && picked != _selectedDate) {
                  setState(() => _selectedDate = picked);
                  _fetchGateActivityStats();
                }
              },
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
            ),
            const SizedBox(width: 12),
            const Text(
              'Sort by:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(width: 8),
            _buildSortChip('Last Event', 'last_event'),
            _buildSortChip('Name', 'name'),
            _buildSortChip('Entries', 'entries'),
            _buildSortChip('Status', 'status'),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String value) {
    final isSelected = _sortBy == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            setState(() => _sortBy = value);
            _sortStats();
          }
        },
        selectedColor: Colors.tealAccent.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected
              ? Colors.tealAccent
              : (widget.isDarkMode ? Colors.white : Colors.black),
        ),
      ),
    );
  }

  Widget _buildStatCard(Map<String, dynamic> stat) {
    final workerName = stat['workers']?['name'] ?? 'Unknown Worker';
    final entries = stat['entry_count'] ?? 0;
    final exits = stat['exit_count'] ?? 0;
    final lastEvent = stat['last_event_time'] != null
        ? TimeUtils.parseToLocal(stat['last_event_time'])
        : null;
    final isInside = entries > exits;

    // Check for active production
    final activeLog = stat['active_log'];
    final isWorking = activeLog != null;

    // Determine status and styling
    String statusText;
    Color statusColor;
    IconData statusIcon;
    Color cardColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;

    if (!isInside) {
      statusText = 'Outside Factory';
      statusColor = Colors.red;
      statusIcon = Icons.logout;
    } else if (isWorking) {
      final itemId = activeLog['item_id']?.toString();
      final machineId = activeLog['machine_id']?.toString();
      final item = (itemId != null ? _itemNames[itemId] : null) ?? 'Item';
      final machine =
          (machineId != null ? _machineNames[machineId] : null) ?? 'Machine';
      statusText = 'Working: $item @ $machine';
      statusColor = Colors.blue;
      statusIcon = Icons.engineering;
      cardColor = widget.isDarkMode
          ? Colors.blue.withValues(alpha: 0.05)
          : Colors.blue.withValues(alpha: 0.02);
    } else {
      statusText = 'Idle (Inside Factory)';
      statusColor = Colors.orange;
      statusIcon = Icons.timer_off;
      cardColor = widget.isDarkMode
          ? Colors.orange.withValues(alpha: 0.05)
          : Colors.orange.withValues(alpha: 0.02);
    }

    return InkWell(
      onTap: () {
        DateTime? initialDate;
        if (stat['date'] != null) {
          try {
            initialDate = DateTime.parse(stat['date']);
          } catch (_) {}
        }

        showDialog(
          context: context,
          builder: (context) => GateActivityDetailDialog(
            workerId: stat['worker_id'],
            workerName: workerName,
            organizationCode: widget.organizationCode,
            isDarkMode: widget.isDarkMode,
            initialDate: initialDate,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey[200]!,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.2),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workerName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: widget.isDarkMode
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lastEvent != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(lastEvent),
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.isDarkMode
                                ? Colors.white54
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Last Event',
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.isDarkMode
                                ? Colors.white30
                                : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat(
                    'Entries',
                    entries.toString(),
                    Icons.login,
                    Colors.green,
                  ),
                  _buildMiniStat(
                    'Exits',
                    exits.toString(),
                    Icons.logout,
                    Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
