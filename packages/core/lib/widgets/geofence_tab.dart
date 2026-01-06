import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class GeofenceTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;

  const GeofenceTab({
    super.key,
    required this.organizationCode,
    required this.isDarkMode,
  });

  @override
  State<GeofenceTab> createState() => _GeofenceTabState();
}

class _GeofenceTabState extends State<GeofenceTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _geofenceStats = [];
  bool _isLoading = true;
  String _sortBy = 'last_event'; // 'name', 'entries', 'status'

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchGeofenceStats();
    // Refresh stats every 30 seconds for real-time visibility
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchGeofenceStats();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _sortStats() {
    setState(() {
      if (_sortBy == 'name') {
        _geofenceStats.sort((a, b) {
          final nameA = a['workers']?['name']?.toString().toLowerCase() ?? '';
          final nameB = b['workers']?['name']?.toString().toLowerCase() ?? '';
          return nameA.compareTo(nameB);
        });
      } else if (_sortBy == 'entries') {
        _geofenceStats.sort((a, b) {
          final countA = (a['entry_count'] ?? 0) as int;
          final countB = (b['entry_count'] ?? 0) as int;
          return countB.compareTo(countA);
        });
      } else if (_sortBy == 'status') {
        _geofenceStats.sort((a, b) {
          // Status logic: Inside first
          final aIsInside = (a['entry_count'] ?? 0) > (a['exit_count'] ?? 0);
          final bIsInside = (b['entry_count'] ?? 0) > (b['exit_count'] ?? 0);
          if (aIsInside == bIsInside) return 0;
          return aIsInside ? -1 : 1;
        });
      } else {
        // last_event (default)
        _geofenceStats.sort((a, b) {
          final timeA = a['last_event_time']?.toString() ?? '';
          final timeB = b['last_event_time']?.toString() ?? '';
          return timeB.compareTo(timeA);
        });
      }
    });
  }

  Future<void> _fetchGeofenceStats() async {
    try {
      // Use UTC date for the query to match DB trigger
      final nowUtc = DateTime.now().toUtc();
      final dateStr = DateFormat('yyyy-MM-dd').format(nowUtc);
      final yesterdayStr = DateFormat(
        'yyyy-MM-dd',
      ).format(nowUtc.subtract(const Duration(days: 1)));

      // Try with join first
      try {
        final response = await _supabase
            .from('daily_geofence_summaries')
            .select('*, workers:worker_id(name)')
            .eq('organization_code', widget.organizationCode)
            .or('date.eq.$dateStr,date.eq.$yesterdayStr')
            .order('last_event_time', ascending: false);

        if (mounted) {
          final stats = List<Map<String, dynamic>>.from(response);
          if (stats.isNotEmpty) {
            setState(() {
              _geofenceStats = stats;
              _isLoading = false;
            });
            _sortStats();
            return;
          }
        }
      } catch (joinError) {
        debugPrint('Geofence join fetch error: $joinError');
      }

      // FALLBACK: If summary is empty or failed, fetch latest from raw events
      final rawEvents = await _supabase
          .from('worker_boundary_events')
          .select('*, workers:worker_id(name)')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', yesterdayStr)
          .order('created_at', ascending: false);

      if (mounted) {
        final List<Map<String, dynamic>> events =
            List<Map<String, dynamic>>.from(rawEvents);

        // Group by worker_id and get latest
        final Map<String, Map<String, dynamic>> latestByWorker = {};
        for (final event in events) {
          final workerId = event['worker_id'];
          if (!latestByWorker.containsKey(workerId)) {
            // Map raw event to summary-like format
            final isEntry = event['type'] == 'entry';
            latestByWorker[workerId] = {
              'worker_id': workerId,
              'organization_code': event['organization_code'],
              'date': event['created_at'].substring(0, 10),
              'entry_count': isEntry ? 1 : 0,
              'exit_count': isEntry ? 0 : 1,
              'last_event_time': event['created_at'],
              'workers': event['workers'],
            };
          } else {
            // Update counts for the day
            if (event['type'] == 'entry') {
              latestByWorker[workerId]!['entry_count'] =
                  (latestByWorker[workerId]!['entry_count'] ?? 0) + 1;
            } else if (event['type'] == 'exit') {
              latestByWorker[workerId]!['exit_count'] =
                  (latestByWorker[workerId]!['exit_count'] ?? 0) + 1;
            }
          }
        }

        setState(() {
          _geofenceStats = latestByWorker.values.toList();
          _isLoading = false;
        });
        _sortStats();
      }
    } catch (e) {
      debugPrint('Error fetching geofence stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showDetailedLogs(String workerId, String workerName) async {
    final now = DateTime.now();
    final startOfYesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1)).toUtc();

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDarkMode
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder(
          future: _supabase
              .from('worker_boundary_events')
              .select()
              .eq('worker_id', workerId)
              .eq('organization_code', widget.organizationCode)
              .gte('created_at', startOfYesterday.toIso8601String())
              .order('created_at', ascending: false),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final logs = List<Map<String, dynamic>>.from(snapshot.data ?? []);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Cross-Check: $workerName',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: widget.isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: logs.isEmpty
                      ? const Center(child: Text('No raw logs found'))
                      : ListView.builder(
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            final time = DateTime.parse(
                              log['created_at'],
                            ).toLocal();
                            final type = log['type'].toString().toUpperCase();
                            final isEntry = type == 'ENTRY';
                            final isViolation =
                                log['remarks'] == 'OUT_OF_BOUNDS_PRODUCTION';

                            return ListTile(
                              leading: Icon(
                                isEntry
                                    ? Icons.login_rounded
                                    : Icons.logout_rounded,
                                color: isViolation
                                    ? Colors.red
                                    : (isEntry ? Colors.green : Colors.orange),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    type,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: widget.isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  if (isViolation) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.red.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'PRODUCTION VIOLATION',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                DateFormat('dd MMM yyyy, hh:mm a').format(time),
                                style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                              trailing: Text(
                                isViolation ? 'Violation Log' : 'Raw Log',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: isViolation
                                      ? Colors.red.shade300
                                      : (widget.isDarkMode
                                            ? Colors.white38
                                            : Colors.black38),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final subTextColor = widget.isDarkMode ? Colors.white70 : Colors.black54;

    return RefreshIndicator(
      onRefresh: _fetchGeofenceStats,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Sort by:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: subTextColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode
                        ? Colors.grey[850]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      icon: const Icon(Icons.sort, size: 16),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _sortBy = newValue);
                          _sortStats();
                        }
                      },
                      items: <String>['last_event', 'name', 'entries', 'status']
                          .map<DropdownMenuItem<String>>((String value) {
                            String label = '';
                            switch (value) {
                              case 'last_event':
                                label = 'Recent';
                                break;
                              case 'name':
                                label = 'Name';
                                break;
                              case 'entries':
                                label = 'Entries';
                                break;
                              case 'status':
                                label = 'Inside/Outside';
                                break;
                            }
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(label),
                            );
                          })
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _geofenceStats.isEmpty
                ? Center(
                    child: Text(
                      'No geofence activity today',
                      style: TextStyle(
                        color: subTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _geofenceStats.length,
                    itemBuilder: (context, index) {
                      final stat = _geofenceStats[index];
                      final firstEntryStr = stat['first_entry_time'];
                      final firstEntry = firstEntryStr != null
                          ? DateTime.parse(firstEntryStr).toLocal()
                          : null;
                      final workerName =
                          stat['workers']?['name'] ?? 'Unknown Worker';
                      final isInside =
                          (stat['entry_count'] ?? 0) >
                          (stat['exit_count'] ?? 0);

                      return GestureDetector(
                        onTap: () =>
                            _showDetailedLogs(stat['worker_id'], workerName),
                        child: Card(
                          color: cardBg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: widget.isDarkMode
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isInside
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          workerName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFA9DFD8,
                                        ).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        stat['worker_id'],
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFA9DFD8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statItem(
                                        label: 'First Entry',
                                        value: firstEntry != null
                                            ? DateFormat(
                                                'hh:mm a',
                                              ).format(firstEntry)
                                            : 'N/A',
                                        icon: Icons.login_rounded,
                                        color: Colors.green,
                                        isDarkMode: widget.isDarkMode,
                                      ),
                                    ),
                                    Expanded(
                                      child: _statItem(
                                        label: 'Entries',
                                        value: stat['entry_count'].toString(),
                                        icon: Icons.input_rounded,
                                        color: Colors.blue,
                                        isDarkMode: widget.isDarkMode,
                                      ),
                                    ),
                                    Expanded(
                                      child: _statItem(
                                        label: 'Exits',
                                        value: stat['exit_count'].toString(),
                                        icon: Icons.logout_rounded,
                                        color: Colors.orange,
                                        isDarkMode: widget.isDarkMode,
                                      ),
                                    ),
                                    Expanded(
                                      child: _statItem(
                                        label: 'Status',
                                        value: isInside ? 'INSIDE' : 'OUTSIDE',
                                        icon: isInside
                                            ? Icons.home_rounded
                                            : Icons.directions_run_rounded,
                                        color: isInside
                                            ? Colors.green
                                            : Colors.red,
                                        isDarkMode: widget.isDarkMode,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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

  Widget _statItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDarkMode,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
