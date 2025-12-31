import '../utils/time_utils.dart';

class WorkerBoundaryEvent {
  final String id;
  final String workerId;
  final String organizationCode;
  final DateTime exitTime;
  final DateTime? entryTime;
  final double exitLat;
  final double exitLng;
  final double? entryLat;
  final double? entryLng;
  final String? durationMinutes;

  WorkerBoundaryEvent({
    required this.id,
    required this.workerId,
    required this.organizationCode,
    required this.exitTime,
    this.entryTime,
    required this.exitLat,
    required this.exitLng,
    this.entryLat,
    this.entryLng,
    this.durationMinutes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'worker_id': workerId,
      'organization_code': organizationCode,
      'exit_time': exitTime.toUtc().toIso8601String(),
      'entry_time': entryTime?.toUtc().toIso8601String(),
      'exit_latitude': exitLat,
      'exit_longitude': exitLng,
      'entry_latitude': entryLat,
      'entry_longitude': entryLng,
      'duration_minutes': durationMinutes,
    };
  }

  factory WorkerBoundaryEvent.fromJson(Map<String, dynamic> json) {
    return WorkerBoundaryEvent(
      id: json['id'],
      workerId: json['worker_id'],
      organizationCode: json['organization_code'],
      exitTime: TimeUtils.parseToLocal(json['exit_time']),
      entryTime: json['entry_time'] != null
          ? TimeUtils.parseToLocal(json['entry_time'])
          : null,
      exitLat: (json['exit_latitude'] as num).toDouble(),
      exitLng: (json['exit_longitude'] as num).toDouble(),
      entryLat: json['entry_latitude'] != null
          ? (json['entry_latitude'] as num).toDouble()
          : null,
      entryLng: json['entry_longitude'] != null
          ? (json['entry_longitude'] as num).toDouble()
          : null,
      durationMinutes: json['duration_minutes'],
    );
  }
}
