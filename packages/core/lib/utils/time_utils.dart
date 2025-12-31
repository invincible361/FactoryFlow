import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

class TimeUtils {
  /// Parses a value (DateTime or String) and ensures it is converted to Local time.
  /// If the string is missing a timezone, it assumes UTC (Supabase standard).
  static DateTime parseToLocal(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value.toLocal();

    String dateStr = value.toString().trim();
    if (dateStr.isEmpty) return DateTime.now();

    try {
      // If it's just a time like "07:30", parse it relative to today
      if (dateStr.length <= 5 && dateStr.contains(':')) {
        final parts = dateStr.split(':');
        final now = DateTime.now();
        return DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }

      // Check if it's already got timezone info
      if (dateStr.contains('Z') || dateStr.contains('+')) {
        return DateTime.parse(dateStr).toLocal();
      }

      // If it's a standard ISO date without 'Z', append 'Z' to treat as UTC then convert to local
      // e.g. "2023-12-28 10:00:00" -> "2023-12-28T10:00:00Z"
      String isoStr = dateStr.replaceAll(' ', 'T');
      if (!isoStr.contains('T')) {
        // If it's just a date "2023-12-28", assume start of day UTC
        isoStr += 'T00:00:00';
      }
      return DateTime.parse('${isoStr}Z').toLocal();
    } catch (e) {
      debugPrint('TimeUtils.parseToLocal error: $e for value: $value');
      // Fallback: try parsing as is
      try {
        return DateTime.parse(dateStr).toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  /// Formats a DateTime or String into 12-hour AM/PM format.
  /// Always converts to Local time first.
  static String formatTo12Hour(dynamic value, {String format = 'hh:mm:ss a'}) {
    if (value == null) return '--';
    DateTime dt = parseToLocal(value);
    return DateFormat(format).format(dt);
  }

  /// Returns the current system time in 12-hour format.
  static String currentSystemTime12h() {
    return DateFormat('hh:mm:ss a').format(DateTime.now());
  }

  /// Formats a date only (e.g., "28 Dec 2023")
  static String formatDate(dynamic value) {
    if (value == null) return '--';
    DateTime dt = parseToLocal(value);
    return DateFormat('dd MMM yyyy').format(dt);
  }

  /// Checks if the current system time is within the given shift start and end times.
  /// Handles shifts that cross midnight (e.g., 8 PM to 8 AM).
  static bool isShiftActive(String startTimeStr, String endTimeStr) {
    try {
      final now = DateTime.now();
      final format = DateFormat('hh:mm a');
      final start = format.parse(startTimeStr);
      final end = format.parse(endTimeStr);

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
      final now = DateTime.now();
      final format = DateFormat('hh:mm a');
      final end = format.parse(endTimeStr);
      final start = format.parse(startTimeStr);

      DateTime shiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        end.hour,
        end.minute,
      );

      if (end.isBefore(start)) {
        // Night shift
        if (now.hour >= start.hour) {
          // Shift is currently running or just started
          return false;
        }
        // If we are in the morning, check if now is after the morning end time
      }

      return now.isAfter(shiftEnd);
    } catch (e) {
      return false;
    }
  }
}
