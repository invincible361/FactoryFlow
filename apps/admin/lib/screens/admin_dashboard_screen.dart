import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'dart:async';
import 'help_screen.dart';
import 'comparison_tab.dart';
import 'reports_tab.dart';
import 'attendance_tab.dart';
import 'visualisation_tab.dart';
import 'employees_tab.dart';
import 'supervisors_tab.dart';
import 'machines_tab.dart';
import 'items_tab.dart';
import 'operations_tab.dart';
import 'shifts_tab.dart';
import 'profile_tab.dart';
import 'security_tab.dart';

// Removed local AdminHomeDrawer import as we now use core AppSidebar

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
  int _unreadNotifications = 0;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 14, vsync: this);
    _fetchOrganization();
    _fetchUnreadCount();
    _setupNotificationListener();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('organization_code', widget.organizationCode)
          .eq('read', false);

      if (mounted) {
        setState(() {
          _unreadNotifications = (response as List).length;
        });
      }
    } catch (e) {
      if (e.toString().contains('PGRST205')) {
        debugPrint('Notifications table not found, skipping unread count');
      } else {
        debugPrint('Error fetching unread count: $e');
      }
    }
  }

  void _setupNotificationListener() {
    _supabase
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            _fetchUnreadCount();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _supabase.channel('public:notifications').unsubscribe();
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
    final themeController = ThemeController.of(context);
    final isDarkMode = themeController?.isDarkMode ?? false;

    final backgroundColor = AppColors.getBackground(isDarkMode);
    final cardColor = AppColors.getCard(isDarkMode);
    final accentColor = AppColors.getAccent(isDarkMode);
    final textColor = AppColors.getText(isDarkMode);
    final secondaryTextColor = AppColors.getSecondaryText(isDarkMode);

    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: AppSidebar(
        organizationCode: widget.organizationCode,
        userName: _ownerUsername ?? 'Admin',
        organizationName: _factoryName ?? 'Factory Admin',
        profileImageUrl: _logoUrl,
        isDarkMode: isDarkMode,
        currentThemeMode: themeController?.themeMode ?? AppThemeMode.auto,
        onThemeModeChanged: (mode) => themeController?.onThemeModeChanged(mode),
        onLogout: () {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        },
        additionalItems: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.analytics_outlined, color: accentColor),
              title: Text(
                'Analytics',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconColor: accentColor,
              collapsedIconColor: secondaryTextColor,
              children: [
                ListTile(
                  leading: Icon(Icons.bar_chart_rounded, color: accentColor),
                  title: Text('Reports', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(0);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.compare_arrows_rounded, color: accentColor),
                  title: Text('Comparison', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(1);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.show_chart_rounded, color: accentColor),
                  title:
                      Text('Visualisation', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(2);
                  },
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.route_outlined, color: accentColor),
              title: Text(
                'Activity',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconColor: accentColor,
              collapsedIconColor: secondaryTextColor,
              children: [
                ListTile(
                  leading: Icon(Icons.security_rounded, color: accentColor),
                  title:
                      Text('Gate Activity', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(3);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.location_on_outlined, color: accentColor),
                  title: Text('Work Abandonment',
                      style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(4);
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.fact_check_outlined, color: accentColor),
                  title:
                      Text('Attendance', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(7);
                  },
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.settings_suggest_outlined, color: accentColor),
              title: Text(
                'Management',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconColor: accentColor,
              collapsedIconColor: secondaryTextColor,
              children: [
                ListTile(
                  leading: Icon(Icons.people_outline, color: accentColor),
                  title:
                      Text('Employees', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(5);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.supervisor_account_outlined, color: accentColor),
                  title:
                      Text('Supervisors', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(6);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.precision_manufacturing, color: accentColor),
                  title:
                      Text('Machines', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(8);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.category_outlined, color: accentColor),
                  title: Text('Items', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(9);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.build_circle_outlined, color: accentColor),
                  title:
                      Text('Operations', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(10);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.schedule_rounded, color: accentColor),
                  title: Text('Shifts', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(11);
                  },
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.person_outline, color: accentColor),
              title: Text(
                'Account',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconColor: accentColor,
              collapsedIconColor: secondaryTextColor,
              children: [
                ListTile(
                  leading: Icon(Icons.account_circle_outlined, color: accentColor),
                  title: Text('Profile', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(12);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.security_outlined, color: accentColor),
                  title: Text('Security', style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(13);
                  },
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.help_outline,
              color: accentColor,
            ),
            title: Text(
              'How to Use',
              style: TextStyle(
                color: textColor,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HelpScreen(isDarkMode: isDarkMode),
                ),
              );
            },
          ),
        ],
      ),
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
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
                          Icon(Icons.factory, size: 28, color: accentColor),
                    ),
                  )
                else
                  Image.asset(
                    'assets/images/logo.png',
                    height: 28,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.factory, size: 28, color: accentColor),
                  ),
                const SizedBox(width: 10),
                Text(
                  'Admin App',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
            if (_ownerUsername != null && _factoryName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Welcome, ${_ownerUsername!} — ${_factoryName!}',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: textColor),
                tooltip: 'Notifications',
                onPressed: () => _showNotificationsDialog(),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_unreadNotifications',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: textColor),
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
          indicatorColor: accentColor,
          indicatorWeight: 3,
          labelColor: accentColor,
          unselectedLabelColor: secondaryTextColor,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Reports'),
            Tab(text: 'Comparison'),
            Tab(text: 'Visualisation'),
            Tab(text: 'Gate Activity'),
            Tab(text: 'Work Abandonment'),
            Tab(text: 'Employees'),
            Tab(text: 'Supervisors'),
            Tab(text: 'Attendance'),
            Tab(text: 'Machines'),
            Tab(text: 'Items'),
            Tab(text: 'Operations'),
            Tab(text: 'Shifts'),
            Tab(text: 'Profile'),
            Tab(text: 'Security'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ReportsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          ComparisonTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          VisualisationTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          GateActivityTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          WorkAbandonmentTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          EmployeesTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          SupervisorsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          AttendanceTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          MachinesTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          ItemsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          OperationsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          ShiftsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
          ProfileTab(
            organizationCode: widget.organizationCode,
            onProfileUpdated: _fetchOrganization,
            isDarkMode: isDarkMode,
          ),
          SecurityTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
        ],
      ),
    );
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => NotificationsDialog(
        organizationCode: widget.organizationCode,
        onRead: _fetchUnreadCount,
      ),
    );
  }
}
