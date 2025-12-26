import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/production_log.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final List<ProductionLog> _logs = [];

  List<ProductionLog> get logs => List.unmodifiable(_logs);

  Future<void> addLog(ProductionLog log) async {
    _logs.insert(0, log); // Keep local copy for immediate UI update if needed

    try {
      await Supabase.instance.client.from('production_logs').insert({
        'worker_id': log.employeeId,
        'machine_id': log.machineId,
        'item_id': log.itemId,
        'operation': log.operation,
        'quantity': log.quantity,
        'start_time': log.startTime?.toIso8601String(),
        'end_time': log.endTime?.toIso8601String(),
        'latitude': log.latitude,
        'longitude': log.longitude,
        'shift_name': log.shiftName,
        'performance_diff': log.performanceDiff,
        'organization_code': log.organizationCode,
        'remarks': log.remarks,
        // 'created_at' is handled by default in Postgres
      });
    } catch (e) {
      debugPrint('Error saving log to Supabase: $e');
      rethrow;
    }
  }
}
