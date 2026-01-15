import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/time_utils.dart';
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

        final payload = {
          'id': log.id,
          'worker_id': log.employeeId,
          'machine_id': log.machineId,
          'item_id': log.itemId,
          'operation': log.operation,
          'quantity': log.quantity,
          'latitude': log.latitude,
          'longitude': log.longitude,
          'shift_name': log.shiftName,
          'performance_diff': log.performanceDiff,
          'organization_code': org,
          'remarks': log.remarks,
          'is_verified': log.createdBySupervisor == true,
          'created_by_supervisor': log.createdBySupervisor,
          'supervisor_id': log.supervisorId,
          'is_active': log.endTime == null,
        };

        if (log.startTime != null) {
          payload['start_time'] = log.startTime?.toUtc().toIso8601String();
        }
        if (log.endTime != null) {
          payload['end_time'] = log.endTime?.toUtc().toIso8601String();
        }
        if (log.timestamp != null) {
          payload['timestamp'] = log.timestamp?.toUtc().toIso8601String();
        }

        payloads.add(payload);
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

  Future<void> startProductionLog(ProductionLog log) async {
    final String idToUse = _isValidUuid(log.id) ? log.id : const Uuid().v4();
    bool rpcOk = false;
    try {
      await Supabase.instance.client.rpc(
        'log_production_start',
        params: {
          'p_id': idToUse,
          'p_worker_id': log.employeeId,
          'p_machine_id': log.machineId,
          'p_item_id': log.itemId,
          'p_operation': log.operation,
          'p_lat': log.latitude,
          'p_lng': log.longitude,
          'p_org_code': log.organizationCode,
          'p_shift_name': log.shiftName ?? 'General',
        },
      );
      rpcOk = true;
    } catch (e) {
      debugPrint('Error starting production log via RPC, will fallback: $e');
    }

    final payload = {
      'id': idToUse,
      'worker_id': log.employeeId,
      'machine_id': log.machineId,
      'item_id': log.itemId,
      'operation': log.operation,
      'quantity': log.quantity,
      'latitude': log.latitude,
      'longitude': log.longitude,
      'shift_name': log.shiftName ?? 'General',
      'organization_code': log.organizationCode,
      'is_active': true,
      if (!rpcOk) 'start_time': TimeUtils.nowUtc().toIso8601String(),
      if (!rpcOk) 'timestamp': TimeUtils.nowUtc().toIso8601String(),
    };
    try {
      await Supabase.instance.client.from('production_logs').upsert(payload);
    } catch (e) {
      debugPrint('Error upserting production log (fallback): $e');
      rethrow;
    }

    _logs.insert(0, log);
  }

  Future<void> finishProductionLog({
    required String id,
    required int quantity,
    required int performanceDiff,
    required double latitude,
    required double longitude,
    String? remarks,
  }) async {
    final String idToUse = _isValidUuid(id) ? id : const Uuid().v4();
    try {
      await Supabase.instance.client.rpc(
        'log_production_end',
        params: {
          'p_id': idToUse,
          'p_quantity': quantity,
          'p_performance_diff': performanceDiff,
          'p_remarks': remarks,
        },
      );
      try {
        await Supabase.instance.client
            .from('production_logs')
            .update({
              'is_active': false,
              'end_time': TimeUtils.nowUtc().toIso8601String(),
              'remarks': remarks,
            })
            .eq('id', idToUse);
      } catch (_) {}
      final index = _logs.indexWhere((l) => l.id == id);
      if (index != -1) {
        final oldLog = _logs[index];
        _logs[index] = ProductionLog(
          id: idToUse,
          employeeId: oldLog.employeeId,
          machineId: oldLog.machineId,
          itemId: oldLog.itemId,
          operation: oldLog.operation,
          quantity: quantity,
          latitude: latitude,
          longitude: longitude,
          shiftName: oldLog.shiftName,
          performanceDiff: performanceDiff,
          organizationCode: oldLog.organizationCode,
          remarks: remarks ?? oldLog.remarks,
          endTime: TimeUtils.nowUtc(),
        );
      }
    } catch (e) {
      debugPrint('Error finishing production log: $e');
      rethrow;
    }
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

  bool _isValidUuid(String s) {
    final r = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return r.hasMatch(s);
  }
}
