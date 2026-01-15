import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        : Colors.black.withValues(alpha: 0.15);
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
                    accentColor.withValues(alpha: widget.isDarkMode ? 0.2 : 0.1),
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
                                        color: textColor.withValues(alpha: 0.2)),
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
