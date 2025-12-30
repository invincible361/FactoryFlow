import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/log_service.dart';
import '../utils/time_utils.dart';

class SupervisorDashboardScreen extends StatefulWidget {
  final String organizationCode;
  final String supervisorName;
  const SupervisorDashboardScreen({
    super.key,
    required this.organizationCode,
    required this.supervisorName,
  });

  @override
  State<SupervisorDashboardScreen> createState() =>
      _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _selectedWorkerId;
  DateTimeRange? _dateRange;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _fetchSupervisorPhoto();
    _fetchLogs();
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

  Future<void> _fetchSupervisorPhoto() async {
    try {
      final resp = await _supabase
          .from('workers')
          .select()
          .eq('organization_code', widget.organizationCode)
          .eq('name', widget.supervisorName)
          .maybeSingle();
      if (resp != null) {
        setState(() {
          _photoUrl = _getFirstNotEmpty(resp, [
            'photo_url',
            'avatar_url',
            'image_url',
            'imageurl',
            'photourl',
            'picture_url',
          ]);
        });
      }
    } catch (_) {
      // ignore, fallback to icon
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _loading = true);
    try {
      var builder = _supabase
          .from('production_logs')
          .select('*, workers:worker_id(name)')
          .eq('organization_code', widget.organizationCode)
          .or('is_verified.is.false,is_verified.is.null')
          .gt('quantity', 0);
      if (_selectedWorkerId != null) {
        builder = builder.eq('worker_id', _selectedWorkerId!);
      }
      if (_dateRange != null) {
        builder = builder
            .gte('created_at', _dateRange!.start.toIso8601String())
            .lte('created_at', _dateRange!.end.toIso8601String());
      }
      final response = await builder.order('created_at', ascending: false);
      setState(() {
        _logs = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      try {
        // Fallback 1: remove relationship join, keep is_verified filter and quantity > 0
        var builder = _supabase
            .from('production_logs')
            .select()
            .eq('organization_code', widget.organizationCode)
            .or('is_verified.is.false,is_verified.is.null')
            .gt('quantity', 0);
        if (_selectedWorkerId != null) {
          builder = builder.eq('worker_id', _selectedWorkerId!);
        }
        if (_dateRange != null) {
          builder = builder
              .gte('created_at', _dateRange!.start.toIso8601String())
              .lte('created_at', _dateRange!.end.toIso8601String());
        }
        final response = await builder.order('created_at', ascending: false);
        setState(() {
          _logs = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      } catch (_) {
        try {
          // Fallback 2: remove is_verified filter in case column isn't present, still only quantity > 0
          var builder = _supabase
              .from('production_logs')
              .select()
              .eq('organization_code', widget.organizationCode)
              .gt('quantity', 0);
          if (_selectedWorkerId != null) {
            builder = builder.eq('worker_id', _selectedWorkerId!);
          }
          if (_dateRange != null) {
            builder = builder
                .gte('created_at', _dateRange!.start.toIso8601String())
                .lte('created_at', _dateRange!.end.toIso8601String());
          }
          final response = await builder.order('created_at', ascending: false);
          setState(() {
            _logs = List<Map<String, dynamic>>.from(response);
            _loading = false;
          });
        } catch (_) {
          setState(() => _loading = false);
        }
      }
    }
  }

  Future<void> _verifyLog(Map<String, dynamic> log) async {
    try {
      final qtyController = TextEditingController(
        text: (log['supervisor_quantity'] ?? log['quantity'] ?? 0).toString(),
      );
      final noteController = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Verify Production'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Worker: ${(log['workers']?['name'] ?? log['worker_id']).toString()}',
                ),
                Text('Machine: ${log['machine_id']}'),
                Text('Item: ${log['item_id']}'),
                Text('Operation: ${log['operation']}'),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Supervisor Quantity',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Supervisor Remark',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newQty = int.tryParse(qtyController.text);
                  if (mounted) Navigator.pop(ctx);
                  await LogService().verifyLog(
                    logId: log['id'].toString(),
                    supervisorName: widget.supervisorName,
                    note: noteController.text.isNotEmpty
                        ? noteController.text
                        : null,
                    supervisorQuantity: newQty,
                  );
                  await _fetchLogs();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Production verified')),
                    );
                  }
                },
                child: const Text('Verify'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey[300],
              backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                  ? NetworkImage(_photoUrl!)
                  : null,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 16, color: Colors.black54)
                  : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchLogs,
            tooltip: 'Refresh',
          ),
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? const Center(child: Text('No pending logs to verify'))
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final worker = log['workers'] as Map<String, dynamic>?;
                final workerName =
                    worker?['name'] ??
                    (log['worker_id']?.toString() ?? 'Unknown');
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text('$workerName — ${log['operation']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Machine: ${log['machine_id']} | Item: ${log['item_id']}',
                        ),
                        Text('Quantity: ${log['quantity']}'),
                        Text(
                          'Time: ${TimeUtils.formatTo12Hour(log['start_time'], format: 'hh:mm a')} - ${TimeUtils.formatTo12Hour(log['end_time'], format: 'hh:mm a')}',
                        ),
                        if ((log['remarks'] ?? '').toString().isNotEmpty)
                          Text('Remarks: ${log['remarks']}'),
                      ],
                    ),
                    trailing: ElevatedButton(
                      onPressed: () => _verifyLog(log),
                      child: const Text('Verify'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
