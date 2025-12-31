import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'admin_dashboard_screen.dart';
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
      UpdateService.checkForUpdates(context, 'admin');
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
          await _recordOwnerLogin(orgCode);
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

        // Only allow Admin login in Admin App
        throw StateError(
          'This app is for Admin use only. Workers/Supervisors should use their respective apps.',
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
      appBar: AppBar(title: const Text('Admin App')),
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
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const FactoryRegistrationPage(),
                              ),
                            );
                          },
                          child: const Text('Register Factory'),
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

class FactoryRegistrationPage extends StatefulWidget {
  const FactoryRegistrationPage({super.key});
  @override
  State<FactoryRegistrationPage> createState() =>
      _FactoryRegistrationPageState();
}

class _FactoryRegistrationPageState extends State<FactoryRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final LocationService _locationService = LocationService();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController(text: '500');
  final _ownerUserController = TextEditingController();
  final _ownerPassController = TextEditingController();
  XFile? _logo;
  bool _isSaving = false;
  bool _isUsingGps = false;

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _logo = picked);
    }
  }

  Future<String?> _uploadLogoIfAny() async {
    if (_logo == null) return null;
    try {
      final bytes = await _logo!.readAsBytes();
      final fileName =
          'logo_${DateTime.now().millisecondsSinceEpoch}_${_codeController.text.replaceAll(' ', '_')}.png';
      try {
        await Supabase.instance.client.storage
            .from('factory_logos')
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: true,
              ),
            );
      } catch (e) {
        if (e.toString().contains('Bucket not found') ||
            e.toString().contains('404')) {
          await Supabase.instance.client.storage.createBucket(
            'factory_logos',
            const BucketOptions(public: true),
          );
          await Supabase.instance.client.storage
              .from('factory_logos')
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/png',
                  upsert: true,
                ),
              );
        } else {
          rethrow;
        }
      }
      return Supabase.instance.client.storage
          .from('factory_logos')
          .getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isUsingGps = true);
    try {
      // Admin doesn't strictly need "Always" permission as much as worker,
      // but we request it for consistency and potential future use.
      final pos = await _locationService.getCurrentLocation(
        requestAlways: true,
      );
      _latController.text = pos.latitude.toStringAsFixed(6);
      _lngController.text = pos.longitude.toStringAsFixed(6);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coordinates set from GPS')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error using GPS: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUsingGps = false);
    }
  }

  Future<void> _saveFactory() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);
    try {
      final code = _codeController.text.trim();
      final dup = await Supabase.instance.client
          .from('organizations')
          .select()
          .eq('organization_code', code)
          .maybeSingle();
      if (dup != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Factory Code already exists. Choose a different code.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final lat = double.tryParse(_latController.text) ?? 0.0;
      final lng = double.tryParse(_lngController.text) ?? 0.0;
      final radius = double.tryParse(_radiusController.text) ?? 500.0;
      final logoUrl = await _uploadLogoIfAny();
      final payload = {
        'organization_code': code,
        'factory_name': _nameController.text,
        'organization_name': _nameController.text,
        'address': _addressController.text,
        'latitude': lat,
        'longitude': lng,
        'radius_meters': radius,
        'owner_username': _ownerUserController.text,
        'owner_password': _ownerPassController.text,
      };
      if (logoUrl != null) {
        payload['logo_url'] = logoUrl;
      }
      try {
        await Supabase.instance.client.from('organizations').insert(payload);
      } catch (e) {
        if (logoUrl != null &&
            (e.toString().contains('PGRST204') ||
                e.toString().contains('column') ||
                e.toString().contains('missing'))) {
          payload.remove('logo_url');
          await Supabase.instance.client.from('organizations').insert(payload);
        } else {
          rethrow;
        }
      }
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
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Factory')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'Factory Code',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Factory Name',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lngController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton(
                    onPressed: _isUsingGps ? null : _useCurrentLocation,
                    child: _isUsingGps
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Use Current Location'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _radiusController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Radius (meters)',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Radius defines the geofence around your factory in meters. '
                  'Set coordinates at the center of your location using "Use Current Location". '
                  'For example, 200 m covers a small campus; 500 m covers a larger area.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ownerUserController,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ownerPassController,
                        decoration: const InputDecoration(
                          labelText: 'Owner Password',
                        ),
                        obscureText: true,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickLogo,
                      icon: const Icon(Icons.image),
                      label: const Text('Pick Factory Logo'),
                    ),
                    const SizedBox(width: 12),
                    if (_logo != null)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: kIsWeb
                            ? Image.network(_logo!.path, fit: BoxFit.cover)
                            : Image.file(
                                io.File(_logo!.path),
                                fit: BoxFit.cover,
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveFactory,
                    child: _isSaving
                        ? const CircularProgressIndicator()
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
