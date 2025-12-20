import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/worker.dart';
import 'production_entry_screen.dart';
import 'admin_dashboard_screen.dart';
import '../services/location_service.dart';
import 'dart:io' show Platform; // Only show Platform for non-web logic

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _orgCodeController = TextEditingController();
  final LocationService _locationService = LocationService();
  bool _isLoading = false;
  final _regOrgCodeController = TextEditingController();
  final _regOrgNameController = TextEditingController();
  final _regFactoryNameController = TextEditingController();
  final _regAddressController = TextEditingController();
  final _regLatController = TextEditingController();
  final _regLngController = TextEditingController();
  final _regRadiusController = TextEditingController(text: '500');
  final _regOwnerUserController = TextEditingController();
  final _regOwnerPassController = TextEditingController();

  Future<void> _recordOwnerLogin() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceName = 'Unknown Device';
    String osVersion = 'Unknown OS';

    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        deviceName = '${webInfo.browserName.name} on ${webInfo.platform}';
        osVersion = webInfo.userAgent ?? 'Unknown Web UserAgent';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = '${iosInfo.name} ${iosInfo.systemName}';
        osVersion = iosInfo.systemVersion;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceName = macInfo.model;
        osVersion = 'macOS ${macInfo.osRelease}';
      } else if (Platform.isWindows) {
        final winInfo = await deviceInfo.windowsInfo;
        deviceName = winInfo.computerName;
        osVersion = 'Windows';
      }

      await Supabase.instance.client.from('owner_logs').insert({
        'login_time': DateTime.now().toIso8601String(),
        'device_name': deviceName,
        'os_version': osVersion,
      });
    } catch (e) {
      debugPrint('Error logging owner login: $e');
    }
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final username = _usernameController.text;
        final password = _passwordController.text;
        final orgCode = _orgCodeController.text;

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
          await _recordOwnerLogin();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AdminDashboardScreen(organizationCode: orgCode),
            ),
          );
          return;
        }

        // 2. Worker Login Checks
        // Check location first
        final position = await _locationService.getCurrentLocation();
        final isInside = _locationService.isInside(
          position,
          orgLat,
          orgLng,
          orgRadius,
        );

        if (!mounted) return;

        if (!isInside) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Login denied: You are not at the factory location.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Simulate network delay for login
        // await Future.delayed(const Duration(seconds: 1)); // Not needed with real DB
        if (!mounted) return;

        final response = await Supabase.instance.client
            .from('workers')
            .select()
            .eq('username', username)
            .eq('password', password)
            .eq('organization_code', orgCode)
            .maybeSingle();

        if (response == null) {
          throw StateError('Invalid username or password');
        }

        final worker = Worker.fromJson(response);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ProductionEntryScreen(worker: worker),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        String errorMessage = 'An error occurred';
        if (e is StateError) {
          errorMessage = 'Invalid username or password';
        } else {
          errorMessage = e.toString();
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adinath Automotive Pvt Ltd')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/logo.png',
                height: 120,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.factory,
                    size: 80,
                    color: Colors.blue,
                  );
                },
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _orgCodeController,
                decoration: const InputDecoration(
                  labelText: 'Organization Code',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter organization code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(onPressed: _login, child: const Text('Login')),
              const SizedBox(height: 16),
              const Text('Hint: worker1 / password1'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _showRegisterDialog,
                child: const Text('Register Factory'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRegisterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Register Factory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _regOrgCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Organization Code',
                  ),
                ),
                TextField(
                  controller: _regOrgNameController,
                  decoration: const InputDecoration(
                    labelText: 'Organization Name',
                  ),
                ),
                TextField(
                  controller: _regFactoryNameController,
                  decoration: const InputDecoration(labelText: 'Factory Name'),
                ),
                TextField(
                  controller: _regAddressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: _regLatController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
                TextField(
                  controller: _regLngController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
                TextField(
                  controller: _regRadiusController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Radius (meters)',
                  ),
                ),
                TextField(
                  controller: _regOwnerUserController,
                  decoration: const InputDecoration(
                    labelText: 'Owner Username',
                  ),
                ),
                TextField(
                  controller: _regOwnerPassController,
                  decoration: const InputDecoration(
                    labelText: 'Owner Password',
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _registerOrganization,
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _registerOrganization() async {
    try {
      final lat = double.tryParse(_regLatController.text) ?? 0.0;
      final lng = double.tryParse(_regLngController.text) ?? 0.0;
      final radius = double.tryParse(_regRadiusController.text) ?? 500.0;
      await Supabase.instance.client.from('organizations').insert({
        'organization_code': _regOrgCodeController.text,
        'organization_name': _regOrgNameController.text,
        'factory_name': _regFactoryNameController.text,
        'address': _regAddressController.text,
        'latitude': lat,
        'longitude': lng,
        'radius_meters': radius,
        'owner_username': _regOwnerUserController.text,
        'owner_password': _regOwnerPassController.text,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Factory registered')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
