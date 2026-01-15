import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'dart:io' as io;
import 'package:flutter/foundation.dart';

class AttendanceTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;
  const AttendanceTab({
    super.key,
    required this.organizationCode,
    required this.isDarkMode,
  });

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
            start: TimeUtils.nowIst().subtract(const Duration(days: 7)),
            end: TimeUtils.nowIst(),
          ),
      firstDate: DateTime(2023),
      lastDate: TimeUtils.nowIst(),
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
      excel.rename('Sheet1', 'Efficiency Report');
      final sheet = excel['Efficiency Report'];

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
        final timestamp =
            DateFormat('yyyyMMdd_HHmmss').format(TimeUtils.nowIst());
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(
                              'Shift Name',
                              record['shift_name'] ?? 'N/A',
                              textColor,
                              subTextColor),
                          _detailRow('Status', record['status'] ?? 'On Time',
                              textColor, subTextColor),
                          _detailRow(
                              'Check In',
                              TimeUtils.formatTo12Hour(record['check_in']),
                              textColor,
                              subTextColor),
                          _detailRow(
                              'Check Out',
                              TimeUtils.formatTo12Hour(record['check_out']),
                              textColor,
                              subTextColor),
                          _detailRow(
                              'Hours Worked',
                              _formatHoursWorked(
                                  record['check_in'], record['check_out']),
                              textColor,
                              subTextColor),
                          _detailRow(
                              'Verified',
                              (record['is_verified'] ?? false) ? 'Yes' : 'No',
                              textColor,
                              subTextColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
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
                                      '${log['item_name']} - ${log['operation']}',
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFA9DFD8)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${log['quantity']} units',
                                      style: const TextStyle(
                                        color: Color(0xFFA9DFD8),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Machine: ${log['machine_name']}',
                                style: TextStyle(
                                    color: subTextColor, fontSize: 12),
                              ),
                              if (log['remarks'] != null &&
                                  log['remarks'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Remarks: ${log['remarks']}',
                                    style: TextStyle(
                                        color: subTextColor,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
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
            child:
                const Text('Close', style: TextStyle(color: Color(0xFFA9DFD8))),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
      String label, String value, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: subTextColor, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatHoursWorked(dynamic checkIn, dynamic checkOut) {
    if (checkIn == null || checkOut == null) return '--:--';
    try {
      final ci = DateTime.parse(checkIn.toString()).toUtc();
      final co = DateTime.parse(checkOut.toString()).toUtc();
      final d = co.difference(ci);
      if (d.isNegative) return '--:--';
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final hh = h.toString().padLeft(2, '0');
      final mm = m.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color cardColor =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;

    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFA9DFD8)))
              : _attendance.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _attendance.length,
                      itemBuilder: (context, index) =>
                          _buildAttendanceCard(_attendance[index], cardColor),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;
    final Color cardColor =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;
    final Color borderColor =
        widget.isDarkMode ? Colors.white10 : Colors.black12;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedEmployeeId,
                      hint: Text('Select Employee',
                          style: TextStyle(color: subTextColor, fontSize: 14)),
                      isExpanded: true,
                      dropdownColor: cardColor,
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: subTextColor),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All Employees'),
                        ),
                        ..._employees.map((e) => DropdownMenuItem<String>(
                              value: e['worker_id'],
                              child: Text(e['name']),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedEmployeeId = val);
                        _fetchAttendance();
                      },
                      style: TextStyle(color: textColor, fontSize: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _selectDateRange,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: Color(0xFFA9DFD8)),
                      const SizedBox(width: 8),
                      Text(
                        _selectedDateRange == null
                            ? 'Select Dates'
                            : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
                        style: TextStyle(fontSize: 13, color: textColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Showing ${_attendance.length} records',
                style: TextStyle(color: subTextColor, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isExporting ? null : _exportToExcel,
                icon: _isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export Efficiency'),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFA9DFD8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_rounded,
              size: 64, color: subTextColor.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No Records Found',
              style: TextStyle(
                  color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Try adjusting your filters or date range',
              style: TextStyle(color: subTextColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> record, Color cardColor) {
    final worker = record['workers'] as Map<String, dynamic>?;
    final workerName = worker?['name'] ?? 'Unknown Worker';
    final status = record['status'] ?? 'On Time';
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black;
    final Color subTextColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;

    Color statusColor = const Color(0xFFA9DFD8);
    if (status == 'Absent') {
      statusColor = Colors.redAccent;
    } else if (status.contains('Early Leave')) {
      statusColor = Colors.orangeAccent;
    } else if (status.contains('Overtime')) {
      statusColor = Colors.blueAccent;
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
      ),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(workerName,
                        style: TextStyle(
                            color: textColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, MMM dd')
                          .format(DateTime.parse(record['date'])),
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${TimeUtils.formatTo12Hour(record['check_in'])} - ${record['check_out'] != null ? TimeUtils.formatTo12Hour(record['check_out']) : '--:--'}',
                    style: TextStyle(color: textColor, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hours: ${_formatHoursWorked(record['check_in'], record['check_out'])}',
                    style: TextStyle(color: subTextColor, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
