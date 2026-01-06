import 'dart:math';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'dart:io' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'help_screen.dart';
import 'comparison_tab.dart';
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
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 14, vsync: this);
    _fetchOrganization();
    _fetchUnreadCount();
    _setupNotificationListener();
    _startLocationLogging();
  }

  void _startLocationLogging() {
    _logAdminLocation();
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _logAdminLocation();
    });
  }

  Future<void> _logAdminLocation() async {
    try {
      final pos = await LocationService().getCurrentLocation();
      // Admins are not in the workers table, so we log to production_outofbounds or a separate admin_logs table if needed.
      // For now, we only log if they are outside to production_outofbounds for history, or just skip logging to boundary_events.

      final org = await _supabase
          .from('organizations')
          .select()
          .eq('organization_code', widget.organizationCode)
          .maybeSingle();

      if (org != null) {
        final lat = (org['latitude'] ?? 0.0) * 1.0;
        final lng = (org['longitude'] ?? 0.0) * 1.0;
        final radius = (org['radius_meters'] ?? 500.0) * 1.0;

        final locationService = LocationService();
        final isInside = locationService.isInside(
          pos,
          lat,
          lng,
          radius,
          bufferMultiplier: 1.1,
        );

        if (!isInside) {
          // Check if we already have an active out-of-bounds event for this admin to avoid duplicates
          final prefs = await SharedPreferences.getInstance();
          final activeEventId = prefs.getString('admin_active_outofbounds_id');

          if (activeEventId == null) {
            final eventId = const Uuid().v4();
            await _supabase.from('production_outofbounds').insert({
              'id': eventId,
              'worker_id': null, // Admin doesn't have a worker_id
              'worker_name': 'Admin: $_ownerUsername',
              'organization_code': widget.organizationCode,
              'date': DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc()),
              'exit_time': DateTime.now().toUtc().toIso8601String(),
              'exit_latitude': pos.latitude,
              'exit_longitude': pos.longitude,
            });
            await prefs.setString('admin_active_outofbounds_id', eventId);
          }
        } else {
          // Admin is back inside, update the event if it exists
          final prefs = await SharedPreferences.getInstance();
          final activeEventId = prefs.getString('admin_active_outofbounds_id');
          if (activeEventId != null) {
            final entryTime = DateTime.now();
            try {
              final event = await _supabase
                  .from('production_outofbounds')
                  .select('exit_time')
                  .eq('id', activeEventId)
                  .maybeSingle();

              String? durationStr;
              if (event != null) {
                final exitTime = TimeUtils.parseToLocal(event['exit_time']);
                final diff = entryTime.difference(exitTime);
                durationStr = "${diff.inMinutes} mins";
              }

              await _supabase.from('production_outofbounds').update({
                'entry_time': entryTime.toUtc().toIso8601String(),
                'entry_latitude': pos.latitude,
                'entry_longitude': pos.longitude,
                'duration_minutes': durationStr,
              }).eq('id', activeEventId);
            } catch (e) {
              debugPrint('Error updating admin return: $e');
            }
            await prefs.remove('admin_active_outofbounds_id');
          }
        }
      }
    } catch (e) {
      debugPrint('Error logging admin location: $e');
    }
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
    _locationTimer?.cancel();
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
          ListTile(
            leading: Icon(
              Icons.help_outline,
              color: isDarkMode ? Colors.blue[300] : Colors.blue,
            ),
            title: Text(
              'How to Use',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            onTap: () {
              Navigator.pop(context); // Close drawer
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
            Tab(text: 'Geofence'),
            Tab(text: 'Employees'),
            Tab(text: 'Supervisors'),
            Tab(text: 'Attendance'),
            Tab(text: 'Machines'),
            Tab(text: 'Items'),
            Tab(text: 'Operations'),
            Tab(text: 'Shifts'),
            Tab(text: 'Profile'),
            Tab(text: 'Security'),
            Tab(text: 'Out of Bounds'),
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
          GeofenceTab(
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
          OutOfBoundsTab(
              organizationCode: widget.organizationCode,
              isDarkMode: isDarkMode),
        ],
      ),
    );
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => _NotificationsDialog(
        organizationCode: widget.organizationCode,
        onRead: _fetchUnreadCount,
      ),
    );
  }
}

Widget _buildFormTextField({
  required TextEditingController controller,
  required String label,
  required bool isDarkMode,
  String? hint,
  TextInputType? keyboardType,
  bool enabled = true,
  ValueChanged<String>? onChanged,
  String? Function(String?)? validator,
  Widget? prefixIcon,
  int maxLines = 1,
}) {
  final textColor = isDarkMode ? Colors.white : Colors.black;
  final secondaryTextColor =
      isDarkMode ? Colors.white70 : Colors.black.withValues(alpha: 0.6);
  final fillColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.grey.withValues(alpha: 0.1);
  final borderColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.15);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      onChanged: onChanged,
      validator: validator,
      maxLines: maxLines,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: secondaryTextColor),
        hintText: hint,
        hintStyle: TextStyle(color: secondaryTextColor.withValues(alpha: 0.5)),
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFA9DFD8)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 9. PROFILE TAB
// ---------------------------------------------------------------------------
class ProfileTab extends StatefulWidget {
  final String organizationCode;
  final VoidCallback? onProfileUpdated;
  final bool isDarkMode;
  const ProfileTab({
    super.key,
    required this.organizationCode,
    this.onProfileUpdated,
    required this.isDarkMode,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _orgNameController;
  late TextEditingController _ownerUsernameController;
  late TextEditingController _facNameController;
  late TextEditingController _addressController;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late TextEditingController _radiusController;
  late TextEditingController _acreController;
  late TextEditingController _passwordController;
  late TextEditingController _logoUrlController;

  bool _isLoading = true;
  bool _isSaving = false;
  PlatformFile? _logoFile;

  @override
  void initState() {
    super.initState();
    _orgNameController = TextEditingController();
    _ownerUsernameController = TextEditingController();
    _facNameController = TextEditingController();
    _addressController = TextEditingController();
    _latController = TextEditingController();
    _lngController = TextEditingController();
    _radiusController = TextEditingController();
    _acreController = TextEditingController();
    _passwordController = TextEditingController();
    _logoUrlController = TextEditingController();
    _fetchProfile();
  }

  @override
  void dispose() {
    _orgNameController.dispose();
    _ownerUsernameController.dispose();
    _facNameController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _acreController.dispose();
    _passwordController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('organizations')
          .select()
          .eq('organization_code', widget.organizationCode)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _orgNameController.text = data['organization_name'] ?? '';
          _ownerUsernameController.text = data['owner_username'] ?? '';
          _facNameController.text = data['factory_name'] ?? '';
          _addressController.text = data['address'] ?? '';
          _latController.text = (data['latitude'] ?? 0).toString();
          _lngController.text = (data['longitude'] ?? 0).toString();
          _radiusController.text = (data['radius_meters'] ?? 500).toString();
          _passwordController.text = data['owner_password'] ?? '';
          _logoUrlController.text = data['logo_url'] ?? '';

          // Reverse calculate acres for display
          double radius = double.tryParse(_radiusController.text) ?? 500;
          _acreController.text =
              ((radius * radius * pi) / 4046.8564).toStringAsFixed(4);

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch profile error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateRadiusFromAcres(String value) {
    double? acres = double.tryParse(value);
    if (acres != null) {
      // Radius (m) = √( Acre × 4046.8564 / π )
      double radius = sqrt((acres * 4046.8564) / pi);
      // Adding 15m buffer as recommended
      double finalRadius = radius + 15;
      setState(() {
        _radiusController.text = finalRadius.toStringAsFixed(2);
      });
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && mounted) {
      setState(() {
        _logoFile = result.files.first;
      });
    }
  }

  Future<String?> _uploadLogo() async {
    if (_logoFile == null) return _logoUrlController.text;

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_logo_${_logoFile!.name}';

    final Uint8List bytes;
    if (kIsWeb) {
      if (_logoFile!.bytes == null) return null;
      bytes = _logoFile!.bytes!;
    } else {
      bytes = _logoFile!.bytes ?? await io.File(_logoFile!.path!).readAsBytes();
    }

    return await _uploadToBucketWithAutoCreate(
      'organization_logos',
      fileName,
      bytes,
      'image/jpeg',
    );
  }

  Future<String?> _uploadToBucketWithAutoCreate(
    String bucket,
    String fileName,
    Uint8List bytes,
    String contentType,
  ) async {
    try {
      try {
        await _supabase.storage.from(bucket).uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      } on StorageException catch (se) {
        if (se.message.contains('Bucket not found') || se.statusCode == '404') {
          // Attempt to create the bucket if it's missing
          try {
            await _supabase.storage.createBucket(
              bucket,
              const BucketOptions(public: true),
            );
          } catch (ce) {
            debugPrint('Error creating bucket $bucket: $ce');
            throw 'Storage Error: Bucket "$bucket" is missing.\n\nPlease create a PUBLIC bucket named "$bucket" in your Supabase Storage dashboard to enable uploads.';
          }

          // Retry the upload
          await _supabase.storage.from(bucket).uploadBinary(
                fileName,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: true,
                ),
              );
        } else {
          rethrow;
        }
      }

      return _supabase.storage.from(bucket).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error for bucket $bucket: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final logoUrl = await _uploadLogo();

      await _supabase.from('organizations').update({
        'organization_name': _orgNameController.text,
        'owner_username': _ownerUsernameController.text,
        'factory_name': _facNameController.text,
        'address': _addressController.text,
        'latitude': double.tryParse(_latController.text) ?? 0,
        'longitude': double.tryParse(_lngController.text) ?? 0,
        'radius_meters': double.tryParse(_radiusController.text) ?? 500,
        'owner_password': _passwordController.text,
        'logo_url': logoUrl,
      }).eq('organization_code', widget.organizationCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        if (widget.onProfileUpdated != null) {
          widget.onProfileUpdated!();
        }
      }
    } catch (e) {
      debugPrint('Update profile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: widget.isDarkMode
              ? const Color(0xFFA9DFD8)
              : const Color(0xFF2E8B57),
        ),
      );
    }

    final accentColor =
        widget.isDarkMode ? const Color(0xFFA9DFD8) : const Color(0xFF2E8B57);
    final cardColor =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final backgroundColor =
        widget.isDarkMode ? const Color(0xFF21222D) : const Color(0xFFF5F5F5);
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final secondaryTextColor = widget.isDarkMode
        ? Colors.white70
        : Colors.black.withValues(alpha: 0.6);
    final borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);

    return RefreshIndicator(
      onRefresh: _fetchProfile,
      color: accentColor,
      backgroundColor: backgroundColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Organization Profile',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  Text(
                    'Manage your factory details and settings',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Logo Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: widget.isDarkMode ? 0.2 : 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.branding_watermark_rounded,
                            color: accentColor.withValues(alpha: 0.5),
                            size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'BRANDING',
                          style: TextStyle(
                            color: accentColor.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildLogoPreview(accentColor, widget.isDarkMode),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Organization Logo',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Recommended size: 512x512px',
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _pickLogo,
                                icon: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    size: 18),
                                label: Text(_logoFile == null
                                    ? 'Upload Logo'
                                    : 'Change Logo'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      accentColor.withValues(alpha: 0.1),
                                  foregroundColor: accentColor,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Basic Info Section
              _buildSectionHeader('BASIC INFORMATION',
                  Icons.info_outline_rounded, widget.isDarkMode),
              _buildFormTextField(
                controller: _orgNameController,
                label: 'Organization Name',
                isDarkMode: widget.isDarkMode,
                prefixIcon:
                    Icon(Icons.business_rounded, color: accentColor, size: 20),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              _buildFormTextField(
                controller: _ownerUsernameController,
                label: 'Owner Username',
                isDarkMode: widget.isDarkMode,
                prefixIcon:
                    Icon(Icons.person_rounded, color: accentColor, size: 20),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              _buildFormTextField(
                controller: _facNameController,
                label: 'Factory Name',
                isDarkMode: widget.isDarkMode,
                prefixIcon:
                    Icon(Icons.factory_rounded, color: accentColor, size: 20),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              _buildFormTextField(
                controller: _addressController,
                label: 'Factory Address',
                isDarkMode: widget.isDarkMode,
                prefixIcon: Icon(Icons.location_on_rounded,
                    color: accentColor, size: 20),
                maxLines: 2,
              ),

              const SizedBox(height: 24),
              // Geofencing Section
              _buildSectionHeader('GEOFENCING & BOUNDARIES', Icons.map_rounded,
                  widget.isDarkMode),
              Row(
                children: [
                  Expanded(
                    child: _buildFormTextField(
                      controller: _latController,
                      label: 'Latitude',
                      isDarkMode: widget.isDarkMode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFormTextField(
                      controller: _lngController,
                      label: 'Longitude',
                      isDarkMode: widget.isDarkMode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildFormTextField(
                      controller: _acreController,
                      label: 'Factory Area (Acres)',
                      isDarkMode: widget.isDarkMode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: _calculateRadiusFromAcres,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFormTextField(
                      controller: _radiusController,
                      label: 'Radius (Meters)',
                      isDarkMode: widget.isDarkMode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      enabled: false,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              // Security Section
              _buildSectionHeader(
                  'SECURITY', Icons.security_rounded, widget.isDarkMode),
              _buildFormTextField(
                controller: _passwordController,
                label: 'Owner Dashboard Password',
                isDarkMode: widget.isDarkMode,
                prefixIcon:
                    Icon(Icons.password_rounded, color: accentColor, size: 20),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _updateProfile,
                  icon: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.isDarkMode
                                ? const Color(0xFF171821)
                                : Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(
                    _isSaving ? 'SAVING CHANGES...' : 'UPDATE SETTINGS',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: widget.isDarkMode
                        ? const Color(0xFF21222D)
                        : Colors.white,
                    elevation: 4,
                    shadowColor: accentColor.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoPreview(Color accentColor, bool isDarkMode) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _logoFile != null
            ? (kIsWeb
                ? Image.memory(
                    _logoFile!.bytes!,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    io.File(_logoFile!.path!),
                    fit: BoxFit.cover,
                  ))
            : _logoUrlController.text.isNotEmpty
                ? Image.network(
                    _logoUrlController.text,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, st) => Icon(Icons.factory_rounded,
                        size: 40,
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.1)),
                  )
                : Icon(Icons.factory_rounded,
                    size: 40,
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.1)),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDarkMode) {
    final color =
        isDarkMode ? const Color(0xFFA9DFD8) : const Color(0xFF2E8B57);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
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
}

// ---------------------------------------------------------------------------
// 8. ATTENDANCE TAB
// ---------------------------------------------------------------------------
class AttendanceTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const AttendanceTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _attendance = [];
  bool _isLoading = true;
  bool _isExporting = false;

  // Filters
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _fetchAttendance();
  }

  Future<List<Map<String, dynamic>>> _fetchProductionForAttendance(
    String workerId,
    String date,
    String? shiftName,
  ) async {
    try {
      final response = await _supabase
          .from('production_logs')
          .select('*')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: true);

      final rawLogs = List<Map<String, dynamic>>.from(response);

      // Filter by date and shift in memory for accuracy
      final filtered = rawLogs.where((log) {
        final createdAt = TimeUtils.parseToLocal(log['created_at']);
        final logDate = DateFormat('yyyy-MM-dd').format(createdAt);
        final logShift = log['shift_name']?.toString();

        bool dateMatch = logDate == date;
        bool shiftMatch = shiftName == null || logShift == shiftName;

        return dateMatch && shiftMatch;
      }).toList();

      if (filtered.isEmpty) return [];

      // Fetch item and machine names
      final itemIds = filtered
          .map((l) => l['item_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final machineIds = filtered
          .map((l) => l['machine_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, String> itemMap = {};
      Map<String, String> machineMap = {};

      if (itemIds.isNotEmpty) {
        final itemsResp = await _supabase
            .from('items')
            .select('item_id, name')
            .filter('item_id', 'in', itemIds);
        for (var i in itemsResp) {
          itemMap[i['item_id'].toString()] = i['name'];
        }
      }

      if (machineIds.isNotEmpty) {
        final machinesResp = await _supabase
            .from('machines')
            .select('machine_id, name')
            .filter('machine_id', 'in', machineIds);
        for (var m in machinesResp) {
          machineMap[m['machine_id'].toString()] = m['name'];
        }
      }

      for (var log in filtered) {
        log['item_name'] = itemMap[log['item_id'].toString()] ?? 'Unknown';
        log['machine_name'] = machineMap[log['machine_id'].toString()] ?? 'N/A';
      }

      return filtered;
    } catch (e) {
      debugPrint('Error fetching production for attendance: $e');
      return [];
    }
  }

  Future<void> _fetchEmployees() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name, role')
          .eq('organization_code', widget.organizationCode)
          .neq('role', 'supervisor')
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(resp);
        });
      }
    } catch (e) {
      debugPrint('Fetch employees error: $e');
    }
  }

  Future<void> _fetchAttendance() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase
          .from('attendance')
          .select('*, workers:worker_id(name)')
          .eq('organization_code', widget.organizationCode);

      if (_selectedEmployeeId != null) {
        query = query.eq('worker_id', _selectedEmployeeId!);
      }

      if (_selectedDateRange != null) {
        query = query
            .gte(
              'date',
              DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
            )
            .lte(
              'date',
              DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
            );
      }

      final response = await query
          .order('date', ascending: false)
          .order('check_in', ascending: false);

      if (mounted) {
        setState(() {
          _attendance = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch attendance error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDateRange) {
      if (mounted) {
        setState(() {
          _selectedDateRange = picked;
        });
      }
      _fetchAttendance();
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      // Rename default Sheet1 to avoid empty first sheet
      excel.rename('Sheet1', 'Efficiency Report');
      final sheet = excel['Efficiency Report'];

      // Add Headers
      sheet.appendRow([
        TextCellValue('Date'),
        TextCellValue('Shift'),
        TextCellValue('Operator ID'),
        TextCellValue('Operator Name'),
        TextCellValue('In Time'),
        TextCellValue('Out Time'),
        TextCellValue('Item'),
        TextCellValue('Operation'),
        TextCellValue('Production Qty'),
        TextCellValue('Performance Diff'),
        TextCellValue('Remarks'),
      ]);

      for (var record in _attendance) {
        final worker = record['workers'] as Map<String, dynamic>?;
        final workerName = worker?['name'] ?? 'Unknown';
        final workerId = record['worker_id'];
        final dateStr = record['date'];
        final shiftName = record['shift_name'];

        final logs = await _fetchProductionForAttendance(
          workerId,
          dateStr,
          shiftName,
        );

        if (logs.isEmpty) {
          // Add row even if no production logs for basic attendance info
          sheet.appendRow([
            TextCellValue(dateStr),
            TextCellValue(shiftName ?? 'N/A'),
            TextCellValue(workerId),
            TextCellValue(workerName),
            TextCellValue(TimeUtils.formatTo12Hour(record['check_in'])),
            TextCellValue(TimeUtils.formatTo12Hour(record['check_out'])),
            TextCellValue('N/A'),
            TextCellValue('N/A'),
            const IntCellValue(0),
            const IntCellValue(0),
            TextCellValue(record['remarks'] ?? ''),
          ]);
        } else {
          for (var log in logs) {
            sheet.appendRow([
              TextCellValue(dateStr),
              TextCellValue(shiftName ?? 'N/A'),
              TextCellValue(workerId),
              TextCellValue(workerName),
              TextCellValue(TimeUtils.formatTo12Hour(record['check_in'])),
              TextCellValue(TimeUtils.formatTo12Hour(record['check_out'])),
              TextCellValue(log['item_name'] ?? 'N/A'),
              TextCellValue(log['operation'] ?? 'N/A'),
              IntCellValue(log['quantity'] ?? 0),
              IntCellValue(log['performance_diff'] ?? 0),
              TextCellValue(log['remarks'] ?? ''),
            ]);
          }
        }
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final fileName = 'Operator_Efficiency_$timestamp.xlsx';

        if (kIsWeb) {
          await WebDownloadHelper.download(
            fileBytes,
            fileName,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
        } else {
          final directory = await getTemporaryDirectory();
          final file = io.File('${directory.path}/$fileName');
          await file.writeAsBytes(fileBytes);

          if (mounted) {
            await share_plus.Share.shareXFiles([
              share_plus.XFile(file.path),
            ], text: 'Operator Efficiency Report');
          }
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _showAttendanceDetails(Map<String, dynamic> record) async {
    final worker = record['workers'] as Map<String, dynamic>?;
    final workerName = worker?['name'] ?? 'Unknown Worker';
    final workerId = record['worker_id'];
    final dateStr = record['date'];
    final shiftName = record['shift_name'];

    final Color dialogBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color cardBg = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.6);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workerName,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Attendance Detail - $dateStr',
                    style: TextStyle(
                      fontSize: 13,
                      color: subTextColor,
                      fontWeight: FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchProductionForAttendance(workerId, dateStr, shiftName),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFA9DFD8)),
                );
              }

              final logs = snapshot.data ?? [];

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.isDarkMode
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: _detailSection('Shift Info', [
                        _detailRow('Shift Name', record['shift_name'] ?? 'N/A'),
                        _detailRow('Status', record['status'] ?? 'On Time'),
                        _detailRow(
                          'Check In',
                          TimeUtils.formatTo12Hour(record['check_in']),
                        ),
                        _detailRow(
                          'Check Out',
                          TimeUtils.formatTo12Hour(record['check_out']),
                        ),
                        _detailRow(
                          'Verified',
                          (record['is_verified'] ?? false) ? 'Yes' : 'No',
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Production Activity',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (logs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history_toggle_off,
                              color: subTextColor.withValues(alpha: 0.4),
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No production activity recorded.',
                              style: TextStyle(
                                color: subTextColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...logs.map(
                        (log) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: widget.isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Item: ${log['item_name'] ?? 'Unknown'}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (log['performance_diff'] ?? 0) >=
                                                0
                                            ? Colors.green
                                                .withValues(alpha: 0.1)
                                            : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Diff: ${log['performance_diff'] >= 0 ? "+" : ""}${log['performance_diff']}',
                                        style: TextStyle(
                                          color:
                                              (log['performance_diff'] ?? 0) >=
                                                      0
                                                  ? Colors.green
                                                  : Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Operation: ${log['operation']}',
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Machine: ${log['machine_name'] ?? 'N/A'}',
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 14,
                                    color: subTextColor.withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${TimeUtils.formatTo12Hour(log['start_time'], format: 'hh:mm a')} - ${TimeUtils.formatTo12Hour(log['end_time'], format: 'hh:mm a')}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: subTextColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Qty: ${log['quantity']}',
                                    style: TextStyle(
                                      color: widget.isDarkMode
                                          ? const Color(0xFFA9DFD8)
                                          : const Color(0xFF2E8B57),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              if (log['remarks'] != null &&
                                  log['remarks'].toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: widget.isDarkMode
                                        ? Colors.white.withValues(alpha: 0.03)
                                        : Colors.black.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Remarks: ${log['remarks']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: subTextColor,
                                    ),
                                  ),
                                ),
                              ],
                              if (log['created_by_supervisor'] == true) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.verified_user_outlined,
                                      size: 14,
                                      color: Colors.blueAccent
                                          .withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Logged by Supervisor (${log['supervisor_id'] ?? 'Unknown'})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueAccent
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFFA9DFD8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFFA9DFD8),
          ),
        ),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.6);

    Color valueColor = textColor;
    if (value == 'Absent') {
      valueColor = Colors.red;
    } else if (value == 'Early Leave' ||
        value == 'Overtime' ||
        value == 'Both') {
      valueColor = Colors.orangeAccent;
    } else if (value == 'On Time') {
      valueColor = Colors.green;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: subTextColor, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
                fontSize: 13,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color cardColor =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    const Color accentColor = Color(0xFFA9DFD8);
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);

    return RefreshIndicator(
      onRefresh: _fetchAttendance,
      color: accentColor,
      backgroundColor:
          widget.isDarkMode ? const Color(0xFF21222D) : Colors.white,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Attendance',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Track and manage operator presence',
                            style: TextStyle(
                              color: subTextColor,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildExportButton(accentColor),
                  ],
                ),
                const SizedBox(height: 24),
                _buildFilters(cardColor, accentColor, textColor, subTextColor,
                    borderColor),
              ],
            ),
          ),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(100.0),
                child: CircularProgressIndicator(color: accentColor),
              ),
            )
          else if (_attendance.isEmpty)
            _buildEmptyState()
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _attendance.length,
              itemBuilder: (context, index) {
                final record = _attendance[index];
                return _buildAttendanceCard(record, cardColor);
              },
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildExportButton(Color accentColor) {
    return ElevatedButton.icon(
      onPressed: _isExporting ? null : _exportToExcel,
      icon: _isExporting
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isDarkMode ? const Color(0xFF21222D) : Colors.white),
              ),
            )
          : const Icon(Icons.ios_share_rounded, size: 18),
      label: Text(_isExporting ? 'Exporting...' : 'Export Excel'),
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor:
            widget.isDarkMode ? const Color(0xFF21222D) : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildFilters(Color cardColor, Color accentColor, Color textColor,
      Color subTextColor, Color borderColor) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor:
                  widget.isDarkMode ? const Color(0xFF21222D) : Colors.white,
            ),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedEmployeeId,
              dropdownColor:
                  widget.isDarkMode ? const Color(0xFF21222D) : Colors.white,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Filter by Employee',
                labelStyle: TextStyle(
                  color: subTextColor,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: borderColor,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: borderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: accentColor.withValues(alpha: 0.5),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child:
                      Text('All Employees', style: TextStyle(color: textColor)),
                ),
                ..._employees.map((e) => DropdownMenuItem(
                      value: e['worker_id'].toString(),
                      child: Text(e['name'].toString(),
                          style: TextStyle(color: textColor)),
                    )),
              ],
              onChanged: (val) {
                setState(() => _selectedEmployeeId = val);
                _fetchAttendance();
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: _selectDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: Color(0xFFA9DFD8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedDateRange == null
                          ? 'Select Dates'
                          : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
                      style: TextStyle(fontSize: 13, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selectedDateRange != null || _selectedEmployeeId != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: subTextColor),
              onPressed: () {
                setState(() {
                  _selectedEmployeeId = null;
                  _selectedDateRange = null;
                });
                _fetchAttendance();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white70
        : Colors.black.withValues(alpha: 0.6);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.02)
                    : Colors.black.withValues(alpha: 0.02),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_note_rounded,
                size: 48,
                color: widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Records Found',
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or date range',
              style: TextStyle(
                color: subTextColor,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> record, Color cardColor) {
    final worker = record['workers'] as Map<String, dynamic>?;
    final workerName = worker?['name'] ?? 'Unknown Worker';
    final status = record['status'] ?? 'On Time';
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white70
        : Colors.black.withValues(alpha: 0.6);

    Color statusColor = const Color(0xFFA9DFD8);
    if (status == 'Absent') {
      statusColor = Colors.redAccent;
    } else if (status.contains('Early Leave')) {
      statusColor = Colors.orangeAccent;
    } else if (status.contains('Overtime')) {
      statusColor = Colors.blueAccent;
    } else if (status == 'Both') {
      statusColor = Colors.purpleAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: widget.isDarkMode ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showAttendanceDetails(record),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_outline_rounded,
                      color: statusColor, size: 24),
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
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, MMM dd')
                            .format(DateTime.parse(record['date'])),
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${TimeUtils.formatTo12Hour(record['check_in'])} - ${record['check_out'] != null ? TimeUtils.formatTo12Hour(record['check_out']) : '--:--'}',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.2),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const ReportsTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _filter = 'All'; // All, Today, Week, Month
  List<Map<String, dynamic>> _employees = [];
  int _extraUnitsToday = 0;

  Widget _metricTile(String title, String value, Color color, IconData icon) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white70
        : Colors.black.withValues(alpha: 0.6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final isVerySmall = constraints.maxHeight < 80;

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isDarkMode
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.12),
            ),
            boxShadow: widget.isDarkMode
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          padding: EdgeInsets.all(isLandscape ? 8 : 12),
          child: isVerySmall
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              value,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 10,
                              color: subTextColor,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: subTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _logInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  int _computeEfficiency(int qty, int target) {
    if (target <= 0) return 0;
    final pct = ((qty / target) * 100).round();
    return pct.clamp(0, 999);
  }

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _fetchExtraUnitsTodayOrg();
    _fetchEmployeesForExport();
  }

  Future<void> _fetchEmployeesForExport() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name, role')
          .eq('organization_code', widget.organizationCode)
          .neq('role', 'supervisor')
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(resp);
        });
      }
    } catch (e) {
      debugPrint('Fetch employees for export error: $e');
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _buildQuery(isExport: false);
      final rawLogs = List<Map<String, dynamic>>.from(response);
      final enriched = await _enrichLogsWithNames(rawLogs);
      if (mounted) {
        setState(() {
          _logs = enriched;
          _isLoading = false;
        });
        // Update rolling 24h extra units after logs load
        _fetchExtraUnitsTodayOrg();
      }
    } catch (e) {
      // Fallback if relationship fails
      if (e.toString().contains('relationship') ||
          e.toString().contains('foreign') ||
          e.toString().contains('PGRST200')) {
        try {
          final fallbackResponse = await _supabase
              .from('production_logs')
              .select()
              .eq('organization_code', widget.organizationCode)
              .order('created_at', ascending: false)
              .limit(50);
          final enriched = await _enrichLogsWithNames(
            List<Map<String, dynamic>>.from(fallbackResponse),
          );
          if (mounted) {
            setState(() {
              _logs = enriched;
              _isLoading = false;
            });
          }
          // Successfully loaded fallback, so return without showing error
          return;
        } catch (_) {}
      }

      if (mounted) {
        // Suppress error if it's just empty/missing table, user prefers "No work done"
        // Only print debug info if it's NOT the relationship error we just tried to handle
        if (!e.toString().contains('PGRST200')) {
          debugPrint('Fetch logs error: $e');
        }

        String msg = e.toString();
        if (msg.contains('Load failed') || msg.contains('ClientException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Connection failed. Check your internet or ad-blocker.',
              ),
            ),
          );
        }

        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // Build query based on filter
  Future<dynamic> _buildQuery({required bool isExport}) {
    var query = _supabase
        .from('production_logs')
        .select('*, remarks') // Explicitly select remarks to be safe
        .eq('organization_code', widget.organizationCode);

    // Apply Date Filters
    final now = DateTime.now();
    if (_filter == 'Today') {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());
    } else if (_filter == 'Week') {
      // Last 7 days
      final start = now.subtract(const Duration(days: 7));
      query = query.gte('created_at', start.toIso8601String());
    } else if (_filter == 'Month') {
      final start = DateTime(now.year, now.month, 1);
      query = query.gte('created_at', start.toIso8601String());
    }

    if (!isExport) {
      // Limit for display
      return query.order('created_at', ascending: false).limit(50);
    }
    // No limit for export
    return query.order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> _enrichLogsWithNames(
    List<Map<String, dynamic>> rawLogs,
  ) async {
    try {
      final employeesResp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode);
      final itemsResp = await _supabase
          .from('items')
          .select('item_id, name, operation_details')
          .eq('organization_code', widget.organizationCode);
      final employeeMap = <String, String>{};
      final itemMap = <String, String>{};
      final targetMap = <String, int>{}; // key: item_id|operation -> target
      for (final w in List<Map<String, dynamic>>.from(employeesResp)) {
        final id = w['worker_id']?.toString() ?? '';
        final name = w['name']?.toString() ?? '';
        if (id.isNotEmpty) employeeMap[id] = name;
      }
      for (final it in List<Map<String, dynamic>>.from(itemsResp)) {
        final id = it['item_id']?.toString() ?? '';
        final name = it['name']?.toString() ?? '';
        if (id.isNotEmpty) itemMap[id] = name;
        final ops = (it['operation_details'] as List? ?? []);
        for (final op in ops) {
          final opName = (op['name'] ?? '').toString();
          final tgt = (op['target'] ?? 0) as int;
          if (opName.isNotEmpty) {
            targetMap['$id|$opName'] = tgt;
          }
        }
      }
      return rawLogs.map((log) {
        final wid = log['worker_id']?.toString() ?? '';
        final iid = log['item_id']?.toString() ?? '';
        final opName = log['operation']?.toString() ?? '';
        final target = targetMap['$iid|$opName'];
        return {
          ...log,
          'employeeName': employeeMap[wid] ?? 'Unknown',
          'itemName': itemMap[iid] ?? 'Unknown',
          if (target != null) 'target': target,
        };
      }).toList();
    } catch (_) {
      return rawLogs;
    }
  }

