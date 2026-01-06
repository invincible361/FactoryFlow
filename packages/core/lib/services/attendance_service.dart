import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../utils/time_utils.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getTodayAttendance(
    String workerId,
    String organizationCode,
  ) async {
    try {
      // We need to check both today and yesterday (for night shifts)
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final yesterdayStr = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));

      final response = await _supabase
          .from('attendance')
          .select()
          .eq('worker_id', workerId)
          .eq('organization_code', organizationCode)
          .or('date.eq.$todayStr,date.eq.$yesterdayStr')
          .order('date', ascending: false);

      if (response.isEmpty) return null;

      // If we have multiple, prioritize the one where check_out is null
      final active = response.where((a) => a['check_out'] == null).toList();
      if (active.isNotEmpty) return active.first;

      return response.first;
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchShifts(
    String organizationCode,
  ) async {
    try {
      final response = await _supabase
          .from('shifts')
          .select()
          .eq('organization_code', organizationCode);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching shifts: $e');
      return [];
    }
  }

  Map<String, dynamic> findShiftByTime(
    DateTime time,
    List<Map<String, dynamic>> shifts,
  ) {
    final minutes = time.hour * 60 + time.minute;
    for (final shift in shifts) {
      try {
        final startStr = shift['start_time'] as String;
        final endStr = shift['end_time'] as String;
        final format = DateFormat('hh:mm a');
        final startDt = format.parse(startStr);
        final endDt = format.parse(endStr);
        final startMinutes = startDt.hour * 60 + startDt.minute;
        final endMinutes = endDt.hour * 60 + endDt.minute;

        if (startMinutes < endMinutes) {
          if (minutes >= startMinutes && minutes < endMinutes) {
            return shift;
          }
        } else {
          // Crosses midnight
          if (minutes >= startMinutes || minutes < endMinutes) {
            return shift;
          }
        }
      } catch (e) {
        debugPrint('Error parsing shift for lookup: $e');
      }
    }
    return <String, dynamic>{};
  }

  Future<void> updateAttendance({
    required String workerId,
    required String organizationCode,
    required List<Map<String, dynamic>> shifts,
    String? selectedShiftName,
    bool isCheckOut = false,
    DateTime? eventTime,
    DateTime? startTimeRef,
    String? overrideStatus,
  }) async {
    try {
      final now = eventTime ?? DateTime.now();

      // Determine shift name strictly
      String targetShiftName = selectedShiftName ?? '';
      Map<String, dynamic> shift = {};

      if (targetShiftName.isNotEmpty) {
        shift = shifts.firstWhere(
          (s) => s['name'] == targetShiftName,
          orElse: () => <String, dynamic>{},
        );
      }

      // If no valid shift selected/found, try to detect from time
      if (shift.isEmpty) {
        shift = findShiftByTime(now, shifts);
        if (shift.isNotEmpty) {
          targetShiftName = shift['name'];
        } else {
          targetShiftName = 'General'; // Fallback to avoid null
        }
      }

      // ATTENDANCE DATE LOGIC:
      DateTime attendanceDate = now;
      if (shift.isNotEmpty) {
        try {
          final format = DateFormat('hh:mm a');
          final startDt = format.parse(shift['start_time']);
          final endDt = format.parse(shift['end_time']);

          if (endDt.isBefore(startDt)) {
            // This is a night shift
            if (now.hour < endDt.hour ||
                (now.hour == endDt.hour && now.minute < endDt.minute)) {
              // We are in the morning part of the night shift
              attendanceDate = now.subtract(const Duration(days: 1));
            }
          }
        } catch (e) {
          debugPrint('Error calculating attendance date: $e');
        }
      }

      // If we are checking out, we MUST use the same attendance date as when we checked in.
      if (isCheckOut && startTimeRef != null) {
        DateTime startRef = startTimeRef;
        if (shift.isNotEmpty) {
          try {
            final format = DateFormat('hh:mm a');
            final startDt = format.parse(shift['start_time']);
            final endDt = format.parse(shift['end_time']);
            if (endDt.isBefore(startDt)) {
              if (startRef.hour < endDt.hour ||
                  (startRef.hour == endDt.hour &&
                      startRef.minute < endDt.minute)) {
                attendanceDate = startRef.subtract(const Duration(days: 1));
              } else {
                attendanceDate = startRef;
              }
            } else {
              attendanceDate = startRef;
            }
          } catch (e) {
            attendanceDate = startRef;
          }
        } else {
          attendanceDate = startRef;
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(attendanceDate);

      final payload = {
        'worker_id': workerId,
        'organization_code': organizationCode,
        'date': dateStr,
        'shift_name': targetShiftName,
        'shift_start_time': shift['start_time'],
        'shift_end_time': shift['end_time'],
      };

      if (!isCheckOut) {
        final existing = await _supabase
            .from('attendance')
            .select()
            .eq('worker_id', workerId)
            .eq('date', dateStr)
            .eq('organization_code', organizationCode)
            .maybeSingle();

        if (existing == null) {
          // Use RPC for check-in to let backend handle timestamp
          await _supabase.rpc(
            'attendance_check_in',
            params: {
              'p_worker_id': workerId,
              'p_org_code': organizationCode,
              'p_date': dateStr,
              'p_shift_name': targetShiftName,
              'p_shift_start': shift['start_time'],
              'p_shift_end': shift['end_time'],
            },
          );
        } else {
          final Map<String, dynamic> updateData = {
            'shift_name': targetShiftName,
            'shift_start_time': shift['start_time'],
            'shift_end_time': shift['end_time'],
          };

          final existingCheckIn = existing['check_in']?.toString();
          bool shouldUpdateCheckIn = (existingCheckIn == null);

          if (existingCheckIn != null) {
            final cin = TimeUtils.parseToLocal(existingCheckIn);
            if (cin.hour == 0 && cin.minute == 0 && cin.second == 0) {
              shouldUpdateCheckIn = true;
            }
          }

          if (shouldUpdateCheckIn) {
            // Re-use check_in RPC which handles ON CONFLICT DO NOTHING
            // but we already know it exists, so we just update check_in manually if needed
            // or we could create an attendance_update_check_in RPC.
            // For now, if we want "Backend as Truth", we use NOW()
            updateData['check_in'] = DateTime.now().toUtc().toIso8601String();
            updateData['status'] = 'On Time';
          }

          await _supabase
              .from('attendance')
              .update(updateData)
              .eq('worker_id', workerId)
              .eq('date', dateStr)
              .eq('organization_code', organizationCode);
        }
      } else {
        // Use RPC for check-out to let backend handle timestamp
        try {
          await _supabase.rpc(
            'attendance_check_out',
            params: {
              'p_worker_id': workerId,
              'p_org_code': organizationCode,
              'p_date': dateStr,
            },
          );
        } catch (e) {
          debugPrint('Error during attendance_check_out RPC: $e');
          // Fallback if RPC fails
          payload['check_out'] = DateTime.now().toUtc().toIso8601String();
        }

        if (shift.isNotEmpty) {
          try {
            final format = DateFormat('hh:mm a');
            final shiftEndDt = format.parse(shift['end_time']);
            final shiftStartDt = format.parse(shift['start_time']);

            DateTime shiftEndToday = DateTime(
              now.year,
              now.month,
              now.day,
              shiftEndDt.hour,
              shiftEndDt.minute,
            );

            if (shiftEndDt.isBefore(shiftStartDt)) {
              if (now.hour >= shiftStartDt.hour || now.hour < shiftEndDt.hour) {
                if (now.hour >= shiftStartDt.hour) {
                  shiftEndToday = shiftEndToday.add(const Duration(days: 1));
                }
              }
            }

            final diffMinutes = now.difference(shiftEndToday).inMinutes;
            final isEarly = diffMinutes < -15;
            final isOvertime = diffMinutes > 15;

            payload['is_early_leave'] = isEarly;
            payload['is_overtime'] = isOvertime;
            payload['status'] =
                overrideStatus ??
                ((isEarly && isOvertime)
                    ? 'Both'
                    : (isEarly
                          ? 'Early Leave'
                          : (isOvertime ? 'Overtime' : 'On Time')));
          } catch (e) {
            debugPrint('Error calculating shift end for attendance: $e');
            if (overrideStatus != null) {
              payload['status'] = overrideStatus;
            }
          }
        } else if (overrideStatus != null) {
          payload['status'] = overrideStatus;
        }

        await _supabase
            .from('attendance')
            .update(payload)
            .eq('worker_id', workerId)
            .eq('date', dateStr)
            .eq('organization_code', organizationCode);
      }
    } catch (e) {
      debugPrint('Error updating attendance: $e');
      rethrow;
    }
  }
}
