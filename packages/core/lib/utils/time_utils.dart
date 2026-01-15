import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TimeUtils {
  static Duration _serverOffset = Duration.zero;

  static Future<void> syncServerTime() async {
    try {
      final resp = await Supabase.instance.client.rpc('get_server_time');
      if (resp != null) {
        final serverUtc = DateTime.parse(resp.toString()).toUtc();
        final deviceUtc = DateTime.now().toUtc();
        _serverOffset = serverUtc.difference(deviceUtc);
      }
    } catch (_) {}
  }

  static DateTime nowUtc() {
    return DateTime.now().toUtc().add(_serverOffset);
  }

  static DateTime nowIst() {
    final utc = nowUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  /// Parses a value (DateTime or String) and ensures it is converted to IST.
  /// If the string is missing a timezone, it assumes UTC (Supabase standard).
  static DateTime parseToLocal(dynamic value) {
    if (value == null) return nowIst();

    DateTime utc;
    if (value is DateTime) {
      utc = value.isUtc ? value : value.toUtc();
    } else {
      String dateStr = value.toString().trim();
      if (dateStr.isEmpty) return nowIst();

      try {
        // If it's just a time like "07:30", parse it relative to today
        if (dateStr.length <= 5 && dateStr.contains(':')) {
          final parts = dateStr.split(':');
          final now = nowIst();
          return DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          ).toUtc().subtract(const Duration(hours: 5, minutes: 30));
        }

        // Check if it's already got timezone info
        if (dateStr.contains('Z') || dateStr.contains('+')) {
          utc = DateTime.parse(dateStr).toUtc();
        } else {
          // If it's a standard ISO date without 'Z', append 'Z' to treat as UTC
          String isoStr = dateStr.replaceAll(' ', 'T');
          if (!isoStr.contains('T')) {
            isoStr += 'T00:00:00';
          }
          utc = DateTime.parse('${isoStr}Z');
        }
      } catch (e) {
        debugPrint('TimeUtils.parseToLocal error: $e for value: $value');
        try {
          utc = DateTime.parse(dateStr).toUtc();
        } catch (_) {
          return nowIst();
        }
      }
    }

    // Convert UTC to IST
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  /// Formats a DateTime or String into 12-hour AM/PM format.
  /// Always converts to Local time first.
  static String formatTo12Hour(dynamic value, {String format = 'hh:mm:ss a'}) {
    if (value == null) return '--';
    DateTime dt = parseToLocal(value);
    // Force UTC for formatting to prevent DateFormat from applying local offset
    final utcDt = DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
    );
    return DateFormat(format).format(utcDt);
  }

  /// Formats to the standard full display format: "dd MMM yyyy, hh:mm a"
  static String formatFull(dynamic value) {
    if (value == null) return '--';
    DateTime dt = parseToLocal(value);
    // Force UTC for formatting to prevent DateFormat from applying local offset
    final utcDt = DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
    );
    return DateFormat('dd MMM yyyy, hh:mm a').format(utcDt);
  }

  /// Returns the current system time in 12-hour format.
  static String currentSystemTime12h() {
    final dt = nowIst();
    final utcDt = DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
    );
    return DateFormat('hh:mm:ss a').format(utcDt);
  }

  /// Formats a date only (e.g., "28 Dec 2023")
  static String formatDate(dynamic value) {
    if (value == null) return '--';
    DateTime dt = parseToLocal(value);
    final utcDt = DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
    );
    return DateFormat('dd MMM yyyy').format(utcDt);
  }

  /// Parses shift time strings like "07:30:00" or "07:30 AM" into a DateTime
  /// with arbitrary date (2000-01-01) for comparison purposes.
  static DateTime? parseShiftTime(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    final trimmed = timeStr.trim();

    // 1. Manual splitting (most reliable for database formats like HH:mm:ss)
    try {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        final hh = int.parse(parts[0]);
        final mm = int.parse(parts[1]);
        final ss = parts.length > 2 ? int.parse(parts[2].split('.')[0]) : 0;
        return DateTime(2000, 1, 1, hh, mm, ss);
      }
    } catch (_) {}

    // 2. Standard formats
    final formats = [
      DateFormat("HH:mm:ss"),
      DateFormat("HH:mm"),
      DateFormat("hh:mm a"),
      DateFormat("h:mm a"),
      DateFormat("H:mm"),
    ];

    for (var format in formats) {
      try {
        return format.parse(trimmed);
      } catch (_) {}
    }
    return null;
  }

  /// Checks if the current system time is within the given shift start and end times.
  /// Handles shifts that cross midnight (e.g., 8 PM to 8 AM).
  static bool isShiftActive(String startTimeStr, String endTimeStr) {
    try {
      final now = nowIst();
      final start = parseShiftTime(startTimeStr);
      final end = parseShiftTime(endTimeStr);
      if (start == null || end == null) return true;

      final shiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        start.hour,
        start.minute,
      );
      DateTime shiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        end.hour,
        end.minute,
      );

      if (end.isBefore(start)) {
        // Shift crosses midnight
        if (now.hour >= start.hour) {
          // We are in the evening part of the shift
          shiftEnd = shiftEnd.add(const Duration(days: 1));
        } else if (now.hour < end.hour) {
          // We are in the morning part of the shift
          return true; // Already within the morning part
        } else {
          // It's after the shift ended in the morning but before it starts in the evening
          return false;
        }
      }

      return now.isAfter(shiftStart) && now.isBefore(shiftEnd);
    } catch (e) {
      debugPrint('isShiftActive error: $e');
      return true; // Fallback to active if error
    }
  }

  /// Checks if a shift has already ended for the day.
  static bool hasShiftEnded(String endTimeStr, String startTimeStr) {
    try {
      final now = nowIst();
      final start = parseShiftTime(startTimeStr);
      final end = parseShiftTime(endTimeStr);
      if (start == null || end == null) return false;

      final shiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        start.hour,
        start.minute,
      );
      var shiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        end.hour,
        end.minute,
      );

      if (end.isBefore(start)) {
        if (now.isAfter(shiftStart)) {
          shiftEnd = shiftEnd.add(const Duration(days: 1));
        }
      }

      return now.isAfter(shiftEnd);
    } catch (e) {
      return false;
    }
  }
}
