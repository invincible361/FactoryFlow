import 'dart:math';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import '../models/item.dart';
import '../utils/time_utils.dart';
import 'dart:io' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 11, vsync: this);
    _fetchOrganization();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    return Scaffold(
      appBar: AppBar(
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
                          const Icon(Icons.factory, size: 28),
                    ),
                  )
                else
                  Image.asset(
                    'assets/images/logo.png',
                    height: 28,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.factory, size: 28),
                  ),
                const SizedBox(width: 10),
                const Text('Admin Dashboard'),
              ],
            ),
            if (_ownerUsername != null && _factoryName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Welcome, ${_ownerUsername!} — ${_factoryName!}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
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
          tabs: const [
            Tab(text: 'Reports'),
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
          ReportsTab(organizationCode: widget.organizationCode),
          EmployeesTab(organizationCode: widget.organizationCode),
          SupervisorsTab(organizationCode: widget.organizationCode),
          AttendanceTab(organizationCode: widget.organizationCode),
          MachinesTab(organizationCode: widget.organizationCode),
          ItemsTab(organizationCode: widget.organizationCode),
          OperationsTab(organizationCode: widget.organizationCode),
          ShiftsTab(organizationCode: widget.organizationCode),
          ProfileTab(
            organizationCode: widget.organizationCode,
            onProfileUpdated: _fetchOrganization,
          ),
          SecurityTab(organizationCode: widget.organizationCode),
          OutOfBoundsTab(organizationCode: widget.organizationCode),
        ],
      ),
    );
  }
}

