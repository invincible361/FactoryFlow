import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../utils/time_utils.dart';

class WorkAbandonmentTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const WorkAbandonmentTab({
    super.key,
    required this.organizationCode,
    required this.isDarkMode,
  });

  @override
  State<WorkAbandonmentTab> createState() => _WorkAbandonmentTabState();
}

class _WorkAbandonmentTabState extends State<WorkAbandonmentTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  RealtimeChannel? _realtimeChannel;
  Timer? _liveUpdateTimer;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
    _setupRealtime();
    // Refresh UI every minute to update "so far" durations
    _liveUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  void _setupRealtime() {
    _realtimeChannel = _supabase
        .channel('work_abandonment_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'production_outofbounds',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            _fetchEvents();
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
            _fetchEvents();
          },
        )
        .subscribe();
  }

  String _calculateLiveDuration(DateTime exitTime) {
    final diff = TimeUtils.nowUtc().difference(exitTime.toUtc());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes % 60}m (so far)';
    }
    return '${diff.inMinutes} mins (so far)';
  }

  Future<void> _fetchEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Fetch with joined worker details
      final response = await _supabase
          .from('production_outofbounds')
          .select('*, workers:worker_id(name, role)')
          .eq('organization_code', widget.organizationCode)
          .order('exit_time', ascending: false);

      if (mounted) {
        final List<Map<String, dynamic>> allEvents =
            List<Map<String, dynamic>>.from(response);

        // Filter and ensure worker_name is present
        final processedEvents = allEvents
            .where((event) {
              final worker = event['workers'] as Map<String, dynamic>?;
              // Show if it's a worker or if we can't determine role but have a name
              if (worker != null) {
                return worker['role'] == 'worker';
              }
              // Fallback: if we have worker_name in the record itself, keep it
              return event['worker_name'] != null;
            })
            .map((event) {
              // Ensure worker_name is populated from join if possible
              if (event['worker_name'] == null ||
                  event['worker_name'].toString().isEmpty) {
                final worker = event['workers'] as Map<String, dynamic>?;
                if (worker != null) {
                  event['worker_name'] = worker['name'];
                }
              }
              return event;
            })
            .toList();

        setState(() {
          _events = processedEvents;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching abandonment events: $e');
      // Simple fallback
      try {
        final simpleResponse = await _supabase
            .from('production_outofbounds')
            .select('*')
            .eq('organization_code', widget.organizationCode)
            .order('exit_time', ascending: false);

        if (mounted) {
          setState(() {
            _events = List<Map<String, dynamic>>.from(simpleResponse);
            _isLoading = false;
          });
        }
      } catch (err) {
        debugPrint('Simple fetch error: $err');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.getAccent(widget.isDarkMode);
    final Color cardBg = widget.isDarkMode
        ? const Color(0xFF21222D)
        : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: accentColor));
    }

    if (_events.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_off_outlined,
                  size: 48,
                  color: textColor.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No work abandonment alerts recorded',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No active abandonment alerts.',
                style: TextStyle(color: subTextColor),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _fetchEvents,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('REFRESH'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: widget.isDarkMode
                      ? const Color(0xFF21222D)
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEvents,
      color: accentColor,
      backgroundColor: cardBg,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final workerName =
              event['worker_name'] ??
              (event['workers'] is Map
                  ? (event['workers'] as Map)['name']
                  : event['worker_id'] ?? 'Unknown Worker');

          final exitTimeStr = event['exit_time'] ?? event['created_at'];
          final exitTime = exitTimeStr != null
              ? TimeUtils.parseToLocal(exitTimeStr.toString())
              : TimeUtils.nowIst();

          final entryTimeStr = event['entry_time'] as String?;
          final entryTime = entryTimeStr != null
              ? TimeUtils.parseToLocal(entryTimeStr)
              : null;
          final duration =
              event['duration_minutes'] ?? _calculateLiveDuration(exitTime);
          final isStillOut = entryTime == null;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      color: isStillOut ? Colors.redAccent : Colors.blueAccent,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color:
                                    (isStillOut
                                            ? Colors.redAccent
                                            : Colors.blueAccent)
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isStillOut
                                    ? Icons.exit_to_app_rounded
                                    : Icons.assignment_turned_in_rounded,
                                color: isStillOut
                                    ? Colors.redAccent
                                    : Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    workerName,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.logout_rounded,
                                            size: 14,
                                            color: subTextColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Time Out: ${DateFormat('dd MMM yyyy, hh:mm a').format(exitTime)}',
                                            style: TextStyle(
                                              color: subTextColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!isStillOut) ...[
                                        Text(
                                          '•',
                                          style: TextStyle(
                                            color: textColor.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.login_rounded,
                                              size: 14,
                                              color: subTextColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Time In: ${DateFormat('dd MMM yyyy, hh:mm a').format(entryTime)}',
                                              style: TextStyle(
                                                color: subTextColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 14,
                                        color: subTextColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Location: ${event['exit_latitude']?.toStringAsFixed(4) ?? 'N/A'}, ${event['exit_longitude']?.toStringAsFixed(4) ?? 'N/A'}',
                                          style: TextStyle(
                                            color: subTextColor,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!isStillOut &&
                                      event['entry_latitude'] != null &&
                                      event['entry_longitude'] != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 14,
                                          color: subTextColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Return: ${event['entry_latitude']?.toStringAsFixed(4)}, ${event['entry_longitude']?.toStringAsFixed(4)}',
                                            style: TextStyle(
                                              color: subTextColor,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (isStillOut
                                                  ? Colors.redAccent
                                                  : Colors.blueAccent)
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isStillOut
                                          ? 'STILL OUT ($duration)'
                                          : 'TOTAL DURATION: $duration',
                                      style: TextStyle(
                                        color: isStillOut
                                            ? Colors.redAccent
                                            : Colors.blueAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.map_outlined,
                                color: accentColor,
                              ),
                              tooltip: 'View on Google Maps',
                              onPressed: () async {
                                final lat =
                                    event['exit_latitude'] ?? event['latitude'];
                                final lng =
                                    event['exit_longitude'] ??
                                    event['longitude'];
                                if (lat != null && lng != null) {
                                  final url =
                                      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                                  if (await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(
                                      Uri.parse(url),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } else {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Could not open map'),
                                        ),
                                      );
                                    }
                                  }
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No location coordinates recorded',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
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
}
