import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'supervisor_dashboard_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _fetchAppVersion();
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

      if (username == ownerUser && password == ownerPass) {
        throw StateError(
          'This app is for Supervisors only. Admins should use the Admin app.',
        );
      }

      // 2. Employee Login Checks
      // Skip location check for supervisors as per user request

      // 3. Authenticate Supervisor
      final empResp = await Supabase.instance.client
          .from('workers')
          .select()
          .eq('organization_code', orgCode)
          .eq('username', username)
          .eq('password', password)
          .maybeSingle();

      if (empResp == null) {
        throw StateError('Invalid supervisor credentials');
      }

      // Check role case-insensitively
      final String role = (empResp['role'] ?? '').toString().toLowerCase();
      if (role != 'supervisor') {
        throw StateError(
          'This account is not registered as a Supervisor (Found: $role)',
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SupervisorDashboardScreen(
            organizationCode: orgCode,
            supervisorName: empResp['name'] ?? username,
          ),
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
      role: 'Supervisor',
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