Widget _buildFormTextField({
  required TextEditingController controller,
  required String label,
  String? hint,
  TextInputType? keyboardType,
  bool enabled = true,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
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
  const ProfileTab({
    super.key,
    required this.organizationCode,
    this.onProfileUpdated,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _orgNameController;
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
          _facNameController.text = data['factory_name'] ?? '';
          _addressController.text = data['address'] ?? '';
          _latController.text = (data['latitude'] ?? 0).toString();
          _lngController.text = (data['longitude'] ?? 0).toString();
          _radiusController.text = (data['radius_meters'] ?? 500).toString();
          _passwordController.text = data['owner_password'] ?? '';
          _logoUrlController.text = data['logo_url'] ?? '';

          // Reverse calculate acres for display
          double radius = double.tryParse(_radiusController.text) ?? 500;
          _acreController.text = ((radius * radius * pi) / 4046.8564)
              .toStringAsFixed(4);

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
    final bytes =
        _logoFile!.bytes ?? await io.File(_logoFile!.path!).readAsBytes();

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
        await _supabase.storage
            .from(bucket)
            .uploadBinary(
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
          await _supabase.storage
              .from(bucket)
              .uploadBinary(
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

      await _supabase
          .from('organizations')
          .update({
            'organization_name': _orgNameController.text,
            'factory_name': _facNameController.text,
            'address': _addressController.text,
            'latitude': double.tryParse(_latController.text) ?? 0,
            'longitude': double.tryParse(_lngController.text) ?? 0,
            'radius_meters': double.tryParse(_radiusController.text) ?? 500,
            'owner_password': _passwordController.text,
            'logo_url': logoUrl,
          })
          .eq('organization_code', widget.organizationCode);

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
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Organization Profile',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _orgNameController,
              decoration: const InputDecoration(
                labelText: 'Organization Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _facNameController,
              decoration: const InputDecoration(
                labelText: 'Factory Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.factory),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_logoFile != null || _logoUrlController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _logoFile != null
                          ? (kIsWeb
                                ? Image.memory(
                                    _logoFile!.bytes!,
                                    height: 60,
                                    width: 60,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    io.File(_logoFile!.path!),
                                    height: 60,
                                    width: 60,
                                    fit: BoxFit.cover,
                                  ))
                          : Image.network(
                              _logoUrlController.text,
                              height: 60,
                              width: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, st) =>
                                  const Icon(Icons.factory, size: 60),
                            ),
                    ),
                  ),
                Expanded(
                  child: TextFormField(
                    controller: _logoUrlController,
                    decoration: InputDecoration(
                      labelText: 'Logo URL',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.image),
                      hintText: 'https://example.com/logo.png',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.upload_file),
                        onPressed: _pickLogo,
                        tooltip: 'Select Logo File',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Security',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Admin Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (v) => v!.length < 6 ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 24),
            const Text(
              'Location & Geofencing',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set your factory area in acres to automatically calculate the geofence radius.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _acreController,
                    decoration: const InputDecoration(
                      labelText: 'Factory Area (Acres)',
                      border: OutlineInputBorder(),
                      suffixText: 'Acres',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _calculateRadiusFromAcres,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _radiusController,
                    decoration: const InputDecoration(
                      labelText: 'Radius (Meters)',
                      border: OutlineInputBorder(),
                      suffixText: 'm',
                      helperText: 'Includes 15m GPS buffer',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _lngController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Factory Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Update Profile & Settings',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. OUT OF BOUNDS TAB
// ---------------------------------------------------------------------------
class OutOfBoundsTab extends StatefulWidget {
  final String organizationCode;
  const OutOfBoundsTab({super.key, required this.organizationCode});

  @override
  State<OutOfBoundsTab> createState() => _OutOfBoundsTabState();
}

class _OutOfBoundsTabState extends State<OutOfBoundsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('production_outofbounds')
          .select('*')
          .eq('organization_code', widget.organizationCode)
          .order('exit_time', ascending: false);

      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch events error: $e');
      // Fallback if production_outofbounds doesn't exist yet
      try {
        final fallback = await _supabase
            .from('worker_boundary_events')
            .select('*')
            .eq('organization_code', widget.organizationCode)
            .order('exit_time', ascending: false);
        if (mounted) {
          setState(() {
            _events = List<Map<String, dynamic>>.from(fallback);
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_events.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No "Out of Bounds" events recorded.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEvents,
      child: ListView.builder(
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final workerName =
              event['worker_name'] ??
              (event['workers'] is Map
                  ? (event['workers'] as Map)['name']
                  : 'Unknown Worker');
          final exitTime = TimeUtils.parseToLocal(event['exit_time']);
          final entryTimeStr = event['entry_time'] as String?;
          final entryTime = entryTimeStr != null
              ? TimeUtils.parseToLocal(entryTimeStr)
              : null;
          final duration = event['duration_minutes'] ?? 'Still Out';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: entryTime == null
                    ? Colors.red.shade100
                    : Colors.green.shade100,
                child: Icon(
                  entryTime == null
                      ? Icons.exit_to_app
                      : Icons.assignment_turned_in,
                  color: entryTime == null ? Colors.red : Colors.green,
                ),
              ),
              title: Text(
                workerName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exited: ${DateFormat('hh:mm a (MMM dd)').format(exitTime)}',
                  ),
                  if (entryTime != null)
                    Text(
                      'Entered: ${DateFormat('hh:mm a (MMM dd)').format(entryTime)}',
                    ),
                  Text(
                    'Duration: $duration',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: entryTime == null ? Colors.red : Colors.blue,
                    ),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.map, color: Colors.indigo),
                onPressed: () {
                  // Optional: Open maps with exit/entry coordinates
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. ATTENDANCE TAB
// ---------------------------------------------------------------------------
class AttendanceTab extends StatefulWidget {
  final String organizationCode;
  const AttendanceTab({super.key, required this.organizationCode});

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

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _fetchAttendance();
  }

  Future<void> _fetchEmployees() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode)
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
      initialDateRange:
          _selectedDateRange ??
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
            IntCellValue(0),
            IntCellValue(0),
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
        final directory = await getTemporaryDirectory();
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final fileName = 'Operator_Efficiency_$timestamp.xlsx';
        final file = io.File('${directory.path}/$fileName');
        await file.writeAsBytes(fileBytes);

        if (mounted) {
          await share_plus.Share.shareXFiles([
            share_plus.XFile(file.path),
          ], text: 'Operator Efficiency Report');
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(workerName),
            Text(
              'Attendance Detail - $dateStr',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
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
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final logs = snapshot.data ?? [];

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailSection('Shift Info', [
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
                    const Divider(),
                    const Text(
                      'Production Activity',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (logs.isEmpty)
                      const Text(
                        'No production activity recorded for this shift.',
                      )
                    else
                      ...logs.map(
                        (log) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Item: ${log['item_name'] ?? 'Unknown'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('Operation: ${log['operation']}'),
                                Text(
                                  'Machine: ${log['machine_name'] ?? 'N/A'}',
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Qty: ${log['quantity']}'),
                                    Text(
                                      'Diff: ${log['performance_diff'] >= 0 ? "+" : ""}${log['performance_diff']}',
                                      style: TextStyle(
                                        color: log['performance_diff'] >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Time: ${TimeUtils.formatTo12Hour(log['start_time'], format: 'hh:mm a')} - ${TimeUtils.formatTo12Hour(log['end_time'], format: 'hh:mm a')}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (log['remarks'] != null)
                                  Text(
                                    'Remarks: ${log['remarks']}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
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
            child: const Text('Close'),
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Daily Attendance History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportToExcel,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Export Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedEmployeeId,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Employee',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Employees'),
                        ),
                        ..._employees.map((e) {
                          return DropdownMenuItem(
                            value: e['worker_id'].toString(),
                            child: Text(e['name'].toString()),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedEmployeeId = val);
                        _fetchAttendance();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _selectDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _selectedDateRange == null
                                    ? 'Select Dates'
                                    : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_selectedDateRange != null || _selectedEmployeeId != null)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      tooltip: 'Clear Filters',
                      onPressed: () {
                        setState(() {
                          _selectedEmployeeId = null;
                          _selectedDateRange = null;
                        });
                        _fetchAttendance();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _attendance.isEmpty
            ? const Center(child: Text('No attendance records found.'))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _attendance.length,
                itemBuilder: (context, index) {
                  final record = _attendance[index];
                  final worker = record['workers'] as Map<String, dynamic>?;
                  final workerName = worker?['name'] ?? 'Unknown Worker';
                  final status = record['status'] ?? 'On Time';

                  Color statusColor = Colors.green;
                  if (status.contains('Early Leave')) {
                    statusColor = Colors.orange;
                  }
                  if (status.contains('Overtime')) statusColor = Colors.blue;
                  if (status == 'Both') statusColor = Colors.purple;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      onTap: () => _showAttendanceDetails(record),
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.1),
                        child: Icon(Icons.person, color: statusColor),
                      ),
                      title: Text(
                        workerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Date: ${record['date']} | Shift: ${record['shift_name'] ?? 'N/A'}',
                          ),
                          Text(
                            'In: ${TimeUtils.formatTo12Hour(record['check_in'], format: 'hh:mm a')} | '
                            'Out: ${TimeUtils.formatTo12Hour(record['check_out'], format: 'hh:mm a')}',
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}

class ReportsTab extends StatefulWidget {
  final String organizationCode;
  const ReportsTab({super.key, required this.organizationCode});

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
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _weekLogs = [];
  List<Map<String, dynamic>> _monthLogs = [];
  List<Map<String, dynamic>> _extraWeekLogs = [];
  int _extraUnitsToday = 0;
  bool _isEmployeeScope = false;
  String _linePeriod = 'Week';
  List<FlSpot> _lineSpots = [];

  Widget _metricTile(String title, String value, Color color, IconData icon) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        return Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.all(isLandscape ? 10 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black87, size: isLandscape ? 20 : 24),
              SizedBox(width: isLandscape ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isLandscape ? 10 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isLandscape ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
    _fetchEmployeesForDropdown();
    _fetchExtraUnitsTodayOrg();
    _refreshLineData();
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

  Future<void> _fetchEmployeesForDropdown() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select('worker_id, name')
          .eq('organization_code', widget.organizationCode)
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(resp);
        });
      }
    } catch (e) {
      debugPrint('Fetch employees for dropdown error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLogsFrom(
    DateTime from, {
    String? employeeId,
  }) async {
    if (employeeId != null) {
      final response = await _supabase
          .from('production_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .eq('worker_id', employeeId)
          .gte('created_at', from.toIso8601String())
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } else {
      final response = await _supabase
          .from('production_logs')
          .select()
          .eq('organization_code', widget.organizationCode)
          .gte('created_at', from.toIso8601String())
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<void> _loadSelectedEmployeeCharts(String employeeId) async {
    final now = DateTime.now();
    final weekFrom = now.subtract(const Duration(days: 6));
    final monthFrom = now.subtract(const Duration(days: 29));
    final extraFrom = now.subtract(const Duration(days: 7 * 8));
    try {
      final w = await _fetchLogsFrom(weekFrom, employeeId: employeeId);
      final m = await _fetchLogsFrom(monthFrom, employeeId: employeeId);
      final e = await _fetchLogsFrom(extraFrom, employeeId: employeeId);
      if (mounted) {
        setState(() {
          _weekLogs = w;
          _monthLogs = m;
          _extraWeekLogs = e;
        });
      }
    } catch (e) {
      debugPrint('Load employee charts error: $e');
    }
  }

  List<BarChartGroupData> _buildPeriodGroups(
    List<Map<String, dynamic>> logs,
    String period,
  ) {
    final now = DateTime.now();
    final List<BarChartGroupData> groups = [];
    if (period == 'Day') {
      final buckets = List<double>.filled(24, 0);
      for (final l in logs) {
        final t = DateTime.tryParse(
          (l['created_at'] ?? '').toString(),
        )?.toLocal();
        if (t != null) {
          buckets[t.hour] += (l['quantity'] ?? 0) * 1.0;
        }
      }
      for (int i = 0; i < buckets.length; i++) {
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(toY: buckets[i], color: Colors.blueAccent),
            ],
          ),
        );
      }
    } else {
      final days = period == 'Week' ? 7 : 30;
      final buckets = List<double>.filled(days, 0);
      for (final l in logs) {
        final t = DateTime.tryParse(
          (l['created_at'] ?? '').toString(),
        )?.toLocal();
        if (t != null) {
          final idx = now.difference(t).inDays;
          final pos = days - 1 - idx;
          if (pos >= 0 && pos < days) {
            buckets[pos] += (l['quantity'] ?? 0) * 1.0;
          }
        }
      }
      for (int i = 0; i < buckets.length; i++) {
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(toY: buckets[i], color: Colors.blueAccent),
            ],
          ),
        );
      }
    }
    return groups;
  }

  List<BarChartGroupData> _buildExtraWeekGroups(
    List<Map<String, dynamic>> logs,
  ) {
    final now = DateTime.now();
    final extraBuckets = List<double>.filled(8, 0);
    for (final l in logs) {
      final t = DateTime.tryParse(
        (l['created_at'] ?? '').toString(),
      )?.toLocal();
      if (t != null) {
        final wStart = DateTime(
          t.year,
          t.month,
          t.day,
        ).subtract(Duration(days: t.weekday - 1));
        final weeksAgo =
            DateTime(now.year, now.month, now.day).difference(wStart).inDays ~/
            7;
        final pos = 7 - weeksAgo;
        final diff = (l['performance_diff'] ?? 0) as int;
        if (diff > 0 && pos >= 0 && pos < 8) {
          extraBuckets[pos] += diff * 1.0;
        }
      }
    }
    return [
      for (int i = 0; i < extraBuckets.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: extraBuckets[i], color: Colors.green)],
        ),
    ];
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

  List<Map<String, dynamic>> _computeTopItemsPerOperation(
    List<Map<String, dynamic>> logs,
  ) {
    final Map<String, Map<String, int>> agg = {};
    for (final l in logs) {
      final op = (l['operation'] ?? '').toString();
      final item = (l['item_id'] ?? '').toString();
      final qty = (l['quantity'] ?? 0) as int;
      if (op.isEmpty || item.isEmpty) continue;
      agg.putIfAbsent(op, () => {});
      agg[op]![item] = (agg[op]![item] ?? 0) + qty;
    }
    final List<Map<String, dynamic>> result = [];
    agg.forEach((op, items) {
      String topItem = '';
      int topQty = 0;
      items.forEach((item, qty) {
        if (qty > topQty) {
          topQty = qty;
          topItem = item;
        }
      });
      result.add({'operation': op, 'item_id': topItem, 'total_qty': topQty});
    });
    return result;
  }

  List<Map<String, dynamic>> _computeTopByKey(
    List<Map<String, dynamic>> logs,
    String key,
  ) {
    final Map<String, Map<String, int>> agg = {};
    for (final l in logs) {
      final id = (l[key] ?? '').toString();
      if (id.isEmpty) continue;
      final qty = (l['quantity'] ?? 0) as int;
      agg.putIfAbsent(id, () => {'count': 0, 'qty': 0});
      agg[id]!['count'] = (agg[id]!['count'] ?? 0) + 1;
      agg[id]!['qty'] = (agg[id]!['qty'] ?? 0) + qty;
    }
    final list = agg.entries
        .map(
          (e) => {
            key: e.key,
            'count': e.value['count'] ?? 0,
            'qty': e.value['qty'] ?? 0,
          },
        )
        .toList();
    list.sort((a, b) {
      final c = (b['count'] as int).compareTo(a['count'] as int);
      if (c != 0) return c;
      return (b['qty'] as int).compareTo(a['qty'] as int);
    });
    return list;
  }

  // Aggregate logs: Employee -> Item -> Operation -> {qty, diff, employeeName}

  Future<void> _showExportOptions() async {
    String groupBy = 'Worker';
    String period = _filter;
    DateTimeRange? customRange;
    final Set<String> selectedWorkers = {};
    String machinesCsv = '';
    String itemsCsv = '';
    String opsCsv = '';
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Export Options'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
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
                        const Text('Group By'),
                        const SizedBox(height: 6),
                        DropdownButton<String>(
                          value: groupBy,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'Worker',
                              child: Text('Worker'),
                            ),
                            DropdownMenuItem(
                              value: 'Machine',
                              child: Text('Machine'),
                            ),
                            DropdownMenuItem(
                              value: 'Operation',
                              child: Text('Operation'),
                            ),
                            DropdownMenuItem(
                              value: 'Item',
                              child: Text('Item'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => groupBy = v ?? 'Worker'),
                        ),
                        const SizedBox(height: 12),
                        const Text('Period'),
                        const SizedBox(height: 6),
                        DropdownButton<String>(
                          value: period,
                          isExpanded: true,
                          items: ['All', 'Today', 'Week', 'Month', 'Custom']
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: (v) async {
                            if (v == null) return;
                            if (ctx.mounted) setState(() => period = v);
                            if (v == 'Custom') {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2023),
                                lastDate: DateTime.now(),
                                initialDateRange:
                                    customRange ??
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
                        if (period == 'Custom' && customRange != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              '${customRange!.start.toIso8601String().substring(0, 10)} — ${customRange!.end.toIso8601String().substring(0, 10)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        const Text('Filter (optional)'),
                        const SizedBox(height: 6),
                        ExpansionTile(
                          title: const Text('Workers'),
                          initiallyExpanded: false,
                          children: [
                            SizedBox(
                              height: 180,
                              child: ListView(
                                children: _employees.map((e) {
                                  final id = (e['worker_id'] ?? '').toString();
                                  final name = (e['name'] ?? '').toString();
                                  final checked = selectedWorkers.contains(id);
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          selectedWorkers.add(id);
                                        } else {
                                          selectedWorkers.remove(id);
                                        }
                                      });
                                    },
                                    title: Text('$name ($id)'),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Machine IDs (comma-separated)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => machinesCsv = v,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Item IDs (comma-separated)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => itemsCsv = v,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Operations (comma-separated)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => opsCsv = v,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final workerIds = selectedWorkers.toList();
                final machineIds = machinesCsv
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final itemIds = itemsCsv
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final operations = opsCsv
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
              child: const Text('Export'),
            ),
          ],
        );
      },
    );
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
          'yyyy-MM-dd hh:mm a',
        ).format(createdAtLocal);
        String verifiedAtFormatted = verifiedAtStr.isNotEmpty
            ? DateFormat(
                'yyyy-MM-dd hh:mm a',
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

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/production_${groupBy.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = io.File(path);
      await file.writeAsBytes(bytes);

      if (mounted) {
        await share_plus.Share.shareXFiles([
          share_plus.XFile(path),
        ], text: 'Production Export ($groupBy)');
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

  Future<void> _refreshLineData() async {
    try {
      final now = DateTime.now();
      DateTime from;
      int bucketsCount;
      if (_linePeriod == 'Day') {
        from = DateTime(now.year, now.month, now.day);
        bucketsCount = 24;
      } else if (_linePeriod == 'Week') {
        from = now.subtract(const Duration(days: 6));
        bucketsCount = 7;
      } else {
        from = now.subtract(const Duration(days: 29));
        bucketsCount = 30;
      }
      final logs = await _fetchLogsFrom(
        from,
        employeeId: _isEmployeeScope ? _selectedEmployeeId : null,
      );
      final buckets = List<double>.filled(bucketsCount, 0);
      for (final l in logs) {
        final t = DateTime.tryParse(
          (l['created_at'] ?? '').toString(),
        )?.toLocal();
        if (t == null) continue;
        int pos;
        if (_linePeriod == 'Day') {
          pos = t.hour;
        } else {
          final idx = now.difference(t).inDays;
          pos = bucketsCount - 1 - idx;
        }
        if (pos >= 0 && pos < bucketsCount) {
          buckets[pos] += (l['quantity'] ?? 0) * 1.0;
        }
      }
      final spots = <FlSpot>[];
      for (int i = 0; i < buckets.length; i++) {
        spots.add(FlSpot(i.toDouble(), buckets[i]));
      }
      if (mounted) setState(() => _lineSpots = spots);
    } catch (e) {
      if (mounted) setState(() => _lineSpots = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _fetchLogs(),
          _fetchEmployeesForDropdown(),
          _fetchExtraUnitsTodayOrg(),
          _refreshLineData(),
        ]);
      },
      child: ListView(
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text(
                  'Filter: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _filter,
                  items: ['All', 'Today', 'Week', 'Month'].map((String value) {
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
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.green),
                  onPressed: _isExporting ? null : _showExportOptions,
                  tooltip: 'Export to Excel',
                ),
                if (_isExporting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          // Metrics Grid
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
                  ? 2.8
                  : 2.2,
              children: [
                _metricTile(
                  'Extra Units (24h)',
                  '$_extraUnitsToday',
                  Colors.green.shade200,
                  Icons.trending_up,
                ),
                _metricTile(
                  'Employees',
                  '${_employees.length}',
                  Colors.blue.shade100,
                  Icons.people,
                ),
                Builder(
                  builder: (context) {
                    final tops = _computeTopItemsPerOperation(_logs);
                    final recent = tops.take(4).toList();
                    final summary = recent.isEmpty
                        ? 'No data'
                        : recent
                              .map(
                                (e) =>
                                    '${e['operation']} → ${e['item_id']} (${e['total_qty']})',
                              )
                              .join(' | ');
                    return _metricTile(
                      'Top Items per Operation',
                      summary,
                      Colors.orange.shade100,
                      Icons.build_circle,
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final topMachines = _computeTopByKey(_logs, 'machine_id');
                    final summary = topMachines.isEmpty
                        ? 'No data'
                        : topMachines
                              .take(4)
                              .map(
                                (e) =>
                                    '${e['machine_id']} (${e['count']} logs, ${e['qty']} qty)',
                              )
                              .join(' | ');
                    return _metricTile(
                      'Most Used Machines',
                      summary,
                      Colors.pink.shade100,
                      Icons.precision_manufacturing,
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final topItems = _computeTopByKey(_logs, 'item_id');
                    final summary = topItems.isEmpty
                        ? 'No data'
                        : topItems
                              .take(4)
                              .map(
                                (e) =>
                                    '${e['item_id']} (${e['count']} logs, ${e['qty']} qty)',
                              )
                              .join(' | ');
                    return _metricTile(
                      'Most Used Items',
                      summary,
                      Colors.teal.shade100,
                      Icons.widgets,
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final topOps = _computeTopByKey(_logs, 'operation');
                    final summary = topOps.isEmpty
                        ? 'No data'
                        : topOps
                              .take(4)
                              .map(
                                (e) =>
                                    '${e['operation']} (${e['count']} logs, ${e['qty']} qty)',
                              )
                              .join(' | ');
                    return _metricTile(
                      'Most Performed Operations',
                      summary,
                      Colors.indigo.shade100,
                      Icons.build,
                    );
                  },
                ),
              ],
            ),
          ),
          // Line chart controls
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: !_isEmployeeScope,
                          onChanged: (v) {
                            setState(() {
                              _isEmployeeScope = false;
                            });
                            _refreshLineData();
                          },
                        ),
                        const Text('All employees'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _isEmployeeScope,
                          onChanged: (v) {
                            setState(() {
                              _isEmployeeScope = true;
                            });
                            _refreshLineData();
                          },
                        ),
                        const Text('Specific employee'),
                      ],
                    ),
                    if (_isEmployeeScope)
                      DropdownButton<String>(
                        value: _selectedEmployeeId,
                        hint: const Text('Select employee'),
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
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _linePeriod == 'Day',
                          onChanged: (v) {
                            setState(() => _linePeriod = 'Day');
                            _refreshLineData();
                          },
                        ),
                        const Text('Daily'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _linePeriod == 'Week',
                          onChanged: (v) {
                            setState(() => _linePeriod = 'Week');
                            _refreshLineData();
                          },
                        ),
                        const Text('Weekly'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _linePeriod == 'Month',
                          onChanged: (v) {
                            setState(() => _linePeriod = 'Month');
                            _refreshLineData();
                          },
                        ),
                        const Text('Monthly'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height:
                      MediaQuery.of(context).orientation ==
                          Orientation.landscape
                      ? 180
                      : 240,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots
                                .map(
                                  (s) => LineTooltipItem(
                                    s.y.toStringAsFixed(0),
                                    const TextStyle(color: Colors.white),
                                  ),
                                )
                                .toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            getTitlesWidget: (value, meta) {
                              final v = value.toInt();
                              if (_linePeriod == 'Day') {
                                if (v % 3 != 0) {
                                  return const SizedBox.shrink();
                                }
                                final hour = v % 12 == 0 ? 12 : v % 12;
                                final amPm = v < 12 ? 'AM' : 'PM';
                                return Text(
                                  '$hour $amPm',
                                  style: const TextStyle(fontSize: 10),
                                );
                              } else if (_linePeriod == 'Week') {
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${v + 1}',
                                  style: const TextStyle(fontSize: 11),
                                );
                              } else {
                                if ((v + 1) % 5 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${v + 1}',
                                  style: const TextStyle(fontSize: 11),
                                );
                              }
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _lineSpots,
                          isCurved: true,
                          color: Colors.blueAccent,
                          barWidth: 3,
                          dotData: FlDotData(show: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Employee selection and graphs
          if (_employees.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  const Text(
                    'Employee: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    value: _selectedEmployeeId,
                    hint: const Text('Select employee'),
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
                ],
              ),
            ),
          if (_selectedEmployeeId != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Efficiency (Week)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height:
                        MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 180
                        : 240,
                    child: BarChart(
                      BarChartData(
                        barGroups: _buildPeriodGroups(_weekLogs, 'Week'),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${v + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Efficiency (Month)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height:
                        MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 180
                        : 240,
                    child: BarChart(
                      BarChartData(
                        barGroups: _buildPeriodGroups(_monthLogs, 'Month'),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 5 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${v + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Weekly Extra Work',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height:
                        MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 150
                        : 200,
                    child: BarChart(
                      BarChartData(
                        barGroups: _buildExtraWeekGroups(_extraWeekLogs),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (value, meta) {
                                final v = value.toInt();
                                if ((v + 1) % 2 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  'W${v + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                            final et = TimeUtils.parseToLocal(log['end_time']);
                            final duration = et.difference(st);
                            final hours = duration.inHours;
                            final minutes = duration.inMinutes.remainder(60);
                            workingHours = 'Total: ${hours}h ${minutes}m';
                          } catch (_) {}
                        } else {
                          inOutTime = 'In: $inT | Out: -';
                        }
                      }

                      return ListTile(
                        title: Text('$employeeName - $itemName'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${log['operation']} | Worker Qty: ${log['quantity']} | Supervisor Qty: ${(log['supervisor_quantity'] ?? '-')}',
                            ),
                            if (log['target'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  'Efficiency: ${_computeEfficiency(log['quantity'] as int, log['target'] as int)}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                              ),
                            if (log['start_time'] != null ||
                                log['end_time'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  'Start: ${TimeUtils.formatTo12Hour(log['start_time'], format: 'hh:mm a')} | '
                                  'End: ${TimeUtils.formatTo12Hour(log['end_time'], format: 'hh:mm a')}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            if (inOutTime.isNotEmpty)
                              Text(
                                inOutTime,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            if (workingHours.isNotEmpty)
                              Text(
                                workingHours,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 12,
                                ),
                              ),
                            if (remarks != null && remarks.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Remark: $remarks',
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              TimeUtils.formatTo12Hour(
                                log['created_at'],
                                format: 'MM/dd hh:mm a',
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            if ((log['verified_at'] ?? '') != '')
                              Text(
                                'Verified: ${TimeUtils.formatTo12Hour(log['verified_at'], format: 'MM/dd hh:mm a')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if ((log['verified_by'] ?? '') != '')
                              Text(
                                'By: ${log['verified_by']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                ),
                              ),
                            if ((log['is_verified'] ?? false) != true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange),
                                ),
                                child: const Text(
                                  'Verification Awaited',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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

// ---------------------------------------------------------------------------
// 2. WORKERS TAB
// ---------------------------------------------------------------------------
class EmployeesTab extends StatefulWidget {
  final String organizationCode;
  const EmployeesTab({super.key, required this.organizationCode});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _employeesList = [];
  bool _isLoading = true;
  XFile? _newEmployeePhotoFile;
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

        if (res != null && (res as List).isNotEmpty) {
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
                      _newEmployeePhotoFile = picked;
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
                      _newEmployeePhotoFile = picked;
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
        await _supabase.storage
            .from(bucket)
            .uploadBinary(
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
          await _supabase.storage
              .from(bucket)
              .uploadBinary(
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
          _newEmployeePhotoFile = null;
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
    String? photoUrlEdit =
        (employee['photo_url'] ??
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
                    ),
                    _buildFormTextField(
                      controller: panEditController,
                      label: 'PAN Card',
                    ),
                    _buildFormTextField(
                      controller: aadharEditController,
                      label: 'Aadhar Card',
                    ),
                    _buildFormTextField(
                      controller: ageEditController,
                      label: 'Age',
                      keyboardType: TextInputType.number,
                    ),
                    _buildFormTextField(
                      controller: mobileEditController,
                      label: 'Mobile Number',
                      keyboardType: TextInputType.phone,
                    ),
                    _buildFormTextField(
                      controller: usernameEditController,
                      label: 'Username',
                    ),
                    _buildFormTextField(
                      controller: passwordEditController,
                      label: 'Password',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey[300],
                          backgroundImage:
                              (photoUrlEdit != null &&
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
                                          final bytes = await picked
                                              .readAsBytes();
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
                                          final bytes = await picked
                                              .readAsBytes();
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
                    Row(children: const [Text('Role: Worker')]),
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
    return RefreshIndicator(
      onRefresh: _fetchEmployees,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ExpansionTile(
              title: const Text('Add New Employee'),
              children: [
                _buildFormTextField(
                  controller: _employeeIdController,
                  label: 'Employee ID',
                ),
                _buildFormTextField(controller: _nameController, label: 'Name'),
                _buildFormTextField(
                  controller: _panController,
                  label: 'PAN Card (Optional)',
                  hint: 'ABCDE1234F',
                ),
                _buildFormTextField(
                  controller: _aadharController,
                  label: 'Aadhar Card',
                ),
                _buildFormTextField(
                  controller: _ageController,
                  label: 'Age',
                  keyboardType: TextInputType.number,
                ),
                _buildFormTextField(
                  controller: _mobileController,
                  label: 'Mobile Number',
                  keyboardType: TextInputType.phone,
                ),
                _buildFormTextField(
                  controller: _usernameController,
                  label: 'Username',
                ),
                _buildFormTextField(
                  controller: _passwordController,
                  label: 'Password',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: _newEmployeePhotoBytes != null
                          ? MemoryImage(_newEmployeePhotoBytes!)
                          : null,
                      child: _newEmployeePhotoBytes == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _pickNewEmployeePhoto,
                      icon: const Icon(Icons.image),
                      label: const Text('Pick Photo'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Role: '),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _role,
                      items: const [
                        DropdownMenuItem(
                          value: 'worker',
                          child: Text('Worker'),
                        ),
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text('Supervisor'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _role = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _addEmployee,
                  child: const Text('Add Employee'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _employeesList.length,
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
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[200],
                        backgroundImage:
                            (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? const Icon(Icons.person, color: Colors.grey)
                            : null,
                      ),
                      title: Text(
                        '${employee['name']} (${employee['worker_id']})',
                      ),
                      subtitle: Text('Mobile: ${employee['mobile_number']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editEmployee(employee),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2a. SUPERVISORS TAB
// ---------------------------------------------------------------------------
class SupervisorsTab extends StatefulWidget {
  final String organizationCode;
  const SupervisorsTab({super.key, required this.organizationCode});

  @override
  State<SupervisorsTab> createState() => _SupervisorsTabState();
}

class _SupervisorsTabState extends State<SupervisorsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _list = [];
  bool _isLoading = true;
  Map<String, dynamic>? _editingSupervisor;
  XFile? _newSupervisorPhotoFile;
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
                      _newSupervisorPhotoFile = picked;
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
                      _newSupervisorPhotoFile = picked;
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
        await _supabase.storage
            .from(bucket)
            .uploadBinary(
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
          await _supabase.storage
              .from(bucket)
              .uploadBinary(
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

        if (res != null && (res as List).isNotEmpty) {
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
          _newSupervisorPhotoFile = null;
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
        String? photoUrlEdit =
            (sup['photo_url'] ??
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
                            backgroundImage:
                                (photoUrlEdit != null &&
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
                                            final bytes = await picked
                                                .readAsBytes();
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
                                            final bytes = await picked
                                                .readAsBytes();
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
                        enabled: false,
                      ),
                      _buildFormTextField(
                        controller: _nameController,
                        label: 'Name',
                      ),
                      _buildFormTextField(
                        controller: _panController,
                        label: 'PAN Card (Optional)',
                      ),
                      _buildFormTextField(
                        controller: _aadharController,
                        label: 'Aadhar Card',
                      ),
                      _buildFormTextField(
                        controller: _ageController,
                        label: 'Age',
                        keyboardType: TextInputType.number,
                      ),
                      _buildFormTextField(
                        controller: _mobileController,
                        label: 'Mobile Number',
                        keyboardType: TextInputType.phone,
                      ),
                      _buildFormTextField(
                        controller: _usernameController,
                        label: 'Username',
                      ),
                      _buildFormTextField(
                        controller: _passwordController,
                        label: 'Password',
                      ),
                      const SizedBox(height: 10),
                      Row(children: const [Text('Role: Supervisor')]),
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
    return RefreshIndicator(
      onRefresh: _fetchSupervisors,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ExpansionTile(
              title: const Text('Add New Supervisor'),
              children: [
                _buildFormTextField(
                  controller: _employeeIdController,
                  label: 'Supervisor ID',
                ),
                _buildFormTextField(controller: _nameController, label: 'Name'),
                _buildFormTextField(
                  controller: _panController,
                  label: 'PAN Card (Optional)',
                  hint: 'ABCDE1234F',
                ),
                _buildFormTextField(
                  controller: _aadharController,
                  label: 'Aadhar Card',
                ),
                _buildFormTextField(
                  controller: _ageController,
                  label: 'Age',
                  keyboardType: TextInputType.number,
                ),
                _buildFormTextField(
                  controller: _mobileController,
                  label: 'Mobile Number',
                  keyboardType: TextInputType.phone,
                ),
                _buildFormTextField(
                  controller: _usernameController,
                  label: 'Username',
                ),
                _buildFormTextField(
                  controller: _passwordController,
                  label: 'Password',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: _newSupervisorPhotoBytes != null
                          ? MemoryImage(_newSupervisorPhotoBytes!)
                          : null,
                      child: _newSupervisorPhotoBytes == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _pickNewSupervisorPhoto,
                      icon: const Icon(Icons.image),
                      label: const Text('Pick Photo'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _addSupervisor,
                      child: const Text('Add Supervisor'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _list.length,
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
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey[200],
                            backgroundImage:
                                (photoUrl != null && photoUrl.isNotEmpty)
                                ? NetworkImage(photoUrl)
                                : null,
                            child: (photoUrl == null || photoUrl.isEmpty)
                                ? const Icon(Icons.person, color: Colors.grey)
                                : null,
                          ),
                          title: Text(
                            '${supervisor['name']} (${supervisor['worker_id']})',
                          ),
                          subtitle: Text(
                            'Mobile: ${supervisor['mobile_number']}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _editSupervisor(supervisor),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. MACHINES TAB
// ---------------------------------------------------------------------------
class MachinesTab extends StatefulWidget {
  final String organizationCode;
  const MachinesTab({super.key, required this.organizationCode});

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
      final list =
          agg.entries
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          if (_topUsage.isNotEmpty)
            Card(
              color: Colors.pink.shade50,
              child: ListTile(
                leading: const Icon(Icons.trending_up, color: Colors.pink),
                title: const Text('Most Used Machine'),
                subtitle: Text(
                  '${_topUsage.first['machine_id']} (${_topUsage.first['count']} logs, ${_topUsage.first['qty']} qty)',
                ),
              ),
            ),
          ExpansionTile(
            title: Text(
              _editingMachine == null ? 'Add New Machine' : 'Edit Machine',
            ),
            initiallyExpanded: _editingMachine != null,
            children: [
              _buildFormTextField(
                controller: _idController,
                label: 'Machine ID',
                enabled: _editingMachine == null,
              ),
              _buildFormTextField(
                controller: _nameController,
                label: 'Machine Name',
              ),
              _buildFormTextField(
                controller: _typeController,
                label: 'Machine Type ',
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _editingMachine == null
                        ? _addMachine
                        : _updateMachine,
                    child: Text(
                      _editingMachine == null
                          ? 'Add Machine'
                          : 'Update Machine',
                    ),
                  ),
                  if (_editingMachine != null) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _clearForm,
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Existing Machines',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              DropdownButton<String>(
                value: _sortOption,
                onChanged: (val) {
                  if (val != null) setState(() => _sortOption = val);
                },
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('Default')),
                  DropdownMenuItem(
                    value: 'most_used',
                    child: Text('Most Used'),
                  ),
                  DropdownMenuItem(
                    value: 'least_used',
                    child: Text('Least Used'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _sortedMachines.length,
                  itemBuilder: (context, index) {
                    final machine = _sortedMachines[index];
                    final usage = _topUsage.firstWhere(
                      (u) => u['machine_id'] == machine['machine_id'],
                      orElse: () => {'count': 0, 'qty': 0},
                    );
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.precision_manufacturing),
                        title: Text(
                          '${machine['name']} (${machine['machine_id']})',
                        ),
                        subtitle: Text(
                          'Type: ${machine['type']} • Usage: ${usage['count']} logs, ${usage['qty']} qty',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editMachine(machine),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  _deleteMachine(machine['machine_id']),
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
  const ItemsTab({super.key, required this.organizationCode});

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
        await _supabase.storage
            .from(bucket)
            .uploadBinary(
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
          await _supabase.storage
              .from(bucket)
              .uploadBinary(
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
      final list =
          agg.entries
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
          final bytes =
              op.newFile!.bytes ??
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
            : DateTime.now().toIso8601String(),
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item['name']} (${item['item_id']})'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'Operations:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...ops.map(
                  (op) => ListTile(
                    title: Text(op.name),
                    subtitle: Text('Target: ${op.target}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (op.imageUrl != null)
                          IconButton(
                            icon: const Icon(Icons.image, color: Colors.blue),
                            tooltip: 'View Image',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  content: SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width * 0.9,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight:
                                            MediaQuery.of(context).size.height *
                                            0.8,
                                      ),
                                      child: Image.network(
                                        op.imageUrl!,
                                        width: MediaQuery.of(
                                          context,
                                        ).size.width,
                                        fit: BoxFit.contain,
                                        errorBuilder: (c, e, st) =>
                                            const Text('Image failed to load'),
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        if (op.pdfUrl != null)
                          IconButton(
                            icon: const Icon(
                              Icons.picture_as_pdf,
                              color: Colors.red,
                            ),
                            tooltip: 'Open PDF',
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
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
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _editItem(item);
            },
            child: const Text('Edit Item'),
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

            final bytes =
                op.newFile!.bytes ??
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
    final filteredItems = _items.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final id = (item['item_id'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          id.contains(_searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          if (_topItemUsage.isNotEmpty)
            Card(
              color: Colors.teal.shade50,
              child: ListTile(
                leading: const Icon(Icons.trending_up, color: Colors.teal),
                title: const Text('Most Used Item'),
                subtitle: Text(
                  '${_topItemUsage.first['item_id']} (${_topItemUsage.first['count']} logs, ${_topItemUsage.first['qty']} qty)',
                ),
              ),
            ),
          Text(
            _editingItem == null ? 'Add New Item' : 'Edit Item',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          _buildFormTextField(
            controller: _itemIdController,
            label: 'Item ID (e.g. 5001)',
            enabled: _editingItem == null,
          ),
          _buildFormTextField(
            controller: _itemNameController,
            label: 'Item Name (e.g. Shirt)',
          ),

          const SizedBox(height: 16),
          Text(
            _editingOperationIndex == null ? 'Operations' : 'Edit Operation',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildFormTextField(
                  controller: _opNameController,
                  label: 'Operation Name (e.g. Collar)',
                ),
                _buildFormTextField(
                  controller: _opTargetController,
                  label: 'Target Quantity',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Pick Image/PDF'),
                    ),
                    const SizedBox(width: 10),
                    if (_opFile != null)
                      Expanded(
                        child: Text(
                          _opFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _addOperation,
                      child: Text(
                        _editingOperationIndex == null
                            ? 'Add Operation'
                            : 'Update Operation',
                      ),
                    ),
                    if (_editingOperationIndex != null) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _editingOperationIndex = null;
                            _opNameController.clear();
                            _opTargetController.clear();
                            _opFile = null;
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Operation List Preview
          if (_operations.isNotEmpty) ...[
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _operations.length,
              itemBuilder: (context, index) {
                final op = _operations[index];
                return ListTile(
                  title: Text(op.name),
                  subtitle: Text('Target: ${op.target}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (op.imageUrl != null || op.existingUrl != null)
                        const Icon(Icons.image, color: Colors.blue),
                      if (op.pdfUrl != null || op.existingPdfUrl != null)
                        const Icon(Icons.picture_as_pdf, color: Colors.red),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editOperationInList(index),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          setState(() {
                            _operations.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _editingItem == null ? _addItem : _updateItem,
                child: Text(
                  _editingItem == null
                      ? 'Save Item to Database'
                      : 'Update Item',
                ),
              ),
              if (_editingItem != null) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _clearItemForm,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          const Divider(thickness: 2),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Existing Items',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    DropdownButton<String>(
                      value: _sortOption,
                      onChanged: (val) {
                        if (val != null) setState(() => _sortOption = val);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'default',
                          child: Text('Default'),
                        ),
                        DropdownMenuItem(
                          value: 'most_used',
                          child: Text('Most Used'),
                        ),
                        DropdownMenuItem(
                          value: 'least_used',
                          child: Text('Least Used'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: const InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          _isLoadingItems
              ? const Center(child: CircularProgressIndicator())
              : _sortedItems.isEmpty
              ? const Center(child: Text('No items found.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _sortedItems.length,
                  itemBuilder: (context, index) {
                    final item = _sortedItems[index];
                    final usage = _topItemUsage.firstWhere(
                      (u) => u['item_id'] == item['item_id'],
                      orElse: () => {'count': 0, 'qty': 0},
                    );
                    final ops = item['operation_details'] as List? ?? [];
                    return Card(
                      child: ListTile(
                        title: Text('${item['name']} (${item['item_id']})'),
                        subtitle: Text(
                          '${ops.length} Operations • Usage: ${usage['count']} logs, ${usage['qty']} qty',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.visibility,
                                color: Colors.green,
                              ),
                              onPressed: () => _viewItemDetails(item),
                              tooltip: 'View Operations',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editItem(item),
                              tooltip: 'Edit Item',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteItem(item['item_id']),
                              tooltip: 'Delete Item',
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
  const OperationsTab({super.key, required this.organizationCode});

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
      final list =
          agg.entries
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

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (_topOperation.isNotEmpty)
            Card(
              color: Colors.indigo.shade50,
              child: ListTile(
                leading: const Icon(Icons.trending_up, color: Colors.indigo),
                title: const Text('Most Performed Operation'),
                subtitle: Text(
                  '$_topOperationName (${_topOperation['count']} logs, ${_topOperation['qty']} qty)',
                ),
              ),
            ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'All Operations',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sortOption,
                onChanged: (val) {
                  if (val != null) setState(() => _sortOption = val);
                },
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('Default')),
                  DropdownMenuItem(
                    value: 'most_used',
                    child: Text('Most Used'),
                  ),
                  DropdownMenuItem(
                    value: 'least_used',
                    child: Text('Least Used'),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: const InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredOps.isEmpty
                ? const Center(child: Text('No operations found.'))
                : ListView.builder(
                    itemCount: filteredOps.length,
                    itemBuilder: (context, index) {
                      final op = filteredOps[index];
                      final usage = _allOperationUsage.firstWhere(
                        (u) => u['operation'] == op['op_name'],
                        orElse: () => {'count': 0, 'qty': 0},
                      );
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          onTap: () => _showOperationDetail(op, usage),
                          title: Text(op['op_name']),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Item: ${op['item_name']} (${op['item_id']})',
                              ),
                              Text(
                                'Target: ${op['target']} • Usage: ${usage['count']} logs, ${usage['qty']} qty',
                              ),
                              if (op['created_at'] != null ||
                                  op['last_produced'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '${op['created_at'] != null ? 'Created: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(op['created_at'].toString()))}' : ''}'
                                    '${op['created_at'] != null && op['last_produced'] != null ? ' • ' : ''}'
                                    '${op['last_produced'] != null ? 'Last Produced: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(op['last_produced'].toString()))}' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (op['imageUrl'] != null)
                                const Icon(Icons.image, color: Colors.blue),
                              if (op['pdfUrl'] != null)
                                const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.red,
                                ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
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
    );
  }

  void _showOperationDetail(
    Map<String, dynamic> op,
    Map<String, dynamic> usage,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(op['op_name']),
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            op['imageUrl'],
                            width: MediaQuery.of(context).size.width,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.broken_image, size: 50),
                              ),
                            ),
                          ),
                        ),
                      ),
                    _detailItem('Item Name', op['item_name']),
                    _detailItem('Item ID', op['item_id']),
                    _detailItem('Target Quantity', op['target'].toString()),
                    if (op['created_at'] != null)
                      _detailItem(
                        'Created At',
                        DateFormat(
                          'yyyy-MM-dd hh:mm a',
                        ).format(DateTime.parse(op['created_at'].toString())),
                      ),
                    const Divider(),
                    const Text(
                      'Usage Statistics',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _detailItem('Total Logs', usage['count'].toString()),
                    _detailItem('Total Quantity', usage['qty'].toString()),
                    if (op['last_produced'] != null)
                      _detailItem(
                        'Last Produced',
                        DateFormat('yyyy-MM-dd hh:mm a').format(
                          DateTime.parse(op['last_produced'].toString()),
                        ),
                      ),
                    if (op['pdfUrl'] != null &&
                        op['pdfUrl'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: ElevatedButton.icon(
                          onPressed: () => _launchURL(op['pdfUrl']),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('View PDF Guide'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red,
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
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
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
  const ShiftsTab({super.key, required this.organizationCode});

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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text(
            _editingShift == null ? 'Add New Shift' : 'Edit Shift',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Shift Name (e.g. Morning)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  readOnly: true,
                  onTap: () => _selectTime(context, _startController),
                  decoration: const InputDecoration(
                    labelText: 'Start Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _endController,
                  readOnly: true,
                  onTap: () => _selectTime(context, _endController),
                  decoration: const InputDecoration(
                    labelText: 'End Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _addOrUpdateShift,
                child: Text(
                  _editingShift == null ? 'Add Shift' : 'Update Shift',
                ),
              ),
              if (_editingShift != null) ...[
                const SizedBox(width: 10),
                TextButton(onPressed: _clearForm, child: const Text('Cancel')),
              ],
            ],
          ),
          const Divider(height: 32, thickness: 2),
          const Text(
            'Existing Shifts',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _shifts.isEmpty
              ? const Center(child: Text('No shifts found.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _shifts.length,
                  itemBuilder: (context, index) {
                    final shift = _shifts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: const Icon(
                            Icons.schedule,
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          shift['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Time: ${shift['start_time']} - ${shift['end_time']}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit Shift',
                              onPressed: () => _editShift(shift),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Shift',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Shift'),
                                    content: const Text(
                                      'Are you sure you want to delete this shift?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          _deleteShift(shift['id']);
                                          Navigator.pop(context);
                                        },
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
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
    );
  }
}

// ---------------------------------------------------------------------------
// 6. SECURITY TAB
// ---------------------------------------------------------------------------
class SecurityTab extends StatefulWidget {
  final String organizationCode;
  const SecurityTab({super.key, required this.organizationCode});

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
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_missingTable) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.security, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No login security available.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Make sure the "owner_logs" table exists in Supabase.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_logs.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No login history found.',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                '(Make sure "owner_logs" table exists in Supabase)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Owner/Admin Login History',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (_logs.isEmpty)
          const Center(child: Text('No owner/admin logins found.'))
        else
          ..._logs.map((log) {
            final timeStr = log['login_time'] as String?;
            final time =
                DateTime.tryParse(timeStr ?? '')?.toLocal() ?? DateTime.now();
            final device = log['device_name'] ?? 'Unknown';
            final os = log['os_version'] ?? 'Unknown';
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.security, color: Colors.blue),
                title: Text('Logged in at ${TimeUtils.formatTo12Hour(time)}'),
                subtitle: Text('Device: $device\nOS: $os'),
                isThreeLine: true,
              ),
            );
          }),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Employee Login History',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (_employeeLogs.isEmpty)
          const Center(child: Text('No worker/supervisor logins found.'))
        else
          ..._employeeLogs.map((log) {
            final timeStr = (log['login_time'] ?? '').toString();
            final time =
                DateTime.tryParse(timeStr)?.toLocal() ?? DateTime.now();
            final role = (log['role'] ?? '').toString();
            final workerId = (log['worker_id'] ?? '').toString();
            final device = (log['device_name'] ?? 'Unknown').toString();
            final os = (log['os_version'] ?? 'Unknown').toString();
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Icon(
                  role == 'supervisor' ? Icons.verified_user : Icons.badge,
                  color: role == 'supervisor' ? Colors.green : Colors.orange,
                ),
                title: Text(
                  '$role logged in at ${DateFormat('yyyy-MM-dd hh:mm a').format(time)}',
                ),
                subtitle: Text('User: $workerId\nDevice: $device\nOS: $os'),
                isThreeLine: true,
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }
}
