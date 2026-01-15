import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:image_picker/image_picker.dart';

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
            'sup_${trimmedId}_${TimeUtils.nowUtc().millisecondsSinceEpoch}.png';
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
                                                'sup_${sup['worker_id']}_${TimeUtils.nowUtc().millisecondsSinceEpoch}.png';
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
                                                'sup_${sup['worker_id']}_${TimeUtils.nowUtc().millisecondsSinceEpoch}.png';
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
