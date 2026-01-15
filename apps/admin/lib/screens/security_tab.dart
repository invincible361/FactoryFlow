import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';

class SecurityTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const SecurityTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _employeeLogs = [];
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
    // Employee login logs (worker/supervisor)
    try {
      final resp = await _supabase
          .from('login_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('login_time', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _employeeLogs = List<Map<String, dynamic>>.from(resp);
        });
      }
    } catch (e) {
      // Gracefully handle missing table or schema mismatch without noisy logs
      final msg = e.toString();
      if (msg.contains('PGRST205') ||
          msg.contains('Not Found') ||
          msg.contains('Could not find the table')) {
        if (mounted) {
          setState(() {
            _employeeLogs = [];
          });
        }
      } else {
        debugPrint('Employee login logs fetch error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);
    const Color accentColor = Color(0xFFA9DFD8);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: accentColor),
      );
    }

    if (_missingTable) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.security_update_warning_outlined,
                      size: 48, color: textColor.withValues(alpha: 0.2)),
                ),
                const SizedBox(height: 24),
                Text(
                  'Security logs unavailable',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Make sure the "owner_logs" table exists in Supabase.',
                  style: TextStyle(color: subTextColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _fetchLogs,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('RETRY'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: widget.isDarkMode
                        ? const Color(0xFF21222D)
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_logs.isEmpty && _employeeLogs.isEmpty) {
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
                child: Icon(Icons.security_outlined,
                    size: 48, color: textColor.withValues(alpha: 0.2)),
              ),
              const SizedBox(height: 24),
              Text(
                'No security logs found',
                style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Login history will appear here once users sign in.',
                style: TextStyle(color: subTextColor),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _fetchLogs,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('REFRESH'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: widget.isDarkMode
                      ? const Color(0xFF21222D)
                      : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchLogs,
      color: accentColor,
      backgroundColor: cardBg,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildSectionHeader(
              'OWNER / ADMIN LOGINS', Icons.admin_panel_settings, accentColor),
          if (_logs.isEmpty)
            _buildEmptySection(
                'No owner logins recorded.', subTextColor, borderColor)
          else
            ..._logs.map((log) {
              final timeStr = log['login_time'];
              final time = TimeUtils.parseToLocal(timeStr);
              final device = log['device_name'] ?? 'Unknown Device';
              final os = log['os_version'] ?? 'Unknown OS';
              return _buildLogCard(
                icon: Icons.security,
                iconColor: Colors.blueAccent,
                title: 'Admin Session',
                subtitle: 'Device: $device • OS: $os',
                details: '',
                time: DateFormat('dd MMM yyyy, hh:mm a').format(time),
                cardBg: cardBg,
                textColor: textColor,
                subTextColor: subTextColor,
                borderColor: borderColor,
              );
            }),
          const SizedBox(height: 24),
          _buildSectionHeader(
              'EMPLOYEE LOGINS', Icons.people_outline, accentColor),
          if (_employeeLogs.isEmpty)
            _buildEmptySection(
                'No employee logins recorded.', subTextColor, borderColor)
          else
            ..._employeeLogs.map((log) {
              final timeStr = log['login_time'];
              final time = TimeUtils.parseToLocal(timeStr);
              final role = (log['role'] ?? 'worker').toString().toUpperCase();
              final workerId = (log['worker_id'] ?? 'Unknown').toString();
              final device = (log['device_name'] ?? 'Unknown').toString();
              final os = (log['os_version'] ?? 'Unknown').toString();
              final isSupervisor = role.contains('SUPERVISOR');

              return _buildLogCard(
                icon: isSupervisor ? Icons.verified_user : Icons.badge,
                iconColor:
                    isSupervisor ? Colors.greenAccent : Colors.orangeAccent,
                title: '$role ($workerId)',
                subtitle: 'Device: $device • OS: $os',
                details: '',
                time: DateFormat('dd MMM yyyy, hh:mm a').format(time),
                cardBg: cardBg,
                textColor: textColor,
                subTextColor: subTextColor,
                borderColor: borderColor,
              );
            }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySection(
      String message, Color subTextColor, Color borderColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: subTextColor.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
              color: subTextColor.withValues(alpha: 0.6), fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildLogCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String details,
    required String time,
    required Color cardBg,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              time,
              style: TextStyle(
                  color: subTextColor.withValues(alpha: 0.6), fontSize: 11),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.7), fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              details,
              style: TextStyle(
                  color: subTextColor.withValues(alpha: 0.8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsDialog extends StatefulWidget {
  final String organizationCode;
  final VoidCallback onRead;

  const NotificationsDialog({
    super.key,
    required this.organizationCode,
    required this.onRead,
  });

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    try {
      final response = await _supabase
          .from('notifications')
          .select('*')
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (e.toString().contains('PGRST205')) {
        debugPrint('Notifications table not found, skipping fetch');
      } else {
        debugPrint('Error fetching notifications: $e');
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await _supabase.from('notifications').update({'read': true}).eq('id', id);
      _fetchNotifications();
      widget.onRead();
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _supabase
          .from('notifications')
          .update({'read': true})
          .eq('organization_code', widget.organizationCode)
          .eq('read', false);
      _fetchNotifications();
      widget.onRead();
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Recent Alerts'),
          if (_notifications.any((n) => n['read'] == false))
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? const Center(child: Text('No recent alerts'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _notifications.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      final isRead = n['read'] == true;
                      final createdAt = DateTime.parse(n['created_at']);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: n['type'] == 'work_abandonment'
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            n['type'] == 'work_abandonment'
                                ? Icons.exit_to_app
                                : Icons.login,
                            color: n['type'] == 'work_abandonment'
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                        title: Text(
                          n['title'],
                          style: TextStyle(
                            fontWeight:
                                isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n['body']),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMM d, h:mm a')
                                  .format(createdAt.toLocal()),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                        trailing: !isRead
                            ? IconButton(
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: () => _markAsRead(n['id']),
                              )
                            : null,
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
    );
  }
}