  // Aggregate logs: Employee -> Item -> Operation -> {qty, diff, employeeName}

  Future<void> _showExportOptions() async {
    String groupBy = 'Worker';
    String period = _filter;
    DateTimeRange? customRange;
    final Set<String> selectedWorkers = {};

    final machinesController = TextEditingController();
    final itemsController = TextEditingController();
    final opsController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final Color dialogBg =
            widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
        final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
        final Color subTextColor = widget.isDarkMode
            ? Colors.white70
            : Colors.black.withValues(alpha: 0.6);
        final Color fieldBg = widget.isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05);
        final Color borderColor = widget.isDarkMode
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1);

        return AlertDialog(
          backgroundColor: dialogBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFA9DFD8).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.file_download_outlined,
                    color: Color(0xFFA9DFD8), size: 20),
              ),
              const SizedBox(width: 12),
              Text('Export Options',
                  style: TextStyle(color: textColor, fontSize: 18)),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      unselectedWidgetColor:
                          subTextColor.withValues(alpha: 0.5),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GROUP BY',
                              style: TextStyle(
                                  color: Color(0xFFA9DFD8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: groupBy,
                                isExpanded: true,
                                dropdownColor: dialogBg,
                                style:
                                    TextStyle(color: textColor, fontSize: 14),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Worker', child: Text('Worker')),
                                  DropdownMenuItem(
                                      value: 'Machine', child: Text('Machine')),
                                  DropdownMenuItem(
                                      value: 'Operation',
                                      child: Text('Operation')),
                                  DropdownMenuItem(
                                      value: 'Item', child: Text('Item')),
                                ],
                                onChanged: (v) =>
                                    setState(() => groupBy = v ?? 'Worker'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('PERIOD',
                              style: TextStyle(
                                  color: Color(0xFFA9DFD8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: period,
                                isExpanded: true,
                                dropdownColor: dialogBg,
                                style:
                                    TextStyle(color: textColor, fontSize: 14),
                                items: [
                                  'All',
                                  'Today',
                                  'Week',
                                  'Month',
                                  'Custom'
                                ]
                                    .map((e) => DropdownMenuItem(
                                        value: e, child: Text(e)))
                                    .toList(),
                                onChanged: (v) async {
                                  if (v == null) return;
                                  if (ctx.mounted) setState(() => period = v);
                                  if (v == 'Custom') {
                                    final picked = await showDateRangePicker(
                                      context: context,
                                      firstDate: DateTime(2023),
                                      lastDate: DateTime.now(),
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme: widget.isDarkMode
                                                ? const ColorScheme.dark(
                                                    primary: Color(0xFFA9DFD8),
                                                    onPrimary:
                                                        Color(0xFF21222D),
                                                    surface: Color(0xFF21222D),
                                                    onSurface: Colors.white,
                                                  )
                                                : const ColorScheme.light(
                                                    primary: Color(0xFFA9DFD8),
                                                    onPrimary: Colors.white,
                                                    surface: Colors.white,
                                                    onSurface: Colors.black,
                                                  ),
                                            dialogTheme: DialogThemeData(
                                              backgroundColor: dialogBg,
                                            ),
                                          ),
                                          child: child!,
                                        );
                                      },
                                      initialDateRange: customRange ??
                                          DateTimeRange(
                                            start: DateTime.now().subtract(
                                              const Duration(days: 7),
                                            ),
                                            end: DateTime.now(),
                                          ),
                                    );
                                    if (picked != null && ctx.mounted) {
                                      setState(() => customRange = picked);
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                          if (period == 'Custom' && customRange != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA9DFD8)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${customRange!.start.toIso8601String().substring(0, 10)} — ${customRange!.end.toIso8601String().substring(0, 10)}',
                                  style: const TextStyle(
                                      color: Color(0xFFA9DFD8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Text('FILTER (OPTIONAL)',
                              style: TextStyle(
                                  color: Color(0xFFA9DFD8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1)),
                          const SizedBox(height: 8),
                          Theme(
                            data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                                listTileTheme: ListTileThemeData(
                                  textColor: textColor,
                                  iconColor: const Color(0xFFA9DFD8),
                                )),
                            child: ExpansionTile(
                              title: Text('Workers',
                                  style: TextStyle(
                                      color: textColor, fontSize: 14)),
                              iconColor: const Color(0xFFA9DFD8),
                              collapsedIconColor: subTextColor,
                              backgroundColor: fieldBg.withValues(alpha: 0.03),
                              collapsedBackgroundColor:
                                  fieldBg.withValues(alpha: 0.03),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              collapsedShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              children: [
                                SizedBox(
                                  height: 180,
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    children: _employees.map((e) {
                                      final id =
                                          (e['worker_id'] ?? '').toString();
                                      final name = (e['name'] ?? '').toString();
                                      final checked =
                                          selectedWorkers.contains(id);
                                      return CheckboxListTile(
                                        value: checked,
                                        activeColor: const Color(0xFFA9DFD8),
                                        checkColor: dialogBg,
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              selectedWorkers.add(id);
                                            } else {
                                              selectedWorkers.remove(id);
                                            }
                                          });
                                        },
                                        title: Text('$name ($id)',
                                            style: TextStyle(
                                                color: subTextColor,
                                                fontSize: 13)),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildFormTextField(
                            controller: machinesController,
                            label: 'Machine IDs',
                            isDarkMode: widget.isDarkMode,
                            hint: 'Comma-separated (e.g. M1, M2)',
                          ),
                          _buildFormTextField(
                            controller: itemsController,
                            label: 'Item IDs',
                            isDarkMode: widget.isDarkMode,
                            hint: 'Comma-separated (e.g. IT1, IT2)',
                          ),
                          _buildFormTextField(
                            controller: opsController,
                            label: 'Operations',
                            isDarkMode: widget.isDarkMode,
                            hint: 'Comma-separated (e.g. OP1, OP2)',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCEL', style: TextStyle(color: subTextColor)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final workerIds = selectedWorkers.toList();
                final machineIds = machinesController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final itemIds = itemsController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final operations = opsController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                await _exportWithOptions(
                  groupBy: groupBy,
                  period: period,
                  dateRange: customRange,
                  workerIds: workerIds.isEmpty ? null : workerIds,
                  machineIds: machineIds.isEmpty ? null : machineIds,
                  itemIds: itemIds.isEmpty ? null : itemIds,
                  operations: operations.isEmpty ? null : operations,
                );
              },
              icon: const Icon(Icons.download, size: 16),
              label: const Text('EXPORT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA9DFD8),
                foregroundColor:
                    widget.isDarkMode ? const Color(0xFF21222D) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );

    machinesController.dispose();
    itemsController.dispose();
    opsController.dispose();
  }

  Future<void> _exportWithOptions({
    required String groupBy,
    String? period,
    DateTimeRange? dateRange,
    List<String>? workerIds,
    List<String>? machineIds,
    List<String>? itemIds,
    List<String>? operations,
  }) async {
    setState(() => _isExporting = true);
    try {
      var query = _supabase
          .from('production_logs')
          .select('*, remarks')
          .eq('organization_code', widget.organizationCode);
      final now = DateTime.now();
      final effectivePeriod = period ?? _filter;
      if (effectivePeriod == 'Today') {
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1));
        query = query
            .gte('created_at', start.toIso8601String())
            .lt('created_at', end.toIso8601String());
      } else if (effectivePeriod == 'Week') {
        final start = now.subtract(const Duration(days: 7));
        query = query.gte('created_at', start.toIso8601String());
      } else if (effectivePeriod == 'Month') {
        final start = DateTime(now.year, now.month, 1);
        query = query.gte('created_at', start.toIso8601String());
      } else if (effectivePeriod == 'Custom' && dateRange != null) {
        query = query
            .gte('created_at', dateRange.start.toIso8601String())
            .lte('created_at', dateRange.end.toIso8601String());
      }
      final allLogsRaw = List<Map<String, dynamic>>.from(
        await query.order('created_at', ascending: false),
      );
      final filteredRaw = allLogsRaw.where((l) {
        final wid = (l['worker_id'] ?? '').toString();
        final mid = (l['machine_id'] ?? '').toString();
        final iid = (l['item_id'] ?? '').toString();
        final op = (l['operation'] ?? '').toString();
        final okWorker = workerIds == null || workerIds.contains(wid);
        final okMachine = machineIds == null || machineIds.contains(mid);
        final okItem = itemIds == null || itemIds.contains(iid);
        final okOp = operations == null || operations.contains(op);
        return okWorker && okMachine && okItem && okOp;
      }).toList();
      final allLogs = await _enrichLogsWithNames(filteredRaw);
      if (allLogs.isEmpty) {
        throw Exception('No data to export for these options');
      }

      var excel = Excel.createExcel();
      // Rename default Sheet1 to avoid empty first sheet
      excel.rename('Sheet1', 'Summary ($groupBy)');
      Sheet summarySheet = excel['Summary ($groupBy)'];
      summarySheet.appendRow([
        TextCellValue(groupBy),
        TextCellValue('Item ID'),
        TextCellValue('Operation'),
        TextCellValue('Total Quantity'),
        TextCellValue('Total Surplus/Deficit'),
      ]);
      final summaryRows = _aggregateByGroup(groupBy, allLogs);
      for (final r in summaryRows) {
        summarySheet.appendRow([
          TextCellValue((r['group'] ?? '').toString()),
          TextCellValue((r['item_id'] ?? '').toString()),
          TextCellValue((r['operation'] ?? '').toString()),
          IntCellValue((r['qty'] ?? 0) as int),
          IntCellValue((r['diff'] ?? 0) as int),
        ]);
      }

      Sheet detailsSheet = excel['Detailed Logs'];
      detailsSheet.appendRow([
        TextCellValue('Employee Name'),
        TextCellValue('Employee ID'),
        TextCellValue('Machine ID'),
        TextCellValue('Item ID'),
        TextCellValue('Operation'),
        TextCellValue('Shift'),
        TextCellValue('Created At'),
        TextCellValue('Start Time'),
        TextCellValue('End Time'),
        TextCellValue('Working Hours'),
        TextCellValue('Worker Qty'),
        TextCellValue('Supervisor Qty'),
        TextCellValue('Surplus/Deficit'),
        TextCellValue('Status'),
        TextCellValue('Verified By'),
        TextCellValue('Verified At'),
        TextCellValue('Remarks'),
      ]);
      for (final log in allLogs) {
        final eName = (log['employeeName'] ?? 'Unknown').toString();
        final workerId = (log['worker_id'] ?? '').toString();
        final machineId = (log['machine_id'] ?? '').toString();
        final itemId = (log['item_id'] ?? '').toString();
        final opName = (log['operation'] ?? '').toString();
        final shiftName = (log['shift_name'] ?? '').toString();
        final qty = (log['quantity'] ?? 0) as int;
        final supQty = (log['supervisor_quantity'] ?? '-') as Object;
        final diff = (log['performance_diff'] ?? 0) as int;
        final status = diff >= 0 ? 'Surplus' : 'Deficit';
        final remarks = (log['remarks'] ?? '').toString();
        final createdAtStr = (log['created_at'] ?? '').toString();
        final startTimeStr = (log['start_time'] ?? '').toString();
        final endTimeStr = (log['end_time'] ?? '').toString();
        final verifiedBy = (log['verified_by'] ?? '').toString();
        final verifiedAtStr = (log['verified_at'] ?? '').toString();

        DateTime createdAtLocal;
        try {
          createdAtLocal = TimeUtils.parseToLocal(createdAtStr);
        } catch (_) {
          createdAtLocal = DateTime.now();
        }
        String startTimeLocal = '-';
        String endTimeLocal = '-';
        String totalHours = '-';
        if (startTimeStr.isNotEmpty) {
          try {
            final st = TimeUtils.parseToLocal(startTimeStr);
            startTimeLocal = DateFormat('hh:mm a').format(st);
            if (endTimeStr.isNotEmpty) {
              final et = TimeUtils.parseToLocal(endTimeStr);
              endTimeLocal = DateFormat('hh:mm a').format(et);
              final duration = et.difference(st);
              final hours = duration.inHours;
              final minutes = duration.inMinutes.remainder(60);
              totalHours = '${hours}h ${minutes}m';
            }
          } catch (_) {}
        }
        String createdAtFormatted = DateFormat(
          'dd MMM yyyy, hh:mm a',
        ).format(createdAtLocal);
        String verifiedAtFormatted = verifiedAtStr.isNotEmpty
            ? DateFormat(
                'dd MMM yyyy, hh:mm a',
              ).format(TimeUtils.parseToLocal(verifiedAtStr))
            : '-';

        detailsSheet.appendRow([
          TextCellValue(eName),
          TextCellValue(workerId),
          TextCellValue(machineId),
          TextCellValue(itemId),
          TextCellValue(opName),
          TextCellValue(shiftName.isEmpty ? '-' : shiftName),
          TextCellValue(createdAtFormatted),
          TextCellValue(startTimeLocal),
          TextCellValue(endTimeLocal),
          TextCellValue(totalHours),
          IntCellValue(qty),
          supQty is int ? IntCellValue(supQty) : TextCellValue('$supQty'),
          IntCellValue(diff),
          TextCellValue(status),
          TextCellValue(verifiedBy.isEmpty ? '-' : verifiedBy),
          TextCellValue(verifiedAtFormatted),
          TextCellValue(remarks),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate Excel bytes');

      final fileName =
          'production_${groupBy.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      if (kIsWeb) {
        await WebDownloadHelper.download(
          bytes,
          fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      } else {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/$fileName';
        final file = io.File(path);
        await file.writeAsBytes(bytes);

        if (mounted) {
          await share_plus.Share.shareXFiles([
            share_plus.XFile(path),
          ], text: 'Production Export ($groupBy)');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export successful!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportMasterData() async {
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Items & Operations');

      // 1. Items & Operations Sheet
      final itemsSheet = excel['Items & Operations'];
      itemsSheet.appendRow([
        TextCellValue('Item ID'),
        TextCellValue('Item Name'),
        TextCellValue('Operation Name'),
        TextCellValue('Target'),
        TextCellValue('Description'),
      ]);

      final itemsResp = await _supabase
          .from('items')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('item_id', ascending: true);

      for (var item in itemsResp) {
        final ops = (item['operation_details'] as List? ?? []);
        if (ops.isEmpty) {
          itemsSheet.appendRow([
            TextCellValue(item['item_id']?.toString() ?? ''),
            TextCellValue(item['name']?.toString() ?? ''),
            TextCellValue('N/A'),
            const IntCellValue(0),
            TextCellValue(item['description']?.toString() ?? ''),
          ]);
        } else {
          for (var op in ops) {
            itemsSheet.appendRow([
              TextCellValue(item['item_id']?.toString() ?? ''),
              TextCellValue(item['name']?.toString() ?? ''),
              TextCellValue(op['name']?.toString() ?? ''),
              IntCellValue(op['target'] ?? 0),
              TextCellValue(item['description']?.toString() ?? ''),
            ]);
          }
        }
      }

      // 2. Machines Sheet
      final machinesSheet = excel['Machines'];
      machinesSheet.appendRow([
        TextCellValue('Machine ID'),
        TextCellValue('Machine Name'),
        TextCellValue('Type'),
        TextCellValue('Status'),
        TextCellValue('Last Maintenance'),
      ]);

      final machinesResp = await _supabase
          .from('machines')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('machine_id', ascending: true);

      for (var machine in machinesResp) {
        machinesSheet.appendRow([
          TextCellValue(machine['machine_id']?.toString() ?? ''),
          TextCellValue(machine['name']?.toString() ?? ''),
          TextCellValue(machine['type']?.toString() ?? ''),
          TextCellValue(machine['status']?.toString() ?? 'Active'),
          TextCellValue(machine['last_maintenance']?.toString() ?? 'N/A'),
        ]);
      }

      // 3. Employees Sheet
      final employeesSheet = excel['Employees'];
      employeesSheet.appendRow([
        TextCellValue('Worker ID'),
        TextCellValue('Name'),
        TextCellValue('Role'),
        TextCellValue('Phone'),
        TextCellValue('Status'),
      ]);

      final employeesResp = await _supabase
          .from('workers')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);

      for (var employee in employeesResp) {
        employeesSheet.appendRow([
          TextCellValue(employee['worker_id']?.toString() ?? ''),
          TextCellValue(employee['name']?.toString() ?? ''),
          TextCellValue(employee['role']?.toString() ?? ''),
          TextCellValue(employee['phone']?.toString() ?? ''),
          TextCellValue(employee['status']?.toString() ?? 'Active'),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate Excel bytes');

      final fileName =
          'Master_Data_${widget.organizationCode}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      if (kIsWeb) {
        await WebDownloadHelper.download(
          bytes,
          fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      } else {
        // Mobile/Desktop: Save to file then share
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/$fileName';
        final file = io.File(path);
        await file.writeAsBytes(bytes);

        if (mounted) {
          await share_plus.Share.shareXFiles([
            share_plus.XFile(path),
          ], text: 'Factory Master Data Export (Items, Machines, Employees)');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master data export successful!')),
        );
      }
    } catch (e) {
      debugPrint('Master data export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<Map<String, dynamic>> _aggregateByGroup(
    String groupBy,
    List<Map<String, dynamic>> logs,
  ) {
    final Map<String, Map<String, dynamic>> acc = {};
    for (final l in logs) {
      final groupKey = groupBy == 'Worker'
          ? (l['worker_id'] ?? '').toString()
          : groupBy == 'Machine'
              ? (l['machine_id'] ?? '').toString()
              : groupBy == 'Item'
                  ? (l['item_id'] ?? '').toString()
                  : (l['operation'] ?? '').toString();
      final itemId = (l['item_id'] ?? '').toString();
      final operation = (l['operation'] ?? '').toString();
      final qty = (l['quantity'] ?? 0) as int;
      final diff = (l['performance_diff'] ?? 0) as int;
      final key = '$groupKey|$itemId|$operation';
      acc.putIfAbsent(
        key,
        () => {
          'group': groupKey,
          'item_id': itemId,
          'operation': operation,
          'qty': 0,
          'diff': 0,
        },
      );
      acc[key]!['qty'] = (acc[key]!['qty'] as int) + qty;
      acc[key]!['diff'] = (acc[key]!['diff'] as int) + diff;
    }
    return acc.values.toList();
  }

  Future<void> _fetchExtraUnitsTodayOrg() async {
    try {
      final now = DateTime.now();
      final dayFrom = now.subtract(const Duration(hours: 24));
      final response = await _supabase
          .from('production_logs')
          .select('performance_diff, created_at, remarks')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', dayFrom.toIso8601String());
      int sum = 0;
      for (final l in List<Map<String, dynamic>>.from(response)) {
        final diff = (l['performance_diff'] ?? 0) as int;
        if (diff > 0) sum += diff;
      }
      if (mounted) setState(() => _extraUnitsToday = sum);
    } catch (e) {
      debugPrint('Fetch org extra units today error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);

    int totalWorkerQty = 0;
    int totalSupervisorQty = 0;
    for (var log in _logs) {
      totalWorkerQty += (log['quantity'] as num? ?? 0).toInt();
      if (log['is_verified'] == true) {
        totalSupervisorQty += (log['supervisor_quantity'] as num? ?? 0).toInt();
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _fetchLogs(),
          _fetchExtraUnitsTodayOrg(),
        ]);
      },
      child: ListView(
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: Color(0xFFA9DFD8), size: 18),
                  const SizedBox(width: 12),
                  Text(
                    'Time Range',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: widget.isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filter,
                          isExpanded: true,
                          dropdownColor: cardBg,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                          ),
                          items: ['All', 'Today', 'Week', 'Month']
                              .map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            if (newValue != null) {
                              setState(() {
                                _filter = newValue;
                                _fetchLogs();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.inventory_2_outlined,
                        color: Color(0xFFA9DFD8)),
                    onPressed: _isExporting ? null : _exportMasterData,
                    tooltip: 'Export Master Data (Items, Machines, Workers)',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined,
                        color: Color(0xFFA9DFD8)),
                    onPressed: _isExporting ? null : _showExportOptions,
                    tooltip: 'Export Reports',
                  ),
                  if (_isExporting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFA9DFD8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Metrics Grid (Simple Numbers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount:
                  MediaQuery.of(context).orientation == Orientation.landscape
                      ? 4
                      : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio:
                  MediaQuery.of(context).orientation == Orientation.landscape
                      ? 1.4
                      : 1.3,
              children: [
                _metricTile(
                  'Worker Qty',
                  '$totalWorkerQty',
                  Colors.blue.shade200,
                  Icons.person_outline,
                ),
                _metricTile(
                  'Supervisor Qty',
                  '$totalSupervisorQty',
                  Colors.green.shade200,
                  Icons.verified_user_outlined,
                ),
                _metricTile(
                  'Extra Units (24h)',
                  '$_extraUnitsToday',
                  const Color(0xFFA9DFD8),
                  Icons.trending_up,
                ),
                _metricTile(
                  'Total Logs',
                  '${_logs.length}',
                  Colors.purple.shade100,
                  Icons.list_alt,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Summary Reports (Wider Cards)
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _logs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(child: Text('No work done.')),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          final employeeName = log['employeeName'] ?? 'Unknown';
                          final itemName = log['itemName'] ?? 'Unknown';
                          final remarks = log['remarks'] as String?;

                          String workingHours = '';
                          String inOutTime = '';

                          if (log['start_time'] != null) {
                            final inT = TimeUtils.formatTo12Hour(
                              log['start_time'],
                              format: 'hh:mm a',
                            );
                            if (log['end_time'] != null) {
                              final outT = TimeUtils.formatTo12Hour(
                                log['end_time'],
                                format: 'hh:mm a',
                              );
                              inOutTime = 'In: $inT | Out: $outT';

                              try {
                                final st = TimeUtils.parseToLocal(
                                  log['start_time'],
                                );
                                final et =
                                    TimeUtils.parseToLocal(log['end_time']);
                                final duration = et.difference(st);
                                final hours = duration.inHours;
                                final minutes =
                                    duration.inMinutes.remainder(60);
                                workingHours = 'Total: ${hours}h ${minutes}m';
                              } catch (_) {}
                            } else {
                              inOutTime = 'In: $inT | Out: -';
                            }
                          }

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 12,
                            ),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            employeeName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            itemName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: subTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          TimeUtils.formatTo12Hour(
                                            log['created_at'],
                                            format: 'MMM dd',
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          TimeUtils.formatTo12Hour(
                                            log['created_at'],
                                            format: 'hh:mm a',
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: subTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _logInfoChip(
                                      Icons.settings_outlined,
                                      '${log['operation']}',
                                      const Color(0xFFA9DFD8),
                                    ),
                                    _logInfoChip(
                                      Icons.inventory_2_outlined,
                                      'Qty: ${log['quantity']}',
                                      const Color(0xFFC2EBAE),
                                    ),
                                    if (log['target'] != null)
                                      _logInfoChip(
                                        Icons.bolt_outlined,
                                        '${_computeEfficiency(log['quantity'] as int, log['target'] as int)}% Eff',
                                        Colors.amber.shade300,
                                      ),
                                  ],
                                ),
                                if (inOutTime.isNotEmpty ||
                                    workingHours.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: widget.isDarkMode
                                          ? Colors.white.withValues(alpha: 0.03)
                                          : Colors.black
                                              .withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: subTextColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (inOutTime.isNotEmpty)
                                                Text(
                                                  inOutTime,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: subTextColor,
                                                  ),
                                                ),
                                              if (workingHours.isNotEmpty)
                                                Text(
                                                  workingHours,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFA9DFD8),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (remarks != null && remarks.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10.0),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.orange
                                            .withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.chat_bubble_outline,
                                            size: 14,
                                            color: Colors.orange,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              remarks,
                                              style: const TextStyle(
                                                fontStyle: FontStyle.italic,
                                                color: Colors.orange,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if ((log['is_verified'] ?? false) == true)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.verified_user_outlined,
                                              color: Colors.green,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Verified: ${log['verified_by']}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.green,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.orange
                                                .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.pending_actions,
                                              color: Colors.orange,
                                              size: 14,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Pending Verification',
                                              style: TextStyle(
                                                color: Colors.orange,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (log['supervisor_quantity'] != null)
                                      Text(
                                        'Supervisor Qty: ${log['supervisor_quantity']}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: subTextColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class VisualisationTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const VisualisationTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<VisualisationTab> createState() => _VisualisationTabState();
}

class _VisualisationTabState extends State<VisualisationTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _weekLogs = [];
  List<Map<String, dynamic>> _monthLogs = [];
  List<Map<String, dynamic>> _extraWeekLogs = [];
  List<Map<String, dynamic>> _summaryLogs = [];
  Map<String, List<FlSpot>> _comparativeSpots = {}; // workerId -> spots
  List<String> _comparativeWorkerIds = []; // To map index to workerId
  bool _isEmployeeScope = false;
  String _linePeriod = 'Week';
  int _currentOffset = 0;
  final PageController _pageController = PageController(initialPage: 500);
  List<FlSpot> _lineSpots = [];
  String _currentRangeTitle = '';

  // Machine/Item/Operation Visualisation State
  String _selectedMachineId = 'All';
  String _selectedItemId = 'All';
  String _selectedOperation = 'All';
  List<Map<String, dynamic>> _machinesList = [];
  List<Map<String, dynamic>> _itemsList = [];
  List<String> _operationsList = [];

  @override
  void initState() {
    super.initState();
    _fetchEmployeesForDropdown();
    _fetchFilterData();
    _fetchSummaryData();
    _refreshLineData();
  }

  List<Map<String, dynamic>> get _filteredSummaryLogs {
    return _summaryLogs.where((log) {
      bool machineMatch = _selectedMachineId == 'All' ||
          log['machine_id'].toString() == _selectedMachineId;
      bool itemMatch = _selectedItemId == 'All' ||
          log['item_id'].toString() == _selectedItemId;
      bool opMatch = _selectedOperation == 'All' ||
          log['operation'].toString() == _selectedOperation;
      return machineMatch && itemMatch && opMatch;
    }).toList();
  }

  Future<void> _fetchSummaryData() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 30));

      final response = await _supabase
          .from('production_logs')
          .select('operation, item_id, machine_id, quantity, created_at')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', start.toIso8601String());

      if (mounted) {
        setState(() {
          _summaryLogs = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching summary data: $e');
    }
  }

  Future<void> _fetchFilterData() async {
    try {
      final machinesResp = await _supabase
          .from('machines')
          .select('machine_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name');
      final itemsResp = await _supabase
          .from('items')
          .select('item_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name');
      final logsResp = await _supabase
          .from('production_logs')
          .select('operation')
          .eq('organization_code', widget.organizationCode);

      final ops = (logsResp as List)
          .map((e) => e['operation']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      ops.sort();

      if (mounted) {
        setState(() {
          _machinesList = List<Map<String, dynamic>>.from(machinesResp);
          _itemsList = List<Map<String, dynamic>>.from(itemsResp);
          _operationsList = ops;
        });
      }
    } catch (e) {
      debugPrint('Error fetching filter data: $e');
    }
  }

  Future<void> _fetchEmployeesForDropdown() async {
    try {
      final response = await _supabase
          .from('workers')
          .select('worker_id, name, role')
          .eq('organization_code', widget.organizationCode)
          .neq('role', 'supervisor')
          .order('name');
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(response);
          if (_employees.isNotEmpty && _selectedEmployeeId == null) {
            _selectedEmployeeId = _employees.first['worker_id'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching employees for dropdown: $e');
    }
  }

  Widget _buildUsageChart({
    required String title,
    required List<Map<String, dynamic>> data,
    required String key,
    required Color barColor,
  }) {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;

    final top5 = data.take(5).toList();

    if (top5.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: subTextColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return _chartCard(
      title: title,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.5,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: top5.isEmpty
                    ? 10
                    : top5
                            .map((e) => (e['qty'] as num).toDouble())
                            .reduce((a, b) => a > b ? a : b) *
                        1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => cardBg,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        rod.toY.toStringAsFixed(0),
                        TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= top5.length) {
                          return const SizedBox.shrink();
                        }
                        final label = top5[index][key].toString();
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              label.length > 10
                                  ? '${label.substring(0, 8)}..'
                                  : label,
                              style: TextStyle(
                                color: subTextColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: top5.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: (entry.value['qty'] as num).toDouble(),
                        color: barColor,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...top5.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: barColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e[key].toString(),
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${e['qty']} units (${e['count']} logs)',
                      style: TextStyle(
                          color: subTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _summaryCard(
      String title, String summary, Color accentColor, IconData icon) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: TextStyle(
              color: subTextColor,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({required String title, required Widget child}) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: const Color(0xFFA9DFD8).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFFA9DFD8),
      labelStyle: TextStyle(
        color: isSelected
            ? const Color(0xFFA9DFD8)
            : (widget.isDarkMode ? Colors.white70 : Colors.black54),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      backgroundColor: widget.isDarkMode ? Colors.white10 : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? const Color(0xFFA9DFD8) : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: subTextColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: cardBg,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _computeTopItemsPerOperation(
      List<Map<String, dynamic>> logs) {
    final Map<String, Map<String, dynamic>> aggregation = {};
    for (final log in logs) {
      final op = log['operation'] ?? 'Unknown';
      final item = log['item_id'] ?? 'Unknown';
      final qty = (log['quantity'] ?? 0) as int;
      final key = '$op|$item';
      if (!aggregation.containsKey(key)) {
        aggregation[key] = {
          'operation': op,
          'item_id': item,
          'total_qty': 0,
        };
      }
      aggregation[key]!['total_qty'] += qty;
    }
    final list = aggregation.values.toList();
    list.sort((a, b) => b['total_qty'].compareTo(a['total_qty']));
    return list;
  }

  List<Map<String, dynamic>> _computeTopByKey(
      List<Map<String, dynamic>> logs, String key) {
    final Map<String, Map<String, dynamic>> aggregation = {};
    for (final log in logs) {
      final val = log[key] ?? 'Unknown';
      final qty = (log['quantity'] ?? 0) as int;
      if (!aggregation.containsKey(val)) {
        aggregation[val] = {
          key: val,
          'count': 0,
          'qty': 0,
        };
      }
      aggregation[val]!['count'] += 1;
      aggregation[val]!['qty'] += qty;
    }
    final list = aggregation.values.toList();
    list.sort((a, b) => b['qty'].compareTo(a['qty']));
    return list;
  }

  Future<void> _refreshLineData() async {
    try {
      final now = DateTime.now();
      DateTime start;
      DateTime end;

      if (_linePeriod == 'Day') {
        final date = now.add(Duration(days: _currentOffset));
        start = DateTime(date.year, date.month, date.day);
        end = start.add(const Duration(days: 1));
        _currentRangeTitle = DateFormat('MMM d, yyyy').format(start);
      } else if (_linePeriod == 'Week') {
        // Start of current week (Monday)
        final weekday = now.weekday; // 1 = Monday, ..., 7 = Sunday
        final currentWeekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        start = currentWeekStart.add(Duration(days: _currentOffset * 7));
        end = start.add(const Duration(days: 7));
        _currentRangeTitle =
            '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, yyyy').format(end.subtract(const Duration(seconds: 1)))}';
      } else if (_linePeriod == 'Month') {
        start = DateTime(now.year, now.month + _currentOffset, 1);
        end = DateTime(start.year, start.month + 1, 1);
        _currentRangeTitle = DateFormat('MMMM yyyy').format(start);
      } else {
        // Year
        start = DateTime(now.year + _currentOffset, 1, 1);
        end = DateTime(start.year + 1, 1, 1);
        _currentRangeTitle = DateFormat('yyyy').format(start);
      }

      var query = _supabase
          .from('production_logs')
          .select(
              'created_at, quantity, machine_id, item_id, operation, worker_id')
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', start.toUtc().toIso8601String())
          .lt('created_at', end.toUtc().toIso8601String());

      if (_isEmployeeScope && _selectedEmployeeId != null) {
        query = query.eq('worker_id', _selectedEmployeeId!);
      }
      if (_selectedMachineId != 'All') {
        query = query.eq('machine_id', _selectedMachineId);
      }
      if (_selectedItemId != 'All') {
        query = query.eq('item_id', _selectedItemId);
      }
      if (_selectedOperation != 'All') {
        query = query.eq('operation', _selectedOperation);
      }

      final response = await query;
      final logs = List<Map<String, dynamic>>.from(response);

      // Comparative data
      final Map<String, Map<int, double>> workerGrouped = {};
      for (final log in logs) {
        final wId = log['worker_id']?.toString() ?? 'Unknown';
        final dt = DateTime.parse(log['created_at']).toLocal();
        int index;
        if (_linePeriod == 'Day') {
          index = dt.hour;
        } else if (_linePeriod == 'Week') {
          index = dt.difference(start).inDays;
        } else if (_linePeriod == 'Month') {
          index = dt.day - 1;
        } else {
          index = dt.month - 1;
        }

        workerGrouped.putIfAbsent(wId, () => {});
        workerGrouped[wId]![index] =
            (workerGrouped[wId]![index] ?? 0) + (log['quantity'] ?? 0);
      }

      final Map<String, List<FlSpot>> compSpots = {};
      int maxIdx;
      if (_linePeriod == 'Day') {
        maxIdx = 23;
      } else if (_linePeriod == 'Week') {
        maxIdx = 6;
      } else if (_linePeriod == 'Month') {
        maxIdx = DateTime(start.year, start.month + 1, 0).day - 1;
      } else {
        maxIdx = 11;
      }

      workerGrouped.forEach((wId, groupedData) {
        final List<FlSpot> s = [];
        for (int i = 0; i <= maxIdx; i++) {
          s.add(FlSpot(i.toDouble(), groupedData[i] ?? 0));
        }
        compSpots[wId] = s;
      });

      // Group by period and create spots
      final Map<int, double> grouped = {};
      for (final log in logs) {
        final dt = DateTime.parse(log['created_at']).toLocal();
        int index;
        if (_linePeriod == 'Day') {
          index = dt.hour;
        } else if (_linePeriod == 'Week') {
          index = dt.difference(start).inDays;
        } else if (_linePeriod == 'Month') {
          index = dt.day - 1;
        } else {
          // Year - group by month (0-11)
          index = dt.month - 1;
        }
        grouped[index] = (grouped[index] ?? 0) + (log['quantity'] ?? 0);
      }

      final List<FlSpot> spots = [];
      int maxIndex;
      if (_linePeriod == 'Day') {
        maxIndex = 23;
      } else if (_linePeriod == 'Week') {
        maxIndex = 6;
      } else if (_linePeriod == 'Month') {
        // Last day of that month
        maxIndex = DateTime(start.year, start.month + 1, 0).day - 1;
      } else {
        // Year
        maxIndex = 11;
      }

      for (int i = 0; i <= maxIndex; i++) {
        spots.add(FlSpot(i.toDouble(), grouped[i] ?? 0));
      }

      if (mounted) {
        setState(() {
          _lineSpots = spots;
          _comparativeSpots = compSpots;
          _comparativeWorkerIds = compSpots.keys.toList();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing line data: $e');
    }
  }

  Future<void> _loadSelectedEmployeeCharts(String workerId) async {
    try {
      final now = DateTime.now();
      final weekStart = now.subtract(const Duration(days: 7));
      final monthStart = DateTime(now.year, now.month, 1);

      final weekResp = await _supabase
          .from('production_logs')
          .select('created_at, quantity')
          .eq('worker_id', workerId)
          .gte('created_at', weekStart.toIso8601String());

      final monthResp = await _supabase
          .from('production_logs')
          .select('created_at, quantity')
          .eq('worker_id', workerId)
          .gte('created_at', monthStart.toIso8601String());

      final extraResp = await _supabase
          .from('production_logs')
          .select('created_at, performance_diff')
          .eq('worker_id', workerId)
          .gte('created_at', weekStart.toIso8601String());

      if (mounted) {
        setState(() {
          _weekLogs = List<Map<String, dynamic>>.from(weekResp);
          _monthLogs = List<Map<String, dynamic>>.from(monthResp);
          _extraWeekLogs = List<Map<String, dynamic>>.from(extraResp);
        });
      }
    } catch (e) {
      debugPrint('Error loading employee charts: $e');
    }
  }

  List<BarChartGroupData> _buildPeriodGroups(
      List<Map<String, dynamic>> logs, String period) {
    final Map<int, double> grouped = {};
    final now = DateTime.now();
    final start = period == 'Week'
        ? now.subtract(const Duration(days: 7))
        : DateTime(now.year, now.month, 1);

    for (final log in logs) {
      final dt = DateTime.parse(log['created_at']).toLocal();
      int index = period == 'Week' ? dt.difference(start).inDays : dt.day - 1;
      grouped[index] = (grouped[index] ?? 0) + (log['quantity'] ?? 0);
    }

    final List<BarChartGroupData> groups = [];
    final int maxIndex = period == 'Week' ? 6 : 30;
    for (int i = 0; i <= maxIndex; i++) {
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: grouped[i] ?? 0,
              color: const Color(0xFFA9DFD8),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  List<BarChartGroupData> _buildExtraWeekGroups(
      List<Map<String, dynamic>> logs) {
    final Map<int, double> grouped = {};
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));

    for (final log in logs) {
      final dt = DateTime.parse(log['created_at']).toLocal();
      final index = dt.difference(start).inDays;
      final diff = (log['performance_diff'] ?? 0) as int;
      if (diff > 0) {
        grouped[index] = (grouped[index] ?? 0) + diff;
      }
    }

    final List<BarChartGroupData> groups = [];
    for (int i = 0; i <= 6; i++) {
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: grouped[i] ?? 0,
              color: Colors.amber.shade300,
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchEmployeesForDropdown();
        await _fetchFilterData();
        await _fetchSummaryData();
        await _refreshLineData();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Global Filter Section
          _chartCard(
            title: 'Filters',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterDropdown(
                        label: 'Machine',
                        value: _selectedMachineId,
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Machines')),
                          ..._machinesList.map((m) => DropdownMenuItem(
                                value: m['machine_id'].toString(),
                                child: Text(m['name'] ?? m['machine_id']),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedMachineId = v!);
                          _refreshLineData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFilterDropdown(
                        label: 'Item',
                        value: _selectedItemId,
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Items')),
                          ..._itemsList.map((i) => DropdownMenuItem(
                                value: i['item_id'].toString(),
                                child: Text(i['name'] ?? i['item_id']),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedItemId = v!);
                          _refreshLineData();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterDropdown(
                        label: 'Operation',
                        value: _selectedOperation,
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Operations')),
                          ..._operationsList.map((o) => DropdownMenuItem(
                                value: o,
                                child: Text(o),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedOperation = v!);
                          _refreshLineData();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final tops = _computeTopItemsPerOperation(_filteredSummaryLogs);
              final recent = tops.take(4).toList();
              final summary = recent.isEmpty
                  ? 'No data'
                  : recent
                      .map(
                        (e) =>
                            '${e['operation']} → ${e['item_id']} (${e['total_qty']})',
                      )
                      .join('\n');
              return _summaryCard(
                'Top Items per Operation (Last 30d)',
                summary,
                Colors.orange,
                Icons.build_circle,
              );
            },
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final topMachines =
                  _computeTopByKey(_filteredSummaryLogs, 'machine_id');
              final summary = topMachines.isEmpty
                  ? 'No data'
                  : topMachines
                      .take(4)
                      .map(
                        (e) =>
                            '${e['machine_id']} (${e['count']} logs, ${e['qty']} qty)',
                      )
                      .join('\n');
              return _summaryCard(
                'Most Used Machines (Last 30d)',
                summary,
                Colors.pink,
                Icons.precision_manufacturing,
              );
            },
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final topItems =
                  _computeTopByKey(_filteredSummaryLogs, 'item_id');
              final summary = topItems.isEmpty
                  ? 'No data'
                  : topItems
                      .take(4)
                      .map(
                        (e) =>
                            '${e['item_id']} (${e['count']} logs, ${e['qty']} qty)',
                      )
                      .join('\n');
              return _summaryCard(
                'Most Used Items (Last 30d)',
                summary,
                widget.isDarkMode ? Colors.teal : Colors.teal.shade700,
                Icons.widgets,
              );
            },
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final topOps =
                  _computeTopByKey(_filteredSummaryLogs, 'operation');
              final summary = topOps.isEmpty
                  ? 'No data'
                  : topOps
                      .take(4)
                      .map(
                        (e) =>
                            '${e['operation']} (${e['count']} logs, ${e['qty']} qty)',
                      )
                      .join('\n');
              return _summaryCard(
                'Most Performed Operations (Last 30d)',
                summary,
                widget.isDarkMode ? Colors.indigo : Colors.indigo.shade700,
                Icons.build,
              );
            },
          ),
          const SizedBox(height: 20),
          // Detailed Usage Charts
          _buildUsageChart(
            title: 'Machine Usage Analytics (Last 30d)',
            data: _computeTopByKey(_filteredSummaryLogs, 'machine_id'),
            key: 'machine_id',
            barColor: Colors.pink.shade300,
          ),
          const SizedBox(height: 12),
          _buildUsageChart(
            title: 'Item Usage Analytics (Last 30d)',
            data: _computeTopByKey(_filteredSummaryLogs, 'item_id'),
            key: 'item_id',
            barColor: Colors.teal.shade300,
          ),
          const SizedBox(height: 12),
          _buildUsageChart(
            title: 'Operation Analytics (Last 30d)',
            data: _computeTopByKey(_filteredSummaryLogs, 'operation'),
            key: 'operation',
            barColor: Colors.indigo.shade300,
          ),
          // Line chart controls
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Production Quantity Overview Filter',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: subTextColor,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: 'All Employees',
                      isSelected: !_isEmployeeScope,
                      onSelected: (v) {
                        setState(() {
                          _isEmployeeScope = false;
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Specific Employee',
                      isSelected: _isEmployeeScope,
                      onSelected: (v) {
                        setState(() {
                          _isEmployeeScope = true;
                        });
                        _refreshLineData();
                      },
                    ),
                    if (_isEmployeeScope) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: borderColor,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedEmployeeId,
                            hint: Text(
                              'Select employee',
                              style: TextStyle(
                                fontSize: 13,
                                color: subTextColor,
                              ),
                            ),
                            dropdownColor: cardBg,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            items: _employees.map((w) {
                              final id = (w['worker_id'] ?? '').toString();
                              final name = (w['name'] ?? '').toString();
                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text('$name ($id)'),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() => _selectedEmployeeId = v);
                              _refreshLineData();
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: 'Daily',
                      isSelected: _linePeriod == 'Day',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Day';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Weekly',
                      isSelected: _linePeriod == 'Week',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Week';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Monthly',
                      isSelected: _linePeriod == 'Month',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Month';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Yearly',
                      isSelected: _linePeriod == 'Year',
                      onSelected: (v) {
                        setState(() {
                          _linePeriod = 'Year';
                          _currentOffset = 0;
                          _pageController.jumpToPage(500);
                        });
                        _refreshLineData();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _chartCard(
                title: 'Production Quantity Overview',
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: textColor),
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                        Text(
                          _currentRangeTitle,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right, color: textColor),
                          onPressed: _currentOffset >= 0
                              ? null
                              : () {
                                  _pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: MediaQuery.of(context).orientation ==
                              Orientation.landscape
                          ? 16 / 6
                          : 9 / 5,
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _currentOffset = index - 500;
                          });
                          _refreshLineData();
                        },
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: LineChart(
                              LineChartData(
                                lineTouchData: LineTouchData(
                                  enabled: true,
                                  handleBuiltInTouches: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (_) => cardBg,
                                    tooltipRoundedRadius: 8,
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots
                                          .map(
                                            (s) => LineTooltipItem(
                                              s.y.toStringAsFixed(0),
                                              TextStyle(
                                                color: textColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                          .toList();
                                    },
                                  ),
                                ),
                                gridData: const FlGridData(show: false),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 32,
                                      getTitlesWidget: (value, meta) {
                                        final v = value.toInt();
                                        String text = '';
                                        if (_linePeriod == 'Day') {
                                          if (v % 6 != 0) {
                                            return const SizedBox();
                                          }
                                          final hour =
                                              v % 12 == 0 ? 12 : v % 12;
                                          final amPm = v < 12 ? 'AM' : 'PM';
                                          text = '$hour$amPm';
                                        } else if (_linePeriod == 'Week') {
                                          final days = [
                                            'Mon',
                                            'Tue',
                                            'Wed',
                                            'Thu',
                                            'Fri',
                                            'Sat',
                                            'Sun'
                                          ];
                                          if (v >= 0 && v < 7) text = days[v];
                                        } else if (_linePeriod == 'Month') {
                                          if ((v + 1) % 5 != 0) {
                                            return const SizedBox();
                                          }
                                          text = '${v + 1}';
                                        } else {
                                          // Year
                                          final months = [
                                            'Jan',
                                            'Feb',
                                            'Mar',
                                            'Apr',
                                            'May',
                                            'Jun',
                                            'Jul',
                                            'Aug',
                                            'Sep',
                                            'Oct',
                                            'Nov',
                                            'Dec'
                                          ];
                                          if (v >= 0 && v < 12) {
                                            text = months[v];
                                          }
                                        }
                                        return SideTitleWidget(
                                          meta: meta,
                                          space: 10,
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: subTextColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          value.toInt().toString(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: subTextColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _lineSpots,
                                    isCurved: true,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFA9DFD8),
                                        Color(0xFFC2EBAE)
                                      ],
                                    ),
                                    barWidth: 3,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          const Color(0xFFA9DFD8)
                                              .withValues(alpha: 0.2),
                                          const Color(0xFFA9DFD8)
                                              .withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Comparative Production Chart
          if (_comparativeSpots.isNotEmpty)
            _chartCard(
              title: 'Comparative Production by Employee',
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 6
                        : 9 / 5,
                    child: LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((s) {
                                if (s.barIndex >=
                                    _comparativeWorkerIds.length) {
                                  return LineTooltipItem(
                                    'Unknown: ${s.y.toInt()}',
                                    TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  );
                                }
                                final workerId =
                                    _comparativeWorkerIds[s.barIndex];
                                final worker = _employees.firstWhere(
                                  (w) => w['worker_id'] == workerId,
                                  orElse: () => {'name': workerId},
                                );
                                return LineTooltipItem(
                                  '${worker['name']}: ${s.y.toInt()}',
                                  TextStyle(
                                    color: s.bar.gradient?.colors.first ??
                                        textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                String text = '';
                                if (_linePeriod == 'Day') {
                                  if (v % 6 != 0) return const SizedBox();
                                  final hour = v % 12 == 0 ? 12 : v % 12;
                                  final amPm = v < 12 ? 'AM' : 'PM';
                                  text = '$hour$amPm';
                                } else if (_linePeriod == 'Week') {
                                  final days = [
                                    'Mon',
                                    'Tue',
                                    'Wed',
                                    'Thu',
                                    'Fri',
                                    'Sat',
                                    'Sun'
                                  ];
                                  if (v >= 0 && v < 7) text = days[v];
                                } else if (_linePeriod == 'Month') {
                                  if ((v + 1) % 5 != 0) return const SizedBox();
                                  text = '${v + 1}';
                                } else {
                                  final months = [
                                    'Jan',
                                    'Feb',
                                    'Mar',
                                    'Apr',
                                    'May',
                                    'Jun',
                                    'Jul',
                                    'Aug',
                                    'Sep',
                                    'Oct',
                                    'Nov',
                                    'Dec'
                                  ];
                                  if (v >= 0 && v < 12) text = months[v];
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: _comparativeSpots.entries.map((entry) {
                          final workerId = entry.key;
                          final spots = entry.value;
                          // Generate a unique color based on workerId
                          final color = Colors.primaries[
                              workerId.hashCode % Colors.primaries.length];

                          return LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            barWidth: 2,
                            gradient: LinearGradient(
                              colors: [
                                color,
                                color.withValues(alpha: 0.7),
                              ],
                            ),
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: false),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: _comparativeSpots.keys.map((wId) {
                      final worker = _employees.firstWhere(
                        (w) => w['worker_id'] == wId,
                        orElse: () => {'name': wId},
                      );
                      final color = Colors
                          .primaries[wId.hashCode % Colors.primaries.length];
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            worker['name'] ?? wId,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          // Employee selection and graphs
          if (_employees.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Efficiency Analytics Filter',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: subTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedEmployeeId,
                      hint: Text(
                        'Select employee for efficiency graphs',
                        style: TextStyle(fontSize: 13, color: subTextColor),
                      ),
                      dropdownColor: cardBg,
                      isExpanded: true,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      items: _employees.map((w) {
                        final id = (w['worker_id'] ?? '').toString();
                        final name = (w['name'] ?? '').toString();
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text('$name ($id)'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedEmployeeId = v;
                        });
                        if (v != null) {
                          _loadSelectedEmployeeCharts(v);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _chartCard(
                  title: 'Weekly Production',
                  child: AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 5
                        : 9 / 4,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: _buildPeriodGroups(_weekLogs, 'Week'),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    'D${v + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _chartCard(
                  title: 'Monthly Production',
                  child: AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 5
                        : 9 / 4,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: _buildPeriodGroups(_monthLogs, 'Month'),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 5 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    '${v + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _chartCard(
                  title: 'Weekly Extra Work',
                  child: AspectRatio(
                    aspectRatio: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 16 / 5
                        : 9 / 4,
                    child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => cardBg,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: _buildExtraWeekGroups(_extraWeekLogs),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 10,
                                  child: Text(
                                    'W${v + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subTextColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: subTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. WORKERS TAB
// ---------------------------------------------------------------------------
class EmployeesTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const EmployeesTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _employeesList = [];
  bool _isLoading = true;
  Uint8List? _newEmployeePhotoBytes;

  final _employeeIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _panController = TextEditingController();
  final _aadharController = TextEditingController();
  final _ageController = TextEditingController();
  final _mobileController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'worker';

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('workers')
          .select()
          .eq('role', 'worker')
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _employeesList = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Error: $e';
        if (msg.contains('Load failed') || msg.contains('ClientException')) {
          msg = 'Connection failed. Check your internet or ad-blocker.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  String? _getFirstNotEmpty(Map<String, dynamic> data, List<String> keys) {
    for (var key in keys) {
      final val = data[key]?.toString();
      if (val != null && val.trim().isNotEmpty) {
        return val;
      }
    }
    return null;
  }

  Future<void> _setPhotoUrl(String workerId, String? url) async {
    if (url == null || url.isEmpty) return;
    final trimmedWorkerId = workerId.trim();
    debugPrint('Updating photo_url for [$trimmedWorkerId] to $url');

    final columnsToTry = [
      'photo_url',
      'avatar_url',
      'image_url',
      'imageurl',
      'photourl',
      'picture_url',
    ];
    bool updated = false;
    String? lastError;

    for (final col in columnsToTry) {
      try {
        final res = await _supabase
            .from('workers')
            .update({col: url})
            .eq('worker_id', trimmedWorkerId)
            .eq('organization_code', widget.organizationCode.trim())
            .select();

        if ((res as List).isNotEmpty) {
          debugPrint('Successfully updated $col for $trimmedWorkerId');
          updated = true;
          break;
        } else {
          debugPrint(
            'No rows matched for $col update (worker_id: $trimmedWorkerId)',
          );
        }
      } catch (e) {
        lastError = e.toString();
        debugPrint('Failed to update $col: $lastError');
      }
    }

    if (!updated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo upload succeeded but database update failed. '
            'Tried columns: ${columnsToTry.join(", ")}. '
            'Last error: ${lastError ?? "No matching row found"}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _pickNewEmployeePhoto() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (picked != null) {
                  final bytes = await picked.readAsBytes();
                  if (mounted) {
                    setState(() {
                      _newEmployeePhotoBytes = bytes;
                    });
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a Photo'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.camera,
                );
                if (picked != null) {
                  final bytes = await picked.readAsBytes();
                  if (mounted) {
                    setState(() {
                      _newEmployeePhotoBytes = bytes;
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadToBucketWithAutoCreate(
    String bucket,
    String fileName,
    Uint8List bytes,
    String contentType,
  ) async {
    try {
      try {
        await _supabase.storage.from(bucket).uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      } on StorageException catch (se) {
        if (se.message.contains('Bucket not found') || se.statusCode == '404') {
          try {
            await _supabase.storage.createBucket(
              bucket,
              const BucketOptions(public: true),
            );
          } catch (ce) {
            debugPrint('Error creating bucket $bucket: $ce');
            throw 'Storage Error: Bucket "$bucket" is missing.\n\nPlease create a PUBLIC bucket named "$bucket" in your Supabase Storage dashboard to enable uploads.';
          }
          await _supabase.storage.from(bucket).uploadBinary(
                fileName,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: true,
                ),
              );
        } else {
          rethrow;
        }
      }
      return _supabase.storage.from(bucket).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error for bucket $bucket: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _deleteEmployee(String employeeId) async {
    try {
      // First delete associated production logs
      await _supabase
          .from('production_logs')
          .delete()
          .eq('worker_id', employeeId);

      // Then delete the worker (table is still 'workers' in DB)
      await _supabase.from('workers').delete().eq('worker_id', employeeId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee and associated logs deleted')),
        );
        _fetchEmployees();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addEmployee() async {
    // Basic validation
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    final aadharRegex = RegExp(r'^[0-9]{12}$');

    final panValue = _panController.text.trim();
    if (panValue.isNotEmpty && !panRegex.hasMatch(panValue)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid PAN Card Format')),
        );
      }
      return;
    }

    if (!_aadharController.text.contains(aadharRegex)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid Aadhar Card Format (must be 12 digits)'),
          ),
        );
      }
      return;
    }

    try {
      final trimmedId = _employeeIdController.text.trim();
      final trimmedName = _nameController.text.trim();
      final trimmedUsername = _usernameController.text.trim();
      final trimmedOrgCode = widget.organizationCode.trim();

      if (trimmedId.isEmpty || trimmedName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ID and Name are required')),
          );
        }
        return;
      }

      String? photoUrl;
      if (_newEmployeePhotoBytes != null) {
        final fileName =
            'emp_${trimmedId}_${DateTime.now().millisecondsSinceEpoch}.png';
        photoUrl = await _uploadToBucketWithAutoCreate(
          'profile_photos',
          fileName,
          _newEmployeePhotoBytes!,
          'image/png',
        );
      }
      await _supabase.from('workers').insert({
        'worker_id': trimmedId,
        'name': trimmedName,
        'pan_card': panValue.isEmpty ? null : panValue,
        'aadhar_card': _aadharController.text.trim(),
        'age': int.tryParse(_ageController.text),
        'mobile_number': _mobileController.text.trim(),
        'username': trimmedUsername,
        'password': _passwordController.text, // Note: Should hash in real app
        'organization_code': trimmedOrgCode,
        'role': 'worker',
      });

      if (photoUrl != null && photoUrl.isNotEmpty) {
        await _setPhotoUrl(trimmedId, photoUrl);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Employee added!')));
        _clearControllers();
        setState(() {
          _newEmployeePhotoBytes = null;
        });
        _fetchEmployees();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editEmployee(Map<String, dynamic> employee) async {
    final nameEditController = TextEditingController(text: employee['name']);
    final panEditController = TextEditingController(text: employee['pan_card']);
    final aadharEditController = TextEditingController(
      text: employee['aadhar_card'],
    );
    final ageEditController = TextEditingController(
      text: employee['age']?.toString(),
    );
    final mobileEditController = TextEditingController(
      text: employee['mobile_number'],
    );
    final usernameEditController = TextEditingController(
      text: employee['username'],
    );
    final passwordEditController = TextEditingController(
      text: employee['password'],
    );
    String roleEdit = 'worker';
    String? photoUrlEdit = (employee['photo_url'] ??
            employee['avatar_url'] ??
            employee['image_url'] ??
            employee['imageurl'] ??
            employee['photourl'] ??
            employee['picture_url'])
        ?.toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Edit Employee: ${employee['worker_id']}'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFormTextField(
                      controller: nameEditController,
                      label: 'Name',
                      isDarkMode: widget.isDarkMode,
                    ),
                    _buildFormTextField(
                      controller: panEditController,
                      label: 'PAN Card',
                      isDarkMode: widget.isDarkMode,
                    ),
                    _buildFormTextField(
                      controller: aadharEditController,
                      label: 'Aadhar Card',
                      isDarkMode: widget.isDarkMode,
                    ),
                    _buildFormTextField(
                      controller: ageEditController,
                      label: 'Age',
                      isDarkMode: widget.isDarkMode,
                      keyboardType: TextInputType.number,
                    ),
                    _buildFormTextField(
                      controller: mobileEditController,
                      label: 'Mobile Number',
                      isDarkMode: widget.isDarkMode,
                      keyboardType: TextInputType.phone,
                    ),
                    _buildFormTextField(
                      controller: usernameEditController,
                      label: 'Username',
                      isDarkMode: widget.isDarkMode,
                    ),
                    _buildFormTextField(
                      controller: passwordEditController,
                      label: 'Password',
                      isDarkMode: widget.isDarkMode,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: (photoUrlEdit != null &&
                                  (photoUrlEdit?.isNotEmpty ?? false))
                              ? NetworkImage(photoUrlEdit!)
                              : null,
                          child: ((photoUrlEdit ?? '').isEmpty)
                              ? const Icon(Icons.person, size: 20)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await showModalBottomSheet<void>(
                              context: ctx,
                              builder: (sheetCtx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.photo_library),
                                      title: const Text('Choose from Gallery'),
                                      onTap: () async {
                                        Navigator.pop(sheetCtx);
                                        final picker = ImagePicker();
                                        final picked = await picker.pickImage(
                                          source: ImageSource.gallery,
                                        );
                                        if (picked != null) {
                                          final bytes =
                                              await picked.readAsBytes();
                                          final fileName =
                                              'emp_${employee['worker_id']}_${DateTime.now().millisecondsSinceEpoch}.png';
                                          final url =
                                              await _uploadToBucketWithAutoCreate(
                                            'profile_photos',
                                            fileName,
                                            bytes,
                                            'image/png',
                                          );
                                          if (url != null && ctx.mounted) {
                                            setLocalState(() {
                                              photoUrlEdit = url;
                                            });
                                          }
                                        }
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.photo_camera),
                                      title: const Text('Take a Photo'),
                                      onTap: () async {
                                        Navigator.pop(sheetCtx);
                                        final picker = ImagePicker();
                                        final picked = await picker.pickImage(
                                          source: ImageSource.camera,
                                        );
                                        if (picked != null) {
                                          final bytes =
                                              await picked.readAsBytes();
                                          final fileName =
                                              'emp_${employee['worker_id']}_${DateTime.now().millisecondsSinceEpoch}.png';
                                          final url =
                                              await _uploadToBucketWithAutoCreate(
                                            'profile_photos',
                                            fileName,
                                            bytes,
                                            'image/png',
                                          );
                                          if (url != null && ctx.mounted) {
                                            setLocalState(() {
                                              photoUrlEdit = url;
                                            });
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.image),
                          label: const Text('Pick Photo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Row(children: [Text('Role: Worker')]),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final nav = Navigator.of(ctx);
                try {
                  final updateData = {
                    'name': nameEditController.text,
                    'pan_card': panEditController.text.isEmpty
                        ? null
                        : panEditController.text,
                    'aadhar_card': aadharEditController.text,
                    'age': int.tryParse(ageEditController.text),
                    'mobile_number': mobileEditController.text,
                    'username': usernameEditController.text,
                    'password': passwordEditController.text,
                    'role': roleEdit,
                  };
                  await _supabase
                      .from('workers')
                      .update(updateData)
                      .eq('worker_id', employee['worker_id'])
                      .eq('organization_code', widget.organizationCode);

                  if ((photoUrlEdit ?? '').isNotEmpty) {
                    await _setPhotoUrl(employee['worker_id'], photoUrlEdit);
                  }

                  if (mounted) {
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Employee updated!')),
                    );
                    _fetchEmployees();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearControllers() {
    _employeeIdController.clear();
    _nameController.clear();
    _panController.clear();
    _aadharController.clear();
    _ageController.clear();
    _mobileController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final subTextColor = widget.isDarkMode
        ? Colors.white70
        : Colors.black.withValues(alpha: 0.6);
    final borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);

    return RefreshIndicator(
      onRefresh: _fetchEmployees,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Add Employee Section
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.person_add_outlined,
                    color: Color(0xFFA9DFD8)),
                title: Text(
                  'Add New Employee',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                iconColor: const Color(0xFFA9DFD8),
                collapsedIconColor: subTextColor,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildFormTextField(
                          controller: _employeeIdController,
                          label: 'Employee ID',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                            controller: _nameController,
                            label: 'Name',
                            isDarkMode: widget.isDarkMode),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _panController,
                          label: 'PAN Card (Optional)',
                          isDarkMode: widget.isDarkMode,
                          hint: 'ABCDE1234F',
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _aadharController,
                          label: 'Aadhar Card',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _ageController,
                          label: 'Age',
                          isDarkMode: widget.isDarkMode,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _mobileController,
                          label: 'Mobile Number',
                          isDarkMode: widget.isDarkMode,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _usernameController,
                          label: 'Username',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _passwordController,
                          label: 'Password',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFFA9DFD8), width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    textColor.withValues(alpha: 0.05),
                                backgroundImage: _newEmployeePhotoBytes != null
                                    ? MemoryImage(_newEmployeePhotoBytes!)
                                    : null,
                                child: _newEmployeePhotoBytes == null
                                    ? Icon(Icons.person,
                                        color:
                                            subTextColor.withValues(alpha: 0.3))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickNewEmployeePhoto,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Add Photo'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFA9DFD8),
                                  side: const BorderSide(
                                      color: Color(0xFFA9DFD8)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              'Role: ',
                              style:
                                  TextStyle(color: subTextColor, fontSize: 14),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _role,
                                    dropdownColor: cardBg,
                                    style: TextStyle(
                                        color: textColor, fontSize: 14),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'worker',
                                          child: Text('Worker')),
                                      DropdownMenuItem(
                                          value: 'supervisor',
                                          child: Text('Supervisor')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _role = val);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _addEmployee,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFA9DFD8),
                              foregroundColor: widget.isDarkMode
                                  ? const Color(0xFF21222D)
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'ADD EMPLOYEE',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.people_outline,
                  color: Color(0xFFA9DFD8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Employee List',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${_employeesList.length} Total',
                style: TextStyle(
                    color: subTextColor.withValues(alpha: 0.5), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(color: Color(0xFFA9DFD8)),
            ))
          else if (_employeesList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.person_off_outlined,
                        size: 48, color: textColor.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text('No employees found',
                        style:
                            TextStyle(color: textColor.withValues(alpha: 0.3))),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _employeesList.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final employee = _employeesList[index];
                final photoUrl = _getFirstNotEmpty(employee, [
                  'photo_url',
                  'avatar_url',
                  'image_url',
                  'imageurl',
                  'photourl',
                  'picture_url',
                ]);
                return Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                const Color(0xFFA9DFD8).withValues(alpha: 0.3)),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: textColor.withValues(alpha: 0.05),
                        backgroundImage:
                            (photoUrl != null && photoUrl.isNotEmpty)
                                ? NetworkImage(photoUrl)
                                : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Icon(Icons.person,
                                color: subTextColor.withValues(alpha: 0.3),
                                size: 24)
                            : null,
                      ),
                    ),
                    title: Text(
                      employee['name'] ?? 'No Name',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 12,
                                color: subTextColor.withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                employee['worker_id'] ?? 'ID: N/A',
                                style: TextStyle(
                                  color: subTextColor.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined,
                                size: 12,
                                color: subTextColor.withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                employee['mobile_number'] ?? 'No mobile',
                                style: TextStyle(
                                  color: subTextColor.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFFA9DFD8), size: 20),
                          onPressed: () => _editEmployee(employee),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () =>
                              _deleteEmployee(employee['worker_id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2a. SUPERVISORS TAB
// ---------------------------------------------------------------------------
class SupervisorsTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const SupervisorsTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<SupervisorsTab> createState() => _SupervisorsTabState();
}

class _SupervisorsTabState extends State<SupervisorsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _list = [];
  bool _isLoading = true;
  Map<String, dynamic>? _editingSupervisor;
  Uint8List? _newSupervisorPhotoBytes;

  final _employeeIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _panController = TextEditingController();
  final _aadharController = TextEditingController();
  final _ageController = TextEditingController();
  final _mobileController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSupervisors();
  }

  Future<void> _fetchSupervisors() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('workers')
          .select()
          .eq('role', 'supervisor')
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _list = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickNewSupervisorPhoto() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (picked != null) {
                  final bytes = await picked.readAsBytes();
                  if (mounted) {
                    setState(() {
                      _newSupervisorPhotoBytes = bytes;
                    });
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a Photo'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.camera,
                );
                if (picked != null) {
                  final bytes = await picked.readAsBytes();
                  if (mounted) {
                    setState(() {
                      _newSupervisorPhotoBytes = bytes;
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadToBucketWithAutoCreate(
    String bucket,
    String fileName,
    Uint8List bytes,
    String contentType,
  ) async {
    try {
      try {
        await _supabase.storage.from(bucket).uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      } on StorageException catch (se) {
        if (se.message.contains('Bucket not found') || se.statusCode == '404') {
          try {
            await _supabase.storage.createBucket(
              bucket,
              const BucketOptions(public: true),
            );
          } catch (ce) {
            debugPrint('Error creating bucket $bucket: $ce');
            throw 'Storage Error: Bucket "$bucket" is missing.\n\nPlease create a PUBLIC bucket named "$bucket" in your Supabase Storage dashboard to enable uploads.';
          }
          await _supabase.storage.from(bucket).uploadBinary(
                fileName,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: true,
                ),
              );
        } else {
          rethrow;
        }
      }
      return _supabase.storage.from(bucket).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error for bucket $bucket: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
      return null;
    }
  }

  String? _getFirstNotEmpty(Map<String, dynamic> data, List<String> keys) {
    for (var key in keys) {
      final val = data[key]?.toString();
      if (val != null && val.trim().isNotEmpty) {
        return val;
      }
    }
    return null;
  }

  Future<void> _setPhotoUrl(String workerId, String? url) async {
    if (url == null || url.isEmpty) return;
    final trimmedWorkerId = workerId.trim();
    debugPrint('Updating supervisor photo_url for [$trimmedWorkerId] to $url');

    final columnsToTry = [
      'photo_url',
      'avatar_url',
      'image_url',
      'imageurl',
      'photourl',
      'picture_url',
    ];
    bool updated = false;
    String? lastError;

    for (final col in columnsToTry) {
      try {
        final res = await _supabase
            .from('workers')
            .update({col: url})
            .eq('worker_id', trimmedWorkerId)
            .eq('organization_code', widget.organizationCode.trim())
            .select();

        if ((res as List).isNotEmpty) {
          debugPrint(
            'Successfully updated supervisor $col for $trimmedWorkerId',
          );
          updated = true;
          break;
        } else {
          debugPrint(
            'No rows matched for supervisor $col update (worker_id: $trimmedWorkerId)',
          );
        }
      } catch (e) {
        lastError = e.toString();
        debugPrint('Failed to update supervisor $col: $lastError');
      }
    }

    if (!updated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Supervisor photo upload succeeded but database update failed. '
            'Tried columns: ${columnsToTry.join(", ")}. '
            'Last error: ${lastError ?? "No matching row found"}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _deleteSupervisor(String id) async {
    try {
      await _supabase.from('workers').delete().eq('worker_id', id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Supervisor deleted')));
        _fetchSupervisors();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addSupervisor() async {
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    final aadharRegex = RegExp(r'^[0-9]{12}$');
    final panValue = _panController.text.trim();
    if (panValue.isNotEmpty && !panRegex.hasMatch(panValue)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid PAN Card Format')),
        );
      }
      return;
    }
    if (!_aadharController.text.contains(aadharRegex)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid Aadhar Card Format (must be 12 digits)'),
          ),
        );
      }
      return;
    }
    try {
      final trimmedId = _employeeIdController.text.trim();
      final trimmedName = _nameController.text.trim();
      final trimmedUsername = _usernameController.text.trim();
      final trimmedOrgCode = widget.organizationCode.trim();

      if (trimmedId.isEmpty || trimmedName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ID and Name are required')),
          );
        }
        return;
      }

      String? photoUrl;
      if (_newSupervisorPhotoBytes != null) {
        final fileName =
            'sup_${trimmedId}_${DateTime.now().millisecondsSinceEpoch}.png';
        photoUrl = await _uploadToBucketWithAutoCreate(
          'profile_photos',
          fileName,
          _newSupervisorPhotoBytes!,
          'image/png',
        );
      }
      await _supabase.from('workers').insert({
        'worker_id': trimmedId,
        'name': trimmedName,
        'pan_card': panValue.isEmpty ? null : panValue,
        'aadhar_card': _aadharController.text.trim(),
        'age': int.tryParse(_ageController.text),
        'mobile_number': _mobileController.text.trim(),
        'username': trimmedUsername,
        'password': _passwordController.text,
        'organization_code': trimmedOrgCode,
        'role': 'supervisor',
      });

      if (photoUrl != null && photoUrl.isNotEmpty) {
        await _setPhotoUrl(trimmedId, photoUrl);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Supervisor added!')));
        _clearControllers();
        setState(() {
          _newSupervisorPhotoBytes = null;
        });
        _fetchSupervisors();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editSupervisor(Map<String, dynamic> sup) async {
    setState(() {
      _editingSupervisor = sup;
      _employeeIdController.text = sup['worker_id']?.toString() ?? '';
      _nameController.text = sup['name']?.toString() ?? '';
      _panController.text = sup['pan_card']?.toString() ?? '';
      _aadharController.text = sup['aadhar_card']?.toString() ?? '';
      _ageController.text = (sup['age']?.toString() ?? '');
      _mobileController.text = sup['mobile_number']?.toString() ?? '';
      _usernameController.text = sup['username']?.toString() ?? '';
      _passwordController.text = sup['password']?.toString() ?? '';
    });
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? photoUrlEdit = (sup['photo_url'] ??
                sup['avatar_url'] ??
                sup['image_url'] ??
                sup['imageurl'] ??
                sup['photourl'] ??
                sup['picture_url'])
            ?.toString();
        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            title: const Text('Edit Supervisor'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: (photoUrlEdit != null &&
                                    (photoUrlEdit?.isNotEmpty ?? false))
                                ? NetworkImage(photoUrlEdit!)
                                : null,
                            child: ((photoUrlEdit ?? '').isEmpty)
                                ? const Icon(Icons.person, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await showModalBottomSheet<void>(
                                context: ctx,
                                builder: (sheetCtx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(
                                          Icons.photo_library,
                                        ),
                                        title: const Text(
                                          'Choose from Gallery',
                                        ),
                                        onTap: () async {
                                          Navigator.pop(sheetCtx);
                                          final picker = ImagePicker();
                                          final picked = await picker.pickImage(
                                            source: ImageSource.gallery,
                                          );
                                          if (picked != null) {
                                            final bytes =
                                                await picked.readAsBytes();
                                            final fileName =
                                                'sup_${sup['worker_id']}_${DateTime.now().millisecondsSinceEpoch}.png';
                                            final url =
                                                await _uploadToBucketWithAutoCreate(
                                              'profile_photos',
                                              fileName,
                                              bytes,
                                              'image/png',
                                            );
                                            if (url != null && ctx.mounted) {
                                              setLocalState(() {
                                                photoUrlEdit = url;
                                              });
                                            }
                                          }
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.photo_camera),
                                        title: const Text('Take a Photo'),
                                        onTap: () async {
                                          Navigator.pop(sheetCtx);
                                          final picker = ImagePicker();
                                          final picked = await picker.pickImage(
                                            source: ImageSource.camera,
                                          );
                                          if (picked != null) {
                                            final bytes =
                                                await picked.readAsBytes();
                                            final fileName =
                                                'sup_${sup['worker_id']}_${DateTime.now().millisecondsSinceEpoch}.png';
                                            final url =
                                                await _uploadToBucketWithAutoCreate(
                                              'profile_photos',
                                              fileName,
                                              bytes,
                                              'image/png',
                                            );
                                            if (url != null && ctx.mounted) {
                                              setLocalState(() {
                                                photoUrlEdit = url;
                                              });
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.image),
                            label: const Text('Pick Photo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormTextField(
                        controller: _employeeIdController,
                        label: 'Supervisor ID',
                        isDarkMode: widget.isDarkMode,
                        enabled: false,
                      ),
                      _buildFormTextField(
                        controller: _nameController,
                        label: 'Name',
                        isDarkMode: widget.isDarkMode,
                      ),
                      _buildFormTextField(
                        controller: _panController,
                        label: 'PAN Card (Optional)',
                        isDarkMode: widget.isDarkMode,
                      ),
                      _buildFormTextField(
                        controller: _aadharController,
                        label: 'Aadhar Card',
                        isDarkMode: widget.isDarkMode,
                      ),
                      _buildFormTextField(
                        controller: _ageController,
                        label: 'Age',
                        isDarkMode: widget.isDarkMode,
                        keyboardType: TextInputType.number,
                      ),
                      _buildFormTextField(
                        controller: _mobileController,
                        label: 'Mobile Number',
                        isDarkMode: widget.isDarkMode,
                        keyboardType: TextInputType.phone,
                      ),
                      _buildFormTextField(
                        controller: _usernameController,
                        label: 'Username',
                        isDarkMode: widget.isDarkMode,
                      ),
                      _buildFormTextField(
                        controller: _passwordController,
                        label: 'Password',
                        isDarkMode: widget.isDarkMode,
                      ),
                      const SizedBox(height: 10),
                      const Row(children: [Text('Role: Supervisor')]),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Basic validations (reuse from add)
                  final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
                  final aadharRegex = RegExp(r'^[0-9]{12}$');
                  final panValue = _panController.text.trim();
                  final messenger = ScaffoldMessenger.of(context);
                  if (panValue.isNotEmpty && !panRegex.hasMatch(panValue)) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Invalid PAN Card Format')),
                    );
                    return;
                  }
                  if (!_aadharController.text.contains(aadharRegex)) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Invalid Aadhar Card Format (must be 12 digits)',
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    final nav = Navigator.of(ctx);
                    final updateData = {
                      'name': _nameController.text,
                      'pan_card': panValue.isEmpty ? null : panValue,
                      'aadhar_card': _aadharController.text,
                      'age': int.tryParse(_ageController.text),
                      'mobile_number': _mobileController.text,
                      'username': _usernameController.text,
                      'password': _passwordController.text,
                    };
                    await _supabase
                        .from('workers')
                        .update(updateData)
                        .eq('worker_id', _editingSupervisor?['worker_id'])
                        .eq('organization_code', widget.organizationCode);

                    if ((photoUrlEdit ?? '').isNotEmpty) {
                      await _setPhotoUrl(
                        _editingSupervisor?['worker_id'] ?? '',
                        photoUrlEdit,
                      );
                    }

                    if (mounted) {
                      nav.pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Supervisor updated')),
                      );
                      _editingSupervisor = null;
                      _clearControllers();
                      await _fetchSupervisors();
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _clearControllers() {
    _employeeIdController.clear();
    _nameController.clear();
    _panController.clear();
    _aadharController.clear();
    _ageController.clear();
    _mobileController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final subTextColor = widget.isDarkMode
        ? Colors.white70
        : Colors.black.withValues(alpha: 0.6);
    final borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.12);

    return RefreshIndicator(
      onRefresh: _fetchSupervisors,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Add Supervisor Section
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.person_add_outlined,
                    color: Color(0xFFA9DFD8)),
                title: Text(
                  'Add New Supervisor',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                iconColor: const Color(0xFFA9DFD8),
                collapsedIconColor: subTextColor,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildFormTextField(
                          controller: _employeeIdController,
                          label: 'Supervisor ID',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                            controller: _nameController,
                            label: 'Name',
                            isDarkMode: widget.isDarkMode),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _panController,
                          label: 'PAN Card (Optional)',
                          isDarkMode: widget.isDarkMode,
                          hint: 'ABCDE1234F',
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _aadharController,
                          label: 'Aadhar Card',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _ageController,
                          label: 'Age',
                          isDarkMode: widget.isDarkMode,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _mobileController,
                          label: 'Mobile Number',
                          isDarkMode: widget.isDarkMode,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _usernameController,
                          label: 'Username',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _passwordController,
                          label: 'Password',
                          isDarkMode: widget.isDarkMode,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFFA9DFD8), width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    textColor.withValues(alpha: 0.05),
                                backgroundImage:
                                    _newSupervisorPhotoBytes != null
                                        ? MemoryImage(_newSupervisorPhotoBytes!)
                                        : null,
                                child: _newSupervisorPhotoBytes == null
                                    ? Icon(Icons.person,
                                        color:
                                            subTextColor.withValues(alpha: 0.3))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickNewSupervisorPhoto,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Add Photo'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFA9DFD8),
                                  side: const BorderSide(
                                      color: Color(0xFFA9DFD8)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _addSupervisor,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFA9DFD8),
                              foregroundColor: widget.isDarkMode
                                  ? const Color(0xFF21222D)
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'ADD SUPERVISOR',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.manage_accounts_outlined,
                  color: Color(0xFFA9DFD8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Supervisor List',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${_list.length} Total',
                style: TextStyle(
                    color: subTextColor.withValues(alpha: 0.5), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(color: Color(0xFFA9DFD8)),
            ))
          else if (_list.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.person_off_outlined,
                        size: 48, color: textColor.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text('No supervisors found',
                        style:
                            TextStyle(color: textColor.withValues(alpha: 0.3))),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final supervisor = _list[index];
                final photoUrl = _getFirstNotEmpty(supervisor, [
                  'photo_url',
                  'avatar_url',
                  'image_url',
                  'imageurl',
                  'photourl',
                  'picture_url',
                ]);
                return Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                const Color(0xFFA9DFD8).withValues(alpha: 0.3)),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: textColor.withValues(alpha: 0.05),
                        backgroundImage:
                            (photoUrl != null && photoUrl.isNotEmpty)
                                ? NetworkImage(photoUrl)
                                : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Icon(Icons.person,
                                color: subTextColor.withValues(alpha: 0.3),
                                size: 24)
                            : null,
                      ),
                    ),
                    title: Text(
                      supervisor['name'] ?? 'No Name',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 12,
                                color: subTextColor.withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Text(
                              supervisor['worker_id'] ?? 'ID: N/A',
                              style: TextStyle(
                                  color: subTextColor.withValues(alpha: 0.5),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined,
                                size: 12,
                                color: subTextColor.withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Text(
                              supervisor['mobile_number'] ?? 'No mobile',
                              style: TextStyle(
                                  color: subTextColor.withValues(alpha: 0.5),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFFA9DFD8), size: 20),
                          onPressed: () => _editSupervisor(supervisor),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () =>
                              _deleteSupervisor(supervisor['worker_id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. MACHINES TAB
// ---------------------------------------------------------------------------
class MachinesTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const MachinesTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<MachinesTab> createState() => _MachinesTabState();
}

class _MachinesTabState extends State<MachinesTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;

  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController(text: 'CNC');

  Map<String, dynamic>? _editingMachine;
  List<Map<String, dynamic>> _topUsage = [];
  String _sortOption = 'default'; // 'default', 'most_used', 'least_used'

  @override
  void initState() {
    super.initState();
    _fetchMachines();
    _fetchTopUsage();
  }

  void _editMachine(Map<String, dynamic> machine) {
    setState(() {
      _editingMachine = machine;
      _idController.text = machine['machine_id'];
      _nameController.text = machine['name'];
      _typeController.text = (machine['type'] ?? '').toString();
    });
  }

  Future<void> _fetchTopUsage() async {
    try {
      final resp = await _supabase
          .from('production_logs')
          .select('machine_id, quantity')
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(500);
      final logs = List<Map<String, dynamic>>.from(resp);
      final Map<String, Map<String, int>> agg = {};
      for (final l in logs) {
        final id = (l['machine_id'] ?? '').toString();
        if (id.isEmpty) continue;
        final qty = (l['quantity'] ?? 0) as int;
        agg.putIfAbsent(id, () => {'count': 0, 'qty': 0});
        agg[id]!['count'] = (agg[id]!['count'] ?? 0) + 1;
        agg[id]!['qty'] = (agg[id]!['qty'] ?? 0) + qty;
      }
      final list = agg.entries
          .map(
            (e) => <String, dynamic>{
              'machine_id': e.key,
              'count': e.value['count'] ?? 0,
              'qty': e.value['qty'] ?? 0,
            },
          )
          .toList()
        ..sort((a, b) {
          final c = (b['count'] as int).compareTo(a['count'] as int);
          if (c != 0) return c;
          return (b['qty'] as int).compareTo(a['qty'] as int);
        });
      if (mounted) setState(() => _topUsage = list);
    } catch (_) {}
  }

  Future<void> _updateMachine() async {
    if (_editingMachine == null) return;
    try {
      await _supabase
          .from('machines')
          .update({'name': _nameController.text, 'type': _typeController.text})
          .eq('machine_id', _editingMachine!['machine_id'])
          .eq('organization_code', widget.organizationCode);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Machine updated!')));
        _clearForm();
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _clearForm() {
    setState(() {
      _editingMachine = null;
      _idController.clear();
      _nameController.clear();
      _typeController.text = 'CNC';
    });
  }

  Future<void> _fetchMachines() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('machines')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _machines = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteMachine(String id) async {
    try {
      await _supabase
          .from('machines')
          .delete()
          .eq('machine_id', id)
          .eq('organization_code', widget.organizationCode);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Machine deleted')));
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addMachine() async {
    try {
      await _supabase.from('machines').insert({
        'machine_id': _idController.text,
        'name': _nameController.text,
        'type': _typeController.text,
        'organization_code': widget.organizationCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Machine added!')));
        _idController.clear();
        _nameController.clear();
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  List<Map<String, dynamic>> get _sortedMachines {
    List<Map<String, dynamic>> list = List.from(_machines);
    if (_sortOption == 'most_used') {
      list.sort((a, b) {
        final usageA = _topUsage.firstWhere(
          (u) => u['machine_id'] == a['machine_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final usageB = _topUsage.firstWhere(
          (u) => u['machine_id'] == b['machine_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final c = (usageB['count'] as int).compareTo(usageA['count'] as int);
        if (c != 0) return c;
        return (usageB['qty'] as int).compareTo(usageA['qty'] as int);
      });
    } else if (_sortOption == 'least_used') {
      list.sort((a, b) {
        final usageA = _topUsage.firstWhere(
          (u) => u['machine_id'] == a['machine_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final usageB = _topUsage.firstWhere(
          (u) => u['machine_id'] == b['machine_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final c = (usageA['count'] as int).compareTo(usageB['count'] as int);
        if (c != 0) return c;
        return (usageA['qty'] as int).compareTo(usageB['qty'] as int);
      });
    } else {
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black
            .withValues(alpha: 0.15); // Slightly darker border for visibility
    final Color accentColor =
        widget.isDarkMode ? const Color(0xFFC2EBAE) : const Color(0xFF4CAF50);

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchMachines();
        await _fetchTopUsage();
      },
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (_topUsage.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(
                        alpha: widget.isDarkMode ? 0.2 : 0.1),
                    cardBg,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: accentColor.withValues(
                        alpha: widget.isDarkMode ? 0.2 : 0.3)),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.trending_up, color: accentColor, size: 24),
                ),
                title: Text(
                  'Most Used Machine',
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '${_topUsage.first['machine_id']} — ${_topUsage.first['count']} logs',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_topUsage.first['qty']} qty',
                    style: TextStyle(
                        color: accentColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Add/Edit Machine Section
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(
                  _editingMachine == null
                      ? Icons.add_circle_outline
                      : Icons.edit_note_outlined,
                  color: accentColor,
                ),
                title: Text(
                  _editingMachine == null ? 'Add New Machine' : 'Edit Machine',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                initiallyExpanded: _editingMachine != null,
                iconColor: accentColor,
                collapsedIconColor: subTextColor.withValues(alpha: 0.5),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildFormTextField(
                          controller: _idController,
                          label: 'Machine ID',
                          isDarkMode: widget.isDarkMode,
                          enabled: _editingMachine == null,
                          hint: 'e.g. CNC-01',
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _nameController,
                          label: 'Machine Name',
                          isDarkMode: widget.isDarkMode,
                          hint: 'e.g. Vertical Milling Machine',
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _typeController,
                          label: 'Machine Type',
                          isDarkMode: widget.isDarkMode,
                          hint: 'e.g. CNC, VMC, Manual',
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (_editingMachine != null) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _clearForm,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: subTextColor,
                                    side: BorderSide(
                                        color:
                                            textColor.withValues(alpha: 0.2)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: const Text('CANCEL'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _editingMachine == null
                                    ? _addMachine
                                    : _updateMachine,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFA9DFD8),
                                  foregroundColor: widget.isDarkMode
                                      ? const Color(0xFF21222D)
                                      : Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  _editingMachine == null
                                      ? 'ADD MACHINE'
                                      : 'UPDATE MACHINE',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Header and Sort
          Row(
            children: [
              const Icon(Icons.precision_manufacturing_outlined,
                  color: Color(0xFFA9DFD8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Machine List',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortOption,
                    dropdownColor: cardBg,
                    icon: Icon(Icons.sort, color: accentColor, size: 18),
                    style: TextStyle(color: textColor, fontSize: 13),
                    onChanged: (val) {
                      if (val != null) setState(() => _sortOption = val);
                    },
                    items: const [
                      DropdownMenuItem(
                          value: 'default', child: Text('Name (A-Z)')),
                      DropdownMenuItem(
                          value: 'most_used', child: Text('Most Used')),
                      DropdownMenuItem(
                          value: 'least_used', child: Text('Least Used')),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: CircularProgressIndicator(color: accentColor),
              ),
            )
          else if (_machines.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.precision_manufacturing_outlined,
                        size: 48, color: textColor.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text('No machines found',
                        style:
                            TextStyle(color: textColor.withValues(alpha: 0.3))),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sortedMachines.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final machine = _sortedMachines[index];
                final usage = _topUsage.firstWhere(
                  (u) => u['machine_id'] == machine['machine_id'],
                  orElse: () => {'count': 0, 'qty': 0},
                );
                return Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.precision_manufacturing,
                          color: accentColor, size: 22),
                    ),
                    title: Text(
                      machine['name'] ?? 'Unnamed Machine',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: textColor.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                machine['machine_id'] ?? 'N/A',
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Type: ${machine['type'] ?? 'N/A'}',
                              style:
                                  TextStyle(color: subTextColor, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 12,
                                color: subTextColor.withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              '${usage['count']} logs • ${usage['qty']} total qty',
                              style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              color: accentColor, size: 20),
                          onPressed: () => _editMachine(machine),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () =>
                              _deleteMachine(machine['machine_id']),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. ITEMS TAB
// ---------------------------------------------------------------------------
class ItemsTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const ItemsTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<ItemsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _isLoadingItems = true;

  // New Item Controllers
  final _itemIdController = TextEditingController();
  final _itemNameController = TextEditingController();
  List<OperationDetail> _operations = [];
  String _searchQuery = '';
  List<Map<String, dynamic>> _topItemUsage = [];
  String _sortOption = 'default'; // 'default', 'most_used', 'least_used'

  // Operation Controllers
  final _opNameController = TextEditingController();
  final _opTargetController = TextEditingController();
  PlatformFile? _opFile;
  int? _editingOperationIndex;
  Map<String, dynamic>? _editingItem;

  Future<String?> _uploadToBucketWithAutoCreate(
    String bucket,
    String fileName,
    Uint8List bytes,
    String contentType,
  ) async {
    try {
      try {
        await _supabase.storage.from(bucket).uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      } on StorageException catch (se) {
        if (se.message.contains('Bucket not found') || se.statusCode == '404') {
          // Attempt to create the bucket if it's missing
          try {
            await _supabase.storage.createBucket(
              bucket,
              const BucketOptions(public: true),
            );
          } catch (ce) {
            debugPrint('Error creating bucket $bucket: $ce');
            throw 'Storage Error: Bucket "$bucket" is missing.\n\nPlease create a PUBLIC bucket named "$bucket" in your Supabase Storage dashboard to enable uploads.';
          }

          // Retry the upload
          await _supabase.storage.from(bucket).uploadBinary(
                fileName,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: true,
                ),
              );
        } else {
          rethrow;
        }
      }
      return _supabase.storage.from(bucket).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error for bucket $bucket: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchItems();
    _fetchTopItemUsage();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final response = await _supabase
          .from('items')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(response);
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoadingItems = false);
      }
    }
  }

  Future<void> _fetchTopItemUsage() async {
    try {
      final resp = await _supabase
          .from('production_logs')
          .select('item_id, quantity')
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(500);
      final logs = List<Map<String, dynamic>>.from(resp);
      final Map<String, Map<String, int>> agg = {};
      for (final l in logs) {
        final id = (l['item_id'] ?? '').toString();
        if (id.isEmpty) continue;
        final qty = (l['quantity'] ?? 0) as int;
        agg.putIfAbsent(id, () => {'count': 0, 'qty': 0});
        agg[id]!['count'] = (agg[id]!['count'] ?? 0) + 1;
        agg[id]!['qty'] = (agg[id]!['qty'] ?? 0) + qty;
      }
      final list = agg.entries
          .map(
            (e) => <String, dynamic>{
              'item_id': e.key,
              'count': e.value['count'] ?? 0,
              'qty': e.value['qty'] ?? 0,
            },
          )
          .toList()
        ..sort((a, b) {
          final c = (b['count'] as int).compareTo(a['count'] as int);
          if (c != 0) return c;
          return (b['qty'] as int).compareTo(a['qty'] as int);
        });
      if (mounted) setState(() => _topItemUsage = list);
    } catch (_) {}
  }

  void _editItem(Map<String, dynamic> item) {
    setState(() {
      _editingItem = item;
      _editingOperationIndex = null;
      _itemIdController.text = item['item_id'];
      _itemNameController.text = item['name'];
      _operations = (item['operation_details'] as List? ?? [])
          .map(
            (op) => OperationDetail(
              name: op['name'],
              target: op['target'],
              existingUrl: op['imageUrl'],
              existingPdfUrl: op['pdfUrl'],
            ),
          )
          .toList();
    });
  }

  Future<void> _updateItem() async {
    if (_editingItem == null) return;
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Updating...')));

      List<Map<String, dynamic>> opJson = [];
      for (var op in _operations) {
        String? imageUrl = op.existingUrl;
        String? pdfUrl = op.existingPdfUrl;

        if (op.newFile != null) {
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}_${op.newFile!.name}';
          final bytes = op.newFile!.bytes ??
              await io.File(op.newFile!.path!).readAsBytes();

          final isPdf = op.newFile!.name.toLowerCase().endsWith('.pdf');
          final bucket = isPdf ? 'operation_documents' : 'operation_images';
          final contentType = isPdf ? 'application/pdf' : 'image/jpeg';

          final publicUrl = await _uploadToBucketWithAutoCreate(
            bucket,
            fileName,
            bytes,
            contentType,
          );

          if (isPdf) {
            pdfUrl = publicUrl;
          } else {
            imageUrl = publicUrl;
          }
        }

        opJson.add({
          'name': op.name,
          'target': op.target,
          'imageUrl': imageUrl,
          'pdfUrl': pdfUrl,
        });
      }

      final opNames = _operations.map((o) => o.name).toList();

      await _supabase
          .from('items')
          .update({
            'name': _itemNameController.text,
            'operation_details': opJson,
            'operations': opNames,
          })
          .eq('item_id', _editingItem!['item_id'])
          .eq('organization_code', widget.organizationCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item Updated Successfully!')),
        );
        _clearItemForm();
        _fetchItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _clearItemForm() {
    setState(() {
      _editingItem = null;
      _editingOperationIndex = null;
      _itemIdController.clear();
      _itemNameController.clear();
      _operations = [];
      _opNameController.clear();
      _opTargetController.clear();
      _opFile = null;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null) {
      if (mounted) {
        setState(() {
          _opFile = result.files.first;
        });
      }
    }
  }

  void _addOperation() {
    if (_opNameController.text.isEmpty) return;

    setState(() {
      final newOp = OperationDetail(
        name: _opNameController.text,
        target: int.tryParse(_opTargetController.text) ?? 0,
        newFile: _opFile,
        existingUrl: _editingOperationIndex != null
            ? _operations[_editingOperationIndex!].existingUrl
            : null,
        existingPdfUrl: _editingOperationIndex != null
            ? _operations[_editingOperationIndex!].existingPdfUrl
            : null,
        createdAt: _editingOperationIndex != null
            ? _operations[_editingOperationIndex!].createdAt
            : DateTime.now().toUtc().toIso8601String(),
      );

      if (_editingOperationIndex != null) {
        _operations[_editingOperationIndex!] = newOp;
        _editingOperationIndex = null;
      } else {
        _operations.add(newOp);
      }

      _opNameController.clear();
      _opTargetController.clear();
      _opFile = null;
    });
  }

  void _editOperationInList(int index) {
    final op = _operations[index];
    setState(() {
      _editingOperationIndex = index;
      _opNameController.text = op.name;
      _opTargetController.text = op.target.toString();
      _opFile = null; // Reset file when editing
    });
  }

  void _viewItemDetails(Map<String, dynamic> item) {
    final ops = (item['operation_details'] as List? ?? [])
        .map((op) => OperationDetail.fromJson(op))
        .toList();

    final Color dialogBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.6);
    final Color accentColor = AppColors.getAccent(widget.isDarkMode);
    final Color cardBg = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.1);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.layers, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? 'Unnamed Item',
                    style: TextStyle(color: textColor, fontSize: 18),
                  ),
                  Text(
                    'ID: ${item['item_id']}',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'OPERATIONS WORKFLOW',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                ...ops.asMap().entries.map(
                  (entry) {
                    final idx = entry.key;
                    final op = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFA9DFD8).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              color: Color(0xFFA9DFD8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          op.name,
                          style: TextStyle(color: textColor, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Target: ${op.target}',
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (op.imageUrl != null)
                              IconButton(
                                icon: const Icon(Icons.image_outlined,
                                    color: Color(0xFFA9DFD8), size: 20),
                                tooltip: 'View Image',
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: dialogBg,
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.network(
                                              op.imageUrl!,
                                              fit: BoxFit.contain,
                                              errorBuilder: (c, e, st) =>
                                                  Padding(
                                                padding:
                                                    const EdgeInsets.all(20.0),
                                                child: Text(
                                                  'Image failed to load',
                                                  style: TextStyle(
                                                      color: subTextColor),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: Text('CLOSE',
                                              style: TextStyle(
                                                  color: subTextColor)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            if (op.pdfUrl != null)
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_outlined,
                                    color: Colors.redAccent, size: 20),
                                tooltip: 'Open PDF',
                                onPressed: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final uri = Uri.parse(op.pdfUrl!);
                                  if (!await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  )) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to open PDF'),
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CLOSE', style: TextStyle(color: subTextColor)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _editItem(item);
            },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('EDIT ITEM'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor:
                  widget.isDarkMode ? const Color(0xFF21222D) : Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem() async {
    if (_itemIdController.text.isEmpty || _itemNameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill item details')));
      return;
    }
    if (_operations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one operation')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading...')));

      // 1. Upload files first and get URLs
      List<Map<String, dynamic>> opJson = [];
      for (var op in _operations) {
        String? imageUrl;
        String? pdfUrl;
        if (op.newFile != null) {
          try {
            final isPdf = op.newFile!.name.toLowerCase().endsWith('.pdf');
            final bucket = isPdf ? 'operation_documents' : 'operation_images';
            final contentType = isPdf ? 'application/pdf' : 'image/jpeg';
            final fileName =
                '${DateTime.now().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}_${op.newFile!.name}';

            final bytes = op.newFile!.bytes ??
                await io.File(op.newFile!.path!).readAsBytes();

            final publicUrl = await _uploadToBucketWithAutoCreate(
              bucket,
              fileName,
              bytes,
              contentType,
            );

            if (isPdf) {
              pdfUrl = publicUrl;
            } else {
              imageUrl = publicUrl;
            }
          } catch (e) {
            debugPrint('File upload failed: $e');
            rethrow; // Rethrow to show in UI
          }
        }
        opJson.add({
          'name': op.name,
          'target': op.target,
          'imageUrl': imageUrl,
          'pdfUrl': pdfUrl,
        });
      }

      // 2. Insert Item
      final opNames = _operations.map((o) => o.name).toList();

      await _supabase.from('items').insert({
        'item_id': _itemIdController.text,
        'name': _itemNameController.text,
        'operation_details': opJson,
        'operations': opNames,
        'organization_code': widget.organizationCode,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item Added Successfully!')),
        );
        _itemIdController.clear();
        _itemNameController.clear();
        setState(() => _operations = []);
        _fetchItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await _supabase
          .from('items')
          .delete()
          .eq('item_id', id)
          .eq('organization_code', widget.organizationCode);
      if (mounted) {
        _fetchItems();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  List<Map<String, dynamic>> get _sortedItems {
    List<Map<String, dynamic>> list = _items.where((it) {
      final name = (it['name'] ?? '').toString().toLowerCase();
      final id = (it['item_id'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();

    if (_sortOption == 'most_used') {
      list.sort((a, b) {
        final usageA = _topItemUsage.firstWhere(
          (u) => u['item_id'] == a['item_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final usageB = _topItemUsage.firstWhere(
          (u) => u['item_id'] == b['item_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final c = (usageB['count'] as int).compareTo(usageA['count'] as int);
        if (c != 0) return c;
        return (usageB['qty'] as int).compareTo(usageA['qty'] as int);
      });
    } else if (_sortOption == 'least_used') {
      list.sort((a, b) {
        final usageA = _topItemUsage.firstWhere(
          (u) => u['item_id'] == a['item_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final usageB = _topItemUsage.firstWhere(
          (u) => u['item_id'] == b['item_id'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final c = (usageA['count'] as int).compareTo(usageB['count'] as int);
        if (c != 0) return c;
        return (usageA['qty'] as int).compareTo(usageB['qty'] as int);
      });
    } else {
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black
            .withValues(alpha: 0.15); // Slightly darker border for visibility
    final Color accentColor =
        widget.isDarkMode ? const Color(0xFFC2EBAE) : const Color(0xFF4CAF50);
    final Color secondaryAccentColor =
        widget.isDarkMode ? const Color(0xFFA9DFD8) : const Color(0xFF2E8B57);

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchItems();
        await _fetchTopItemUsage();
      },
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (_topItemUsage.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    secondaryAccentColor.withValues(
                        alpha: widget.isDarkMode ? 0.2 : 0.1),
                    cardBg,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: secondaryAccentColor.withValues(
                      alpha: widget.isDarkMode ? 0.2 : 0.3),
                ),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: secondaryAccentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.trending_up,
                      color: secondaryAccentColor, size: 24),
                ),
                title: Text(
                  'Most Used Item',
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '${_topItemUsage.first['item_id']} — ${_topItemUsage.first['count']} logs',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_topItemUsage.first['qty']} qty',
                    style: TextStyle(
                        color: secondaryAccentColor,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Add/Edit Item Section
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: accentColor,
                  brightness:
                      widget.isDarkMode ? Brightness.dark : Brightness.light,
                ),
              ),
              child: ExpansionTile(
                leading: Icon(
                  _editingItem == null
                      ? Icons.add_circle_outline
                      : Icons.edit_note_outlined,
                  color: accentColor,
                ),
                title: Text(
                  _editingItem == null ? 'Add New Item' : 'Edit Item',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                initiallyExpanded: _editingItem != null,
                iconColor: accentColor,
                collapsedIconColor: subTextColor,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFormTextField(
                          controller: _itemIdController,
                          label: 'Item ID',
                          isDarkMode: widget.isDarkMode,
                          enabled: _editingItem == null,
                          hint: 'e.g. 5001',
                        ),
                        const SizedBox(height: 12),
                        _buildFormTextField(
                          controller: _itemNameController,
                          label: 'Item Name',
                          isDarkMode: widget.isDarkMode,
                          hint: 'e.g. Polo Shirt',
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Icon(Icons.layers_outlined,
                                color: accentColor, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _editingOperationIndex == null
                                  ? 'Add Operation'
                                  : 'Edit Operation',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: textColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            children: [
                              _buildFormTextField(
                                controller: _opNameController,
                                label: 'Operation Name',
                                isDarkMode: widget.isDarkMode,
                                hint: 'e.g. Front Pocket',
                              ),
                              const SizedBox(height: 12),
                              _buildFormTextField(
                                controller: _opTargetController,
                                label: 'Target Quantity',
                                isDarkMode: widget.isDarkMode,
                                keyboardType: TextInputType.number,
                                hint: 'e.g. 100',
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickFile,
                                      icon: const Icon(Icons.attach_file,
                                          size: 18),
                                      label: Text(
                                        _opFile != null
                                            ? _opFile!.name
                                            : 'Pick Image/PDF',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: subTextColor,
                                        side: BorderSide(color: borderColor),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (_editingOperationIndex != null) ...[
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _editingOperationIndex = null;
                                            _opNameController.clear();
                                            _opTargetController.clear();
                                            _opFile = null;
                                          });
                                        },
                                        child: Text('Cancel',
                                            style:
                                                TextStyle(color: subTextColor)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton(
                                      onPressed: _addOperation,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: widget.isDarkMode
                                            ? const Color(0xFF21222D)
                                            : Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      child: Text(
                                        _editingOperationIndex == null
                                            ? 'ADD OPERATION'
                                            : 'UPDATE OPERATION',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Operations Preview
                        if (_operations.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Item Operations:',
                            style: TextStyle(
                                color: subTextColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          ..._operations.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final op = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: textColor.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${idx + 1}',
                                    style: TextStyle(
                                        color: accentColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                                title: Text(
                                  op.name,
                                  style:
                                      TextStyle(color: textColor, fontSize: 14),
                                ),
                                subtitle: Text(
                                  'Target: ${op.target}',
                                  style: TextStyle(
                                      color: subTextColor, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (op.imageUrl != null ||
                                        op.existingUrl != null ||
                                        op.newFile != null)
                                      Icon(Icons.image_outlined,
                                          size: 16, color: subTextColor),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.edit_outlined,
                                          size: 18, color: accentColor),
                                      onPressed: () =>
                                          _editOperationInList(idx),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.redAccent),
                                      onPressed: () {
                                        setState(
                                            () => _operations.removeAt(idx));
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],

                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (_editingItem != null) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _clearItemForm,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: subTextColor,
                                    side: BorderSide(color: borderColor),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: const Text('CANCEL'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _editingItem == null
                                    ? _addItem
                                    : _updateItem,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor: widget.isDarkMode
                                      ? const Color(0xFF21222D)
                                      : Colors.black,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  _editingItem == null
                                      ? 'SAVE ITEM'
                                      : 'UPDATE ITEM',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Header and Search/Sort
          Column(
            children: [
              Row(
                children: [
                  Icon(Icons.layers_outlined, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Item List',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        style: TextStyle(color: textColor, fontSize: 14),
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search items...',
                          hintStyle: TextStyle(
                              color: textColor.withValues(alpha: 0.3)),
                          border: InputBorder.none,
                          icon: Icon(Icons.search,
                              color: textColor.withValues(alpha: 0.3),
                              size: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortOption,
                        dropdownColor: cardBg,
                        icon: Icon(Icons.sort, color: accentColor, size: 18),
                        style: TextStyle(color: textColor, fontSize: 13),
                        onChanged: (val) {
                          if (val != null) setState(() => _sortOption = val);
                        },
                        items: const [
                          DropdownMenuItem(
                              value: 'default', child: Text('Name (A-Z)')),
                          DropdownMenuItem(
                              value: 'most_used', child: Text('Most Used')),
                          DropdownMenuItem(
                              value: 'least_used', child: Text('Least Used')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_isLoadingItems)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: CircularProgressIndicator(color: accentColor),
              ),
            )
          else if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.layers_outlined,
                        size: 48, color: textColor.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text('No items found',
                        style:
                            TextStyle(color: textColor.withValues(alpha: 0.3))),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sortedItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = _sortedItems[index];
                final usage = _topItemUsage.firstWhere(
                  (u) => u['item_id'] == item['item_id'],
                  orElse: () => {'count': 0, 'qty': 0},
                );
                final opCount =
                    (item['operation_details'] as List? ?? []).length;

                return Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onTap: () => _viewItemDetails(item),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.layers, color: accentColor, size: 22),
                    ),
                    title: Text(
                      item['name'] ?? 'Unnamed Item',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: textColor.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item['item_id'] ?? 'N/A',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$opCount operations',
                              style:
                                  TextStyle(color: subTextColor, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 12,
                                color: textColor.withValues(alpha: 0.3)),
                            const SizedBox(width: 4),
                            Text(
                              '${usage['count']} logs • ${usage['qty']} total qty',
                              style: TextStyle(
                                  color: textColor.withValues(alpha: 0.4),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              color: accentColor, size: 20),
                          onPressed: () => _editItem(item),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () => _deleteItem(item['item_id']),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. OPERATIONS TAB
// ---------------------------------------------------------------------------
class OperationsTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const OperationsTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<OperationsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Map<String, int> _topOperation = {};
  String _topOperationName = '';
  List<Map<String, dynamic>> _allOperationUsage = [];
  String _sortOption = 'default'; // 'default', 'most_used', 'least_used'

  @override
  void initState() {
    super.initState();
    _fetchOperations();
    _fetchTopOperationUsage();
  }

  Future<void> _fetchOperations() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('items')
          .select('item_id, name, operation_details, created_at')
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Fetch operations error: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchTopOperationUsage() async {
    try {
      final resp = await _supabase
          .from('production_logs')
          .select('operation, quantity, created_at')
          .eq('organization_code', widget.organizationCode)
          .order('created_at', ascending: false)
          .limit(1000);
      final logs = List<Map<String, dynamic>>.from(resp);
      final Map<String, Map<String, dynamic>> agg = {};
      for (final l in logs) {
        final name = (l['operation'] ?? '').toString();
        if (name.isEmpty) continue;
        final qty = (l['quantity'] ?? 0) as int;
        final createdAt = l['created_at'];

        agg.putIfAbsent(
          name,
          () => {'count': 0, 'qty': 0, 'last_produced': createdAt},
        );
        agg[name]!['count'] = (agg[name]!['count'] as int) + 1;
        agg[name]!['qty'] = (agg[name]!['qty'] as int) + qty;
      }
      final list = agg.entries
          .map(
            (e) => <String, dynamic>{
              'operation': e.key,
              'count': e.value['count'] ?? 0,
              'qty': e.value['qty'] ?? 0,
              'last_produced': e.value['last_produced'],
            },
          )
          .toList()
        ..sort((a, b) {
          final c = (b['count'] as int).compareTo(a['count'] as int);
          if (c != 0) return c;
          return (b['qty'] as int).compareTo(a['qty'] as int);
        });
      if (mounted && list.isNotEmpty) {
        setState(() {
          _allOperationUsage = list;
          _topOperationName = (list.first['operation'] ?? '').toString();
          _topOperation = {
            'count': list.first['count'] as int,
            'qty': list.first['qty'] as int,
          };
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _sortedOperations {
    List<Map<String, dynamic>> allOperations = [];
    for (var item in _items) {
      final ops = item['operation_details'] as List? ?? [];
      final itemCreatedAt = item['created_at'];
      for (var op in ops) {
        final opName = (op['name'] ?? '').toString();
        final usage = _allOperationUsage.firstWhere(
          (u) => u['operation'] == opName,
          orElse: () => {'count': 0, 'qty': 0, 'last_produced': null},
        );

        allOperations.add({
          'item_id': item['item_id'],
          'item_name': item['name'],
          'op_name': opName,
          'target': op['target'],
          'imageUrl': op['imageUrl'],
          'pdfUrl': op['pdfUrl'],
          'created_at': op['createdAt'] ?? itemCreatedAt,
          'last_produced': usage['last_produced'],
        });
      }
    }

    List<Map<String, dynamic>> filtered = allOperations.where((op) {
      final opName = op['op_name'].toString().toLowerCase();
      final itemName = op['item_name'].toString().toLowerCase();
      final itemId = op['item_id'].toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return opName.contains(query) ||
          itemName.contains(query) ||
          itemId.contains(query);
    }).toList();

    if (_sortOption == 'most_used') {
      filtered.sort((a, b) {
        final usageA = _allOperationUsage.firstWhere(
          (u) => u['operation'] == a['op_name'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final usageB = _allOperationUsage.firstWhere(
          (u) => u['operation'] == b['op_name'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final c = (usageB['count'] as int).compareTo(usageA['count'] as int);
        if (c != 0) return c;
        return (usageB['qty'] as int).compareTo(usageA['qty'] as int);
      });
    } else if (_sortOption == 'least_used') {
      filtered.sort((a, b) {
        final usageA = _allOperationUsage.firstWhere(
          (u) => u['operation'] == a['op_name'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final usageB = _allOperationUsage.firstWhere(
          (u) => u['operation'] == b['op_name'],
          orElse: () => {'count': 0, 'qty': 0},
        );
        final c = (usageA['count'] as int).compareTo(usageB['count'] as int);
        if (c != 0) return c;
        return (usageA['qty'] as int).compareTo(usageB['qty'] as int);
      });
    } else {
      filtered.sort((a, b) {
        int c = (a['op_name'] ?? '').compareTo(b['op_name'] ?? '');
        if (c != 0) return c;
        return (a['item_name'] ?? '').compareTo(b['item_name'] ?? '');
      });
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredOps = _sortedOperations;
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black
            .withValues(alpha: 0.12); // Slightly darker border for visibility
    final Color accentColor =
        widget.isDarkMode ? const Color(0xFFC2EBAE) : const Color(0xFF4CAF50);

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchOperations();
        await _fetchTopOperationUsage();
      },
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (_topOperation.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(
                        alpha: widget.isDarkMode ? 0.2 : 0.1),
                    cardBg,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor.withValues(
                      alpha: widget.isDarkMode ? 0.2 : 0.3),
                ),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome, color: accentColor, size: 24),
                ),
                title: Text(
                  'Most Performed Operation',
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    _topOperationName,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_topOperation['count']} logs',
                    style: TextStyle(
                        color: accentColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Header and Search/Sort
          Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_suggest_outlined,
                      color: Color(0xFFC2EBAE), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'All Operations',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        style: TextStyle(color: textColor, fontSize: 14),
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search operations...',
                          hintStyle: TextStyle(
                              color: subTextColor.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          icon: Icon(Icons.search,
                              color: subTextColor.withValues(alpha: 0.5),
                              size: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortOption,
                        dropdownColor: cardBg,
                        icon: const Icon(Icons.sort,
                            color: Color(0xFFC2EBAE), size: 18),
                        style: TextStyle(color: textColor, fontSize: 13),
                        onChanged: (val) {
                          if (val != null) setState(() => _sortOption = val);
                        },
                        items: const [
                          DropdownMenuItem(
                              value: 'default', child: Text('Name (A-Z)')),
                          DropdownMenuItem(
                              value: 'most_used', child: Text('Most Used')),
                          DropdownMenuItem(
                              value: 'least_used', child: Text('Least Used')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(color: Color(0xFFC2EBAE)),
              ),
            )
          else if (filteredOps.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.settings_suggest_outlined,
                        size: 48, color: textColor.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text('No operations found',
                        style: TextStyle(
                            color: subTextColor.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredOps.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final op = filteredOps[index];
                final usage = _allOperationUsage.firstWhere(
                  (u) => u['operation'] == op['op_name'],
                  orElse: () => {'count': 0, 'qty': 0},
                );

                return Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onTap: () => _showOperationDetail(op, usage),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC2EBAE).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings_suggest_outlined,
                          color: Color(0xFFC2EBAE), size: 24),
                    ),
                    title: Text(
                      op['op_name'],
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Item: ${op['item_name']} (${op['item_id']})',
                          style: TextStyle(color: subTextColor, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 12,
                                color: subTextColor.withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              '${usage['count']} logs • ${usage['qty']} qty',
                              style: TextStyle(
                                  color: subTextColor.withValues(alpha: 0.6),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (op['imageUrl'] != null)
                          Icon(Icons.image_outlined,
                              size: 18,
                              color: subTextColor.withValues(alpha: 0.5)),
                        if (op['pdfUrl'] != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.picture_as_pdf_outlined,
                              size: 18,
                              color: subTextColor.withValues(alpha: 0.5)),
                        ],
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right,
                            color: subTextColor.withValues(alpha: 0.3),
                            size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showOperationDetail(
    Map<String, dynamic> op,
    Map<String, dynamic> usage,
  ) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cardBg,
          title: Text(
            op['op_name'],
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (op['imageUrl'] != null &&
                        op['imageUrl'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => Dialog.fullscreen(
                                backgroundColor: Colors.black,
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      minScale: 0.5,
                                      maxScale: 4.0,
                                      child: Center(
                                        child: Image.network(
                                          op['imageUrl'],
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 40,
                                      right: 20,
                                      child: IconButton(
                                        icon: const Icon(Icons.close,
                                            size: 30, color: Colors.white),
                                        onPressed: () => Navigator.pop(context),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.black
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Hero(
                              tag: 'op_image_${op['imageUrl']}',
                              child: Image.network(
                                op['imageUrl'],
                                width: MediaQuery.of(context).size.width,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: textColor.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Icon(Icons.broken_image,
                                        size: 40,
                                        color:
                                            textColor.withValues(alpha: 0.2)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    _detailItem(
                        'Item Name', op['item_name'], textColor, subTextColor),
                    _detailItem(
                        'Item ID', op['item_id'], textColor, subTextColor),
                    _detailItem('Target Quantity', op['target'].toString(),
                        textColor, subTextColor),
                    if (op['created_at'] != null)
                      _detailItem(
                        'Created At',
                        DateFormat('dd MMM yyyy, hh:mm a').format(
                            DateTime.parse(op['created_at'].toString())),
                        textColor,
                        subTextColor,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Divider(color: textColor.withValues(alpha: 0.1)),
                    ),
                    const Text(
                      'Usage Statistics',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFFC2EBAE),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _detailItem('Total Logs', usage['count'].toString(),
                        textColor, subTextColor),
                    _detailItem('Total Quantity', usage['qty'].toString(),
                        textColor, subTextColor),
                    if (op['last_produced'] != null)
                      _detailItem(
                        'Last Produced',
                        DateFormat('dd MMM yyyy, hh:mm a').format(
                          DateTime.parse(op['last_produced'].toString()),
                        ),
                        textColor,
                        subTextColor,
                      ),
                    if (op['pdfUrl'] != null &&
                        op['pdfUrl'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _launchURL(op['pdfUrl']),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('VIEW PDF GUIDE'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.redAccent.withValues(alpha: 0.1),
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CLOSE',
                  style: TextStyle(
                      color: subTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _detailItem(
      String label, String value, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
                color: subTextColor, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not launch PDF')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 6. SHIFTS TAB
// ---------------------------------------------------------------------------
class ShiftsTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const ShiftsTab(
      {super.key, required this.organizationCode, required this.isDarkMode});

  @override
  State<ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<ShiftsTab> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  List<Map<String, dynamic>> _shifts = [];
  bool _isLoading = true;
  Map<String, dynamic>? _editingShift;

  @override
  void initState() {
    super.initState();
    _fetchShifts();
  }

  Future<void> _fetchShifts() async {
    setState(() => _isLoading = true);
    try {
      final resp = await _supabase
          .from('shifts')
          .select()
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _shifts = List<Map<String, dynamic>>.from(resp);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch shifts error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrUpdateShift() async {
    if (_nameController.text.isEmpty ||
        _startController.text.isEmpty ||
        _endController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    try {
      final data = {
        'name': _nameController.text,
        'start_time': _startController.text,
        'end_time': _endController.text,
        'organization_code': widget.organizationCode,
      };

      if (_editingShift == null) {
        await _supabase.from('shifts').insert(data);
      } else {
        await _supabase
            .from('shifts')
            .update(data)
            .eq('id', _editingShift!['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _editingShift == null ? 'Shift added!' : 'Shift updated!',
            ),
          ),
        );
        _clearForm();
        _fetchShifts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _editShift(Map<String, dynamic> shift) {
    setState(() {
      _editingShift = shift;
      _nameController.text = shift['name'] ?? '';
      _startController.text = shift['start_time'] ?? '';
      _endController.text = shift['end_time'] ?? '';
    });
  }

  Future<void> _deleteShift(dynamic id) async {
    try {
      await _supabase.from('shifts').delete().eq('id', id);
      _fetchShifts();
    } catch (e) {
      debugPrint('Delete shift error: $e');
    }
  }

  void _clearForm() {
    setState(() {
      _editingShift = null;
      _nameController.clear();
      _startController.clear();
      _endController.clear();
    });
  }

  Future<void> _selectTime(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final now = DateTime.now();
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      setState(() {
        controller.text = DateFormat('hh:mm a').format(dt);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    final Color borderColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);
    const Color accentColor = Color(0xFFC2EBAE);

    return RefreshIndicator(
      onRefresh: _fetchShifts,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Add/Edit Shift Section
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(
                  _editingShift == null
                      ? Icons.add_circle_outline
                      : Icons.edit_note_outlined,
                  color: accentColor,
                ),
                title: Text(
                  _editingShift == null ? 'Add New Shift' : 'Edit Shift',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                initiallyExpanded: _editingShift != null,
                iconColor: accentColor,
                collapsedIconColor: subTextColor,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFormTextField(
                          controller: _nameController,
                          label: 'Shift Name',
                          isDarkMode: widget.isDarkMode,
                          hint: 'e.g. Morning Shift',
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () =>
                                    _selectTime(context, _startController),
                                child: IgnorePointer(
                                  child: _buildFormTextField(
                                    controller: _startController,
                                    label: 'Start Time',
                                    isDarkMode: widget.isDarkMode,
                                    hint: 'Tap to select',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () =>
                                    _selectTime(context, _endController),
                                child: IgnorePointer(
                                  child: _buildFormTextField(
                                    controller: _endController,
                                    label: 'End Time',
                                    isDarkMode: widget.isDarkMode,
                                    hint: 'Tap to select',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (_editingShift != null) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _clearForm,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: subTextColor,
                                    side: BorderSide(color: borderColor),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: const Text('CANCEL'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _addOrUpdateShift,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor: widget.isDarkMode
                                      ? const Color(0xFF21222D)
                                      : Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  _editingShift == null
                                      ? 'ADD SHIFT'
                                      : 'UPDATE SHIFT',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Header
          Row(
            children: [
              const Icon(Icons.schedule_outlined, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Existing Shifts',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(color: accentColor),
              ),
            )
          else if (_shifts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.schedule_outlined,
                        size: 48, color: textColor.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text('No shifts found',
                        style: TextStyle(
                            color: subTextColor.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _shifts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final shift = _shifts[index];
                return Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.schedule,
                          color: accentColor, size: 22),
                    ),
                    title: Text(
                      shift['name'] ?? '',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Time: ${shift['start_time']} - ${shift['end_time']}',
                        style: TextStyle(color: subTextColor, fontSize: 13),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: accentColor, size: 20),
                          onPressed: () => _editShift(shift),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: cardBg,
                                title: Text('Delete Shift',
                                    style: TextStyle(color: textColor)),
                                content: Text(
                                  'Are you sure you want to delete this shift?',
                                  style: TextStyle(color: subTextColor),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text('CANCEL',
                                        style: TextStyle(color: subTextColor)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _deleteShift(shift['id']);
                                      Navigator.pop(context);
                                    },
                                    child: const Text('DELETE',
                                        style:
                                            TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );
                          },
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. SECURITY TAB
// ---------------------------------------------------------------------------
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

class _NotificationsDialog extends StatefulWidget {
  final String organizationCode;
  final VoidCallback onRead;

  const _NotificationsDialog({
    required this.organizationCode,
    required this.onRead,
  });

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<_NotificationsDialog> {
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
                          backgroundColor: n['type'] == 'out_of_bounds'
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            n['type'] == 'out_of_bounds'
                                ? Icons.exit_to_app
                                : Icons.login,
                            color: n['type'] == 'out_of_bounds'
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
