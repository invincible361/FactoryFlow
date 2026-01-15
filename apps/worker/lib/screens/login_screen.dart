import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:factoryflow_core/services/version_service.dart';
import 'package:factoryflow_core/ui_components/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../ui_components/navigation_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _locationService = LocationService();
  bool _isLoading = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _fetchAppVersion();
    // Request notification permissions on startup
    NotificationService.requestPermissions();
    // Check for updates on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    final updateInfo = await VersionService.checkForUpdate('worker');
    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: !updateInfo['isForceUpdate'],
        builder: (context) => UpdateDialog(
          latestVersion: updateInfo['latestVersion'],
          apkUrl: updateInfo['apkUrl'],
          isForceUpdate: updateInfo['isForceUpdate'],
          releaseNotes: updateInfo['releaseNotes'],
          headers: updateInfo['headers'],
        ),
      );
    }
  }

  Future<void> _fetchAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${info.version}';
      });
    }
  }

  void _login(String username, String password, String orgCode) async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (username.isEmpty || password.isEmpty || orgCode.isEmpty) {
        throw StateError('All fields are required');
      }

      // 1. Owner Login (Admin for organization)
      final orgResp = await Supabase.instance.client
          .from('organizations')
          .select()
          .eq('organization_code', orgCode)
          .maybeSingle();
      if (orgResp == null) {
        throw StateError('Invalid organization code');
      }
      final ownerUser = orgResp['owner_username']?.toString() ?? '';
      final ownerPass = orgResp['owner_password']?.toString() ?? '';
      final orgLat = (orgResp['latitude'] ?? 0.0) * 1.0;
      final orgLng = (orgResp['longitude'] ?? 0.0) * 1.0;
      final orgRadius = (orgResp['radius_meters'] ?? 500.0) * 1.0;

      if (username == ownerUser && password == ownerPass) {
        throw StateError(
          'This app is for Workers only. Admins should use the Admin app.',
        );
      }

      // 2. Employee Login Checks
      // Check location first
      final Position position;
      try {
        position = await _locationService.getCurrentLocation(
          requestAlways: true,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location error: $e. Please enable location services.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      bool isInside = _locationService.isInside(
        position,
        orgLat,
        orgLng,
        orgRadius,
        bufferMultiplier: 1.0,
      );

      if (!isInside) {
        final double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          orgLat,
          orgLng,
        );
        throw StateError(
          'You are too far from the factory (${distance.toInt()}m). Required: ${orgRadius.toInt()}m.',
        );
      }

      // 3. Authenticate Employee
      final empResp = await Supabase.instance.client
          .from('workers')
          .select()
          .eq('organization_code', orgCode)
          .eq('username', username)
          .eq('password', password)
          .maybeSingle();

      if (empResp == null) {
        throw StateError('Invalid worker credentials');
      }

      // Check role case-insensitively
      final String role = (empResp['role'] ?? '').toString().toLowerCase();
      if (role != 'worker') {
        throw StateError(
          'This account is not registered as a Worker (Found: $role)',
        );
      }

      final employee = Employee.fromJson(empResp);

      // Update FCM token for the worker
      try {
        final fcmToken = await NotificationService.getFCMToken();
        if (fcmToken != null) {
          await SupabaseService.updateWorkerFCMToken(employee.id, fcmToken);
        }
      } catch (e) {
        debugPrint('Error updating FCM token during login: $e');
      }

      // Force an entry log on login if inside
      if (isInside) {
        try {
          // 1. Sync to gate_events (for attendance and last_boundary_state)
          await Supabase.instance.client.from('gate_events').insert({
            'worker_id': employee.id,
            'organization_code': employee.organizationCode,
            'event_type': 'entry',
            'latitude': position.latitude,
            'longitude': position.longitude,
            // 'timestamp' omitted to use server-side now()
          });

          // 2. Sync to worker_boundary_events (legacy compatibility)
          await Supabase.instance.client.from('worker_boundary_events').insert({
            'id': const Uuid().v4(),
            'worker_id': employee.id,
            'organization_code': employee.organizationCode,
            'type': 'entry',
            'latitude': position.latitude,
            'longitude': position.longitude,
            'is_inside': true,
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_inside', true);
        } catch (e) {
          debugPrint('Error logging initial entry: $e');
        }
      }

      // Cache organization location details for offline/background use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('factory_lat', orgLat);
      await prefs.setDouble('factory_lng', orgLng);
      await prefs.setDouble('factory_radius', orgRadius);
      await prefs.setString('org_code', orgCode);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => NavigationHomeScreen(employee: employee),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is StateError ? e.message : e.toString()),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.of(context);
    final isDarkMode = themeController?.isDarkMode ?? false;

    return ModernLoginScreen(
      appTitle: 'FactoryFlow',
      role: 'Worker',
      version: _appVersion,
      isLoading: _isLoading,
      isDarkMode: isDarkMode,
      logoAsset: 'assets/images/logo.png',
      onLogin: (username, password, orgCode) {
        _login(username, password, orgCode);
      },
    );
  }
}
