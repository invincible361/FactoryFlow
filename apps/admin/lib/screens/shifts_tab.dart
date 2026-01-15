import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';

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
      final dt = DateTime(
        2000,
        1,
        1,
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
