import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import '../screens/production_entry_screen.dart';
import '../screens/help_screen.dart';
import '../screens/login_screen.dart';
import '../main.dart'; // Import to access _handleBackgroundLocation

// Background task identifiers
const String syncLocationTask = "syncLocationTask";
const String shiftEndReminderTask = "shiftEndReminderTask";
const String checkForUpdateTask = "checkForUpdateTask";

class NavigationHomeScreen extends StatefulWidget {
  final Employee employee;

  const NavigationHomeScreen({super.key, required this.employee});

  // Global access to location status for child screens
  static final ValueNotifier<bool?> isInsideNotifier = ValueNotifier<bool?>(
    null,
  );
  static final ValueNotifier<Position?> currentPositionNotifier =
      ValueNotifier<Position?>(null);
  static final ValueNotifier<String> locationStatusNotifier =
      ValueNotifier<String>('Checking location...');

  @override
  State<NavigationHomeScreen> createState() => _NavigationHomeScreenState();
}

class _NavigationHomeScreenState extends State<NavigationHomeScreen> {
  Widget? screenView;
  String _currentTitle = 'Home';
  Timer? _locationTimer;

  @override
  void initState() {
    screenView = ProductionEntryScreen(employee: widget.employee);
    super.initState();
    _initializeBackgroundTasks();
    _startLocationTimer();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  void _startLocationTimer() {
    // Check location immediately
    _performLocationCheck();

    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _performLocationCheck();
      }
    });
  }

  Future<void> _performLocationCheck() async {
    final result = await handleBackgroundLocation();
    final isInside = result['isInside'] as bool?;
    final position = result['position'] as Position?;

    if (mounted) {
      NavigationHomeScreen.isInsideNotifier.value = isInside;
      NavigationHomeScreen.currentPositionNotifier.value = position;

      if (isInside == null) {
        NavigationHomeScreen.locationStatusNotifier.value =
            'Location error or not set';
      } else {
        NavigationHomeScreen.locationStatusNotifier.value = isInside
            ? 'Inside Factory ✅'
            : 'Outside Factory ❌';
      }
    }
  }

  Future<void> _initializeBackgroundTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('worker_id', widget.employee.id);
    await prefs.setString(
      'worker_name',
      widget.employee.name,
    ); // Store name for background tasks
    await prefs.setString(
      'worker_role',
      widget.employee.role ?? 'worker',
    ); // Store role to filter abandonment checks
    if (widget.employee.organizationCode != null) {
      await prefs.setString('org_code', widget.employee.organizationCode!);

      // Also ensure we have the factory location cached if not already there
      // This helps with 24/7 tracking without constant API calls
      if (!prefs.containsKey('factory_lat')) {
        try {
          final org = await Supabase.instance.client
              .from('organizations')
              .select()
              .eq('organization_code', widget.employee.organizationCode!)
              .maybeSingle();
          if (org != null) {
            await prefs.setDouble(
              'factory_lat',
              (org['latitude'] ?? 0.0) * 1.0,
            );
            await prefs.setDouble(
              'factory_lng',
              (org['longitude'] ?? 0.0) * 1.0,
            );
            await prefs.setDouble(
              'factory_radius',
              (org['radius_meters'] ?? 500.0) * 1.0,
            );
            await prefs.setDouble(
              'geofence_radius',
              (org['radius_meters'] ?? 500.0) * 1.0,
            );
          }
        } catch (e) {
          debugPrint('Error caching factory location: $e');
        }
      }
    }
    // Initialize location status based on current position
    _performLocationCheck();

    // Workmanager periodic tasks are only supported on Android.
    if (!kIsWeb && Platform.isAndroid) {
      debugPrint('NavigationHome: Registering background tasks');
      await Workmanager().registerPeriodicTask(
        "1",
        syncLocationTask,
        frequency: const Duration(
          minutes: 15,
        ), // Android minimum for periodic tasks
        initialDelay: const Duration(seconds: 10),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      await Workmanager().registerPeriodicTask(
        "2",
        shiftEndReminderTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(networkType: NetworkType.connected),
      );

      await Workmanager().registerPeriodicTask(
        "3",
        checkForUpdateTask,
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 5),
        constraints: Constraints(networkType: NetworkType.connected),
      );
      debugPrint('NavigationHome: Background tasks registered');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.of(context);
    final isDarkMode = themeController?.isDarkMode ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentTitle,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
            fontWeight: isDarkMode ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      drawer: AppSidebar(
        userName: widget.employee.name,
        organizationCode: widget.employee.organizationCode ?? 'UNKNOWN',
        profileImageUrl: widget.employee.photoUrl,
        isDarkMode: isDarkMode,
        currentThemeMode: themeController?.themeMode ?? AppThemeMode.auto,
        onThemeModeChanged: (mode) => themeController?.onThemeModeChanged(mode),
        onLogout: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        },
        additionalItems: [
          AttendanceSidebarItem(
            workerId: widget.employee.id,
            organizationCode: widget.employee.organizationCode ?? 'UNKNOWN',
            isDarkMode: isDarkMode,
          ),
          _buildDrawerItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isDarkMode: isDarkMode,
            onTap: () {
              setState(() {
                screenView = ProductionEntryScreen(employee: widget.employee);
                _currentTitle = 'Home';
              });
              Navigator.pop(context);
            },
          ),
          _buildDrawerItem(
            icon: Icons.help_outline_rounded,
            label: 'Help',
            isDarkMode: isDarkMode,
            onTap: () {
              setState(() {
                screenView = HelpScreen();
                _currentTitle = 'Help';
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: screenView,
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return ListTile(
      leading: Icon(icon, color: isDarkMode ? Colors.white : Colors.black87),
      title: Text(
        label,
        style: TextStyle(
          color: isDarkMode ? Colors.white : Colors.black87,
          fontWeight: isDarkMode ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
    );
  }
}
