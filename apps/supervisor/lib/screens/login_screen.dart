import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'supervisor_dashboard_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' as io;

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
  String _appVersion = '';
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _fetchAppVersion();
    // Check for updates on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context, 'supervisor');
    });
  }

  Future<void> _fetchAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${info.version}';
      });
    }
  }

  Future<void> _recordOwnerLogin(String organizationCode) async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceName = 'Unknown Device';
    String osVersion = 'Unknown OS';

    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        deviceName = '${webInfo.browserName.name} on ${webInfo.platform}';
        osVersion = webInfo.userAgent ?? 'Unknown Web UserAgent';
      } else if (io.Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
      } else if (io.Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = '${iosInfo.name} ${iosInfo.systemName}';
        osVersion = iosInfo.systemVersion;
      } else if (io.Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceName = macInfo.model;
        osVersion = 'macOS ${macInfo.osRelease}';
      } else if (io.Platform.isWindows) {
        final winInfo = await deviceInfo.windowsInfo;
        deviceName = winInfo.computerName;
        osVersion = 'Windows';
      }

      final payload = {
        'login_time': DateTime.now().toIso8601String(),
        'device_name': deviceName,
        'os_version': osVersion,
        'organization_code': organizationCode,
      };
      try {
        await Supabase.instance.client.from('owner_logs').insert(payload);
      } catch (e) {
        if (e.toString().contains('PGRST204') ||
            e.toString().contains('column') ||
            e.toString().contains('missing')) {
          payload.remove('organization_code');
          await Supabase.instance.client.from('owner_logs').insert(payload);
        } else {
          rethrow;
        }
      }
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
        final username = _usernameController.text.trim();
        final password = _passwordController.text.trim();
        final orgCode = _orgCodeController.text.trim();

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
            'This app is for Supervisors only. Admins should use the Admin app.',
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

        final employee = Employee.fromJson(response);

        if (!mounted) return;

        // Restrict to supervisor role only
        if ((employee.role ?? 'worker') != 'supervisor') {
          throw StateError(
            'This app is for Supervisors only. Your role is ${employee.role}. Please use the correct app.',
          );
        }

        // Record login event
        try {
          final deviceInfo = DeviceInfoPlugin();
          String deviceName = 'Unknown Device';
          String osVersion = 'Unknown OS';
          if (kIsWeb) {
            final webInfo = await deviceInfo.webBrowserInfo;
            deviceName = '${webInfo.browserName.name} on ${webInfo.platform}';
            osVersion = webInfo.userAgent ?? 'Unknown Web UserAgent';
          } else if (io.Platform.isAndroid) {
            final androidInfo = await deviceInfo.androidInfo;
            deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
            osVersion = 'Android ${androidInfo.version.release}';
          } else if (io.Platform.isIOS) {
            final iosInfo = await deviceInfo.iosInfo;
            deviceName = '${iosInfo.name} ${iosInfo.systemName}';
            osVersion = iosInfo.systemVersion;
          }
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final payload = {
            'worker_id': employee.id,
            'role': employee.role ?? 'worker',
            'organization_code': orgCode,
            'device_name': deviceName,
            'os_version': osVersion,
            'login_time': nowIso,
          };
          await Supabase.instance.client.from('login_logs').insert(payload);
        } catch (e) {
          // Silently fail if table doesn't exist to avoid confusing the user
          if (e.toString().contains('PGRST205') ||
              e.toString().contains('login_logs')) {
            debugPrint('Login logging skipped: table login_logs not found');
          } else {
            debugPrint('Error recording login event: $e');
          }
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SupervisorDashboardScreen(
              organizationCode: orgCode,
              supervisorName: employee.name,
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        String errorMessage = 'An error occurred';
        if (e is StateError) {
          errorMessage = 'Invalid username or password';
        } else {
          errorMessage = e.toString();
          // Log detailed error for debugging
          debugPrint('Detailed Login Error: $e');

          if (errorMessage.contains('Load failed') ||
              errorMessage.contains('ClientException')) {
            errorMessage =
                'Connection failed. This usually means Supabase is blocked by an ad-blocker, firewall, or your network is down.\n\nDetails: $e';
          } else if (errorMessage.contains('PGRST204') ||
              errorMessage.contains('column')) {
            errorMessage =
                'Database schema mismatch. Please run the migration script.';
          } else if (errorMessage.contains('Location services are disabled')) {
            errorMessage =
                'Location services are disabled. Please enable them in your device settings to log in.';
          } else if (errorMessage.contains('Location permissions are denied')) {
            errorMessage =
                'Location permissions are required for workers to log in. Please grant permission.';
          } else if (errorMessage.contains('permanently denied')) {
            errorMessage =
                'Location permissions are permanently denied. Please enable them in App Settings.';
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            action: (errorMessage.contains('Location'))
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: () {
                      Geolocator.openLocationSettings();
                    },
                  )
                : null,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supervisor App')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: viewportConstraints.maxHeight > 0
                          ? viewportConstraints.maxHeight
                          : 0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          height:
                              MediaQuery.of(context).orientation ==
                                  Orientation.landscape
                              ? 80
                              : 120,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.factory,
                              size:
                                  MediaQuery.of(context).orientation ==
                                      Orientation.landscape
                                  ? 60
                                  : 80,
                              color: Colors.blue,
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _orgCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Organization Code',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter organization code';
                            }
                            // Only allow alphanumeric characters
                            if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
                              return 'Invalid characters in organization code';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                          ),
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
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        if (_appVersion.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            _appVersion,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Removed unused _showRegisterDialog
}
