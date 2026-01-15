import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

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
              '${TimeUtils.nowUtc().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}_${op.newFile!.name}';
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
            : TimeUtils.nowUtc().toIso8601String(),
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
                '${TimeUtils.nowUtc().millisecondsSinceEpoch}_${op.name.replaceAll(' ', '_')}_${op.newFile!.name}';

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
            debugPrint('Upload error: $e');
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
        : Colors.black.withValues(alpha: 0.15);
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
