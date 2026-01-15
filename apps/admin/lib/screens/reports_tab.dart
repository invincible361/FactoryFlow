import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as xl;
import 'package:share_plus/share_plus.dart';

class ReportsTab extends StatefulWidget {
  final String organizationCode;
  final bool isDarkMode;

  const ReportsTab({
    super.key,
    required this.organizationCode,
    required this.isDarkMode,
  });

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _supabase = Supabase.instance.client;
  bool _isExporting = false;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: TimeUtils.nowIst().subtract(const Duration(days: 7)),
    end: TimeUtils.nowIst(),
  );

  final List<Map<String, dynamic>> _reportTypes = [
    {
      'id': 'daily_worker_summary',
      'title': 'Daily Worker Summary',
      'description':
          'First entry, last exit, total production and outside time.',
      'icon': Icons.person_search_rounded,
    },
    {
      'id': 'machine_utilization',
      'title': 'Machine Utilization',
      'description': 'Running time, idle time, and operator count per machine.',
      'icon': Icons.settings_suggest_rounded,
    },
    {
      'id': 'production_efficiency',
      'title': 'Production Efficiency',
      'description':
          'Planned vs actual output, correction delta, and output/hour.',
      'icon': Icons.speed_rounded,
    },
    {
      'id': 'exception_report',
      'title': 'Exception Report',
      'description':
          'Late arrivals, long outside durations, and production spikes.',
      'icon': Icons.warning_amber_rounded,
    },
  ];

  Future<void> _generateAndDownloadReport(String reportType,
      {bool isExcel = false}) async {
    setState(() => _isExporting = true);
    try {
      List<Map<String, dynamic>> data = [];
      try {
        final response = await _supabase.functions.invoke(
          'generate-report',
          body: {
            'reportType': reportType,
            'orgCode': widget.organizationCode,
            'dateStart':
                DateFormat('yyyy-MM-dd').format(_selectedDateRange.start),
            'dateEnd': DateFormat('yyyy-MM-dd').format(_selectedDateRange.end),
            'format': isExcel ? 'json' : 'csv',
          },
        );

        if (response.status == 200) {
          if (isExcel || response.data is List) {
            data = List<Map<String, dynamic>>.from(response.data);
          } else if (response.data is String) {
            // CSV string from Edge Function - directly download
            await _handleFileDownload(
                response.data, reportType, 'csv', 'text/csv');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report downloaded successfully')),
              );
            }
            return;
          } else {
            throw 'Unexpected response format';
          }
        } else {
          throw 'Failed to generate report: ${response.data}';
        }
      } catch (e) {
        debugPrint(
            'Edge function failed, falling back to local generation: $e');
        data = await _fetchReportDataLocally(reportType);
      }

      if (data.isEmpty) {
        throw 'No data found for the selected period';
      }

      if (isExcel) {
        final excelBytes = await _generateExcel(data, reportType);
        await _handleFileDownload(excelBytes, reportType, 'xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      } else {
        final csvString = _generateCsv(data);
        await _handleFileDownload(csvString, reportType, 'csv', 'text/csv');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report generated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleFileDownload(
      dynamic content, String reportType, String ext, String mimeType) async {
    final fileName =
        '${reportType}_${DateFormat('yyyyMMdd').format(_selectedDateRange.start)}.$ext';
    final Uint8List bytes = content is String
        ? Uint8List.fromList(content.codeUnits)
        : content as Uint8List;

    if (kIsWeb) {
      await WebDownloadHelper.download(bytes, fileName, mimeType: mimeType);
    } else {
      final directory = await getTemporaryDirectory();
      final file = io.File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: 'Report: $fileName');
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReportDataLocally(
      String reportType) async {
    final start = DateFormat('yyyy-MM-dd').format(_selectedDateRange.start);
    final end = DateFormat('yyyy-MM-dd').format(_selectedDateRange.end);

    String viewName = "";
    switch (reportType) {
      case "daily_worker_summary":
        viewName = "daily_worker_summary";
        break;
      case "machine_utilization":
        viewName = "machine_utilization_summary";
        break;
      case "production_efficiency":
        viewName = "production_efficiency_summary";
        break;
      case "exception_report":
        viewName = "exception_report";
        break;
      default:
        throw Exception("Invalid report type");
    }

    final response = await _supabase
        .from(viewName)
        .select()
        .eq("organization_code", widget.organizationCode)
        .gte("date", start)
        .lte("date", end);

    return List<Map<String, dynamic>>.from(response);
  }

  String _generateCsv(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return "";
    final headers =
        data[0].keys.where((k) => k != 'id' && k != 'log_id').toList();
    return [
      headers.map((h) => h.replaceAll('_', ' ').toUpperCase()).join(","),
      ...data.map((row) => headers.map((header) {
            final val = row[header];
            if (val == null) return "";
            final str = val.toString();
            return str.contains(',') ? '"${str.replaceAll('"', '""')}"' : str;
          }).join(","))
    ].join("\n");
  }

  Future<Uint8List> _generateExcel(
      List<Map<String, dynamic>> data, String sheetName) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel[sheetName];
    excel.delete('Sheet1'); // Remove default sheet

    if (data.isNotEmpty) {
      final headers =
          data[0].keys.where((k) => k != 'id' && k != 'log_id').toList();
      sheet.appendRow(headers
          .map((h) => xl.TextCellValue(h.replaceAll('_', ' ').toUpperCase()))
          .toList());

      for (final row in data) {
        sheet.appendRow(headers
            .map((h) => xl.TextCellValue(row[h]?.toString() ?? ""))
            .toList());
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes!);
  }

  void _viewReportInApp(String reportType) async {
    setState(() => _isExporting = true);
    try {
      final data = await _fetchReportDataLocally(reportType);
      if (mounted) {
        if (data.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data found for this period')),
          );
          return;
        }
        _showReportDialog(reportType, data);
      }
    } catch (e) {
      debugPrint('View report error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showReportDialog(String title, List<Map<String, dynamic>> data) {
    showDialog(
      context: context,
      builder: (context) {
        final headers =
            data[0].keys.where((k) => k != 'id' && k != 'log_id').toList();
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title.replaceAll('_', ' ').toUpperCase()),
              actions: [
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () {
                    Navigator.pop(context);
                    _generateAndDownloadReport(title, isExcel: true);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: headers
                      .map((h) => DataColumn(
                              label: Text(
                            h.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )))
                      .toList(),
                  rows: data.map((row) {
                    return DataRow(
                      cells: headers.map((h) {
                        final val = row[h];
                        return DataCell(Text(val?.toString() ?? '-'));
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Helper for typeof in Dart (not needed but for clarity from JS)
  String typeof(dynamic val) => val.runtimeType.toString();

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2024),
      lastDate: TimeUtils.nowIst(),
      builder: (context, child) {
        return Theme(
          data: widget.isDarkMode ? ThemeData.dark() : ThemeData.light(),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;
    final secondaryTextColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;
    final cardColor =
        widget.isDarkMode ? const Color(0xFF21222D) : Colors.white;

    return Padding(
      padding: const EdgeInsets.all(16.0),
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
                      'Analytics & Reports',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Generate and download comprehensive data exports',
                      style: TextStyle(color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  '${DateFormat('MMM d').format(_selectedDateRange.start)} - ${DateFormat('MMM d').format(_selectedDateRange.end)}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isDarkMode
                      ? Colors.tealAccent.withValues(alpha: 0.1)
                      : Colors.teal.shade50,
                  foregroundColor:
                      widget.isDarkMode ? Colors.tealAccent : Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: _reportTypes.length,
              itemBuilder: (context, index) {
                final report = _reportTypes[index];
                return Card(
                  color: cardColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color:
                          widget.isDarkMode ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: InkWell(
                    onTap: _isExporting
                        ? null
                        : () => _viewReportInApp(report['id']),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                report['icon'],
                                color: Colors.tealAccent,
                                size: 28,
                              ),
                              const Spacer(),
                              if (_isExporting)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.table_view_rounded,
                                          size: 18),
                                      onPressed: () =>
                                          _viewReportInApp(report['id']),
                                      tooltip: 'View in App',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.download_for_offline_rounded,
                                          size: 18),
                                      onPressed: () =>
                                          _generateAndDownloadReport(
                                              report['id'],
                                              isExcel: true),
                                      tooltip: 'Export Excel',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            report['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report['description'],
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
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
}
