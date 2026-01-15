import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

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
  RealtimeChannel? _realtimeChannel;
  Timer? _statusRefreshTimer;

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
    _setupRealtime();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  void _setupRealtime() {
    _realtimeChannel = _supabase
        .channel('admin_employees_status')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'production_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            if (mounted) setState(() {});
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'worker_boundary_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_code',
            value: widget.organizationCode,
          ),
          callback: (payload) {
            if (mounted) setState(() {});
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    try {
      _realtimeChannel?.unsubscribe();
      _statusRefreshTimer?.cancel();
    } catch (_) {}
    super.dispose();
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

  Future<Map<String, dynamic>?> _getWorkerStatus(String workerId) async {
    try {
      // 1. Get location status from workers table directly (most efficient)
      final worker = await _supabase
          .from('workers')
          .select('last_boundary_state')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .maybeSingle();

      final isInside =
          worker != null && worker['last_boundary_state'] == 'inside';

      // 2. Get active production log
      final activeLog = await _supabase
          .from('production_logs')
          .select('*, items(name), machines(name)')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .eq('is_active', true)
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();

      // 3. Get all pending verifications
      final pendingVerifications = await _supabase
          .from('production_logs')
          .select('*, items(name), machines(name)')
          .eq('worker_id', workerId)
          .eq('organization_code', widget.organizationCode)
          .or('is_verified.is.false,is_verified.is.null')
          .not('end_time', 'is', null)
          .gt('quantity', 0)
          .order('end_time', ascending: false);

      String? awaitingVerificationStatus;
      if ((pendingVerifications as List).isNotEmpty) {
        final count = pendingVerifications.length;
        final latest = pendingVerifications.first;
        final itemName = latest['items']?['name'] ?? latest['item_id'];
        if (count > 1) {
          awaitingVerificationStatus =
              "${latest['operation']} ($itemName) + ${count - 1} more";
        } else {
          awaitingVerificationStatus = "${latest['operation']} ($itemName)";
        }
      }

      return {
        'is_inside': isInside,
        'active_log': activeLog,
        'awaiting_verification': awaitingVerificationStatus,
      };
    } catch (e) {
      debugPrint('Error getting worker status: $e');
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
          hintStyle:
              TextStyle(color: secondaryTextColor.withValues(alpha: 0.5)),
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
            borderSide: BorderSide(color: borderColor),
          ),
        ),
      ),
    );
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
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            employee['name'] ?? 'No Name',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _getWorkerStatus(employee['worker_id']),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                width: 8,
                                height: 8,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.grey),
                                ),
                              );
                            }
                            final status = snapshot.data;
                            final isInside = status?['is_inside'] ??
                                (employee['last_boundary_state'] == 'inside');
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isInside ? Colors.green : Colors.redAccent,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _getWorkerStatus(employee['worker_id']),
                          builder: (context, snapshot) {
                            final status = snapshot.data;
                            final activeLog = status?['active_log'];
                            final isInside = status?['is_inside'] ?? false;
                            final awaiting = status?['awaiting_verification'];
                            if (activeLog == null) {
                              if (awaiting != null) {
                                return Text(
                                  "Awaiting verification: $awaiting",
                                  style: TextStyle(
                                    color: const Color(0xFFA9DFD8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                );
                              } else {
                                return Text(
                                  isInside ? 'Idle' : 'OUTSIDE FACTORY',
                                  style: TextStyle(
                                    color: isInside
                                        ? subTextColor.withValues(alpha: 0.5)
                                        : Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: isInside
                                        ? FontWeight.normal
                                        : FontWeight.w900,
                                    letterSpacing: isInside ? 0 : 0.5,
                                    fontStyle: isInside
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                );
                              }
                            } else {
                              final itemName =
                                  activeLog['items']?['name'] ?? 'Unknown Item';
                              final machineName = activeLog['machines']
                                      ?['name'] ??
                                  'Unknown Machine';
                              String base =
                                  'Working on $itemName at $machineName';
                              // If stale (>12h since start), consider Idle
                              final startStr = activeLog['start_time'] ??
                                  activeLog['created_at'];
                              if (startStr != null) {
                                try {
                                  final start =
                                      DateTime.parse(startStr.toString())
                                          .toUtc();
                                  final diff = DateTime.now()
                                      .toUtc()
                                      .difference(start)
                                      .inHours;
                                  if (diff >= 12) {
                                    return Text(
                                      isInside ? 'Idle' : 'OUTSIDE FACTORY',
                                      style: TextStyle(
                                        color: isInside
                                            ? subTextColor.withValues(
                                                alpha: 0.5)
                                            : Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: isInside
                                            ? FontWeight.normal
                                            : FontWeight.w900,
                                        letterSpacing: isInside ? 0 : 0.5,
                                        fontStyle: isInside
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  }
                                } catch (_) {}
                              }
                              if (!isInside) {
                                final startTimeStr = activeLog['start_time'] ??
                                    activeLog['created_at'];
                                bool isRecent = false;
                                if (startTimeStr != null) {
                                  try {
                                    final start =
                                        DateTime.parse(startTimeStr.toString())
                                            .toUtc();
                                    isRecent = DateTime.now()
                                            .toUtc()
                                            .difference(start)
                                            .inMinutes <
                                        5;
                                  } catch (_) {}
                                }
                                return Text(
                                  isRecent
                                      ? '$base (OUTSIDE)'
                                      : 'OUTSIDE FACTORY',
                                  style: TextStyle(
                                    color: isRecent
                                        ? const Color(0xFFA9DFD8)
                                        : Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: isRecent
                                        ? FontWeight.w500
                                        : FontWeight.w900,
                                    letterSpacing: isRecent ? 0 : 0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                );
                              }
                              return Text(
                                base,
                                style: const TextStyle(
                                  color: Color(0xFFA9DFD8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                          },
                        ),
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
