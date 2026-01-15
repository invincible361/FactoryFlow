import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:url_launcher/url_launcher.dart';

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
