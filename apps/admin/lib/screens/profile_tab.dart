import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as io;

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
        '${TimeUtils.nowUtc().millisecondsSinceEpoch}_logo_${_logoFile!.name}';

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
}
