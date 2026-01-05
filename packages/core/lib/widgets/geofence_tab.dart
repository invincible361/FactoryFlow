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

  @override
  void initState() {
    super.initState();
    _fetchGeofenceStats();
  }

  Future<void> _fetchGeofenceStats() async {
    try {
      final now = DateTime.now();
      // Use local date for the query, but we'll also check if we need to adjust for UTC
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final yesterdayStr = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));

      // Try with join first
      try {
        final response = await _supabase
            .from('daily_geofence_summaries')
            .select('*, workers:worker_id(name)')
            .eq('organization_code', widget.organizationCode)
            .or('date.eq.$dateStr,date.eq.$yesterdayStr')
            .order('last_event_time', ascending: false);

        if (mounted) {
          setState(() {
            _geofenceStats = List<Map<String, dynamic>>.from(response);
            _isLoading = false;
          });
          return;
        }
      } catch (joinError) {
        debugPrint('Geofence join fetch error: $joinError');
        // Fallback to simple select
        final simpleResponse = await _supabase
            .from('daily_geofence_summaries')
            .select('*')
            .eq('organization_code', widget.organizationCode)
            .or('date.eq.$dateStr,date.eq.$yesterdayStr')
            .order('last_event_time', ascending: false);

        if (mounted) {
          setState(() {
            _geofenceStats = List<Map<String, dynamic>>.from(simpleResponse);
            _isLoading = false;
          });
        }
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
                                DateFormat('hh:mm:ss a').format(time),
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
                final workerName = stat['workers']?['name'] ?? 'Unknown Worker';

                return GestureDetector(
                  onTap: () => _showDetailedLogs(stat['worker_id'], workerName),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                workerName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
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
                                      ? DateFormat('hh:mm a').format(firstEntry)
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
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
