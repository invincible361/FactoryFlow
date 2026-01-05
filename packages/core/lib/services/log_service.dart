import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/production_log.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final List<ProductionLog> _logs = [];

  List<ProductionLog> get logs => List.unmodifiable(_logs);

  Future<void> addLogs(List<ProductionLog> logs) async {
    if (logs.isEmpty) return;
    
    // Add to local list
    for (var log in logs) {
      _logs.insert(0, log);
    }

    try {
      final List<Map<String, dynamic>> payloads = [];
      
      for (var log in logs) {
        String? org = log.organizationCode;
        if (org == null || org.isEmpty) {
          // Fallback fetch if missing for any log (though ideally it should be provided)
          try {
            final w = await Supabase.instance.client
                .from('workers')
                .select('organization_code')
                .eq('worker_id', log.employeeId)
                .maybeSingle();
            if (w != null) {
              org = (w['organization_code'] ?? '').toString();
            }
          } catch (_) {}
        }

        payloads.add({
          'id': log.id,
          'worker_id': log.employeeId,
          'machine_id': log.machineId,
          'item_id': log.itemId,
          'operation': log.operation,
          'quantity': log.quantity,
          'start_time': log.startTime?.toUtc().toIso8601String(),
          'end_time': log.endTime?.toUtc().toIso8601String(),
          'latitude': log.latitude,
          'longitude': log.longitude,
          'shift_name': log.shiftName,
          'performance_diff': log.performanceDiff,
          'organization_code': org,
          'remarks': log.remarks,
          'is_verified': log.createdBySupervisor == true,
          'created_by_supervisor': log.createdBySupervisor,
          'supervisor_id': log.supervisorId,
        });
      }

      await Supabase.instance.client.from('production_logs').upsert(payloads);
    } catch (e) {
      debugPrint('Error saving bulk logs to Supabase: $e');
      rethrow;
    }
  }

  Future<void> addLog(ProductionLog log) async {
    await addLogs([log]);
  }

  Future<List<Map<String, dynamic>>> fetchLogsForOrganization({
    required String organizationCode,
    bool? isVerified,
    String? workerId,
  }) async {
    var builder = Supabase.instance.client.from('production_logs').select();
    builder = builder.eq('organization_code', organizationCode);
    if (isVerified != null) {
      builder = builder.eq('is_verified', isVerified);
    }
    if (workerId != null) {
      builder = builder.eq('worker_id', workerId);
    }
    final response = await builder.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> verifyLog({
    required String logId,
    required String supervisorName,
    String? note,
    int? supervisorQuantity,
  }) async {
    try {
      final updatePayload = {
        'is_verified': true,
        'verified_by': supervisorName,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'verified_note': note,
      };
      if (supervisorQuantity != null) {
        updatePayload['supervisor_quantity'] = supervisorQuantity;
      }
      await Supabase.instance.client
          .from('production_logs')
          .update(updatePayload)
          .eq('id', logId);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('PGRST204') || msg.contains('column')) {
        try {
          final fallbackPayload = {
            'is_verified': true,
            'verified_by': supervisorName,
            'verified_at': DateTime.now().toUtc().toIso8601String(),
            'verified_note': note,
          };
          await Supabase.instance.client
              .from('production_logs')
              .update(fallbackPayload)
              .eq('id', logId);
          debugPrint(
            'Supervisor verification completed (using fallback for missing quantity column)',
          );
          return;
        } catch (e2) {
          debugPrint('Verify fallback failed: $e2');
          rethrow;
        }
      } else {
        debugPrint('Error verifying log: $e');
        rethrow;
      }
    }
  }
}
