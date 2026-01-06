import '../utils/time_utils.dart';

class ProductionLog {
  final String id;
  final String employeeId;
  final String machineId;
  final String itemId;
  final String operation;
  final int quantity;
  final DateTime? timestamp;
  final DateTime? startTime;
  final DateTime? endTime;
  final double latitude;
  final double longitude;
  final String? shiftName;
  final int performanceDiff;
  final String? organizationCode;
  final String? remarks;
  final bool? createdBySupervisor;
  final String? supervisorId;

  ProductionLog({
    required this.id,
    required this.employeeId,
    required this.machineId,
    required this.itemId,
    required this.operation,
    required this.quantity,
    this.timestamp,
    this.startTime,
    this.endTime,
    required this.latitude,
    required this.longitude,
    this.shiftName,
    this.performanceDiff = 0,
    this.organizationCode,
    this.remarks,
    this.createdBySupervisor = false,
    this.supervisorId,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'worker_id': employeeId, // Database uses worker_id
      'machine_id': machineId, // Database uses machine_id
      'item_id': itemId, // Database uses item_id
      'operation': operation,
      'quantity': quantity,
      'latitude': latitude,
      'longitude': longitude,
      'shift_name': shiftName,
      'performance_diff': performanceDiff, // Database uses performance_diff
      'organization_code': organizationCode,
      'remarks': remarks,
      'created_by_supervisor': createdBySupervisor,
      'supervisor_id': supervisorId,
    };

    if (timestamp != null) {
      data['timestamp'] = timestamp?.toUtc().toIso8601String();
    }
    if (startTime != null) {
      data['start_time'] = startTime?.toUtc().toIso8601String();
    }
    if (endTime != null) {
      data['end_time'] = endTime?.toUtc().toIso8601String();
    }

    return data;
  }

  factory ProductionLog.fromJson(Map<String, dynamic> json) {
    return ProductionLog(
      id: json['id'],
      employeeId: json['employeeId'],
      machineId: json['machineId'],
      itemId: json['itemId'],
      operation: json['operation'],
      quantity: json['quantity'],
      timestamp: TimeUtils.parseToLocal(json['timestamp']),
      startTime: json['startTime'] != null
          ? TimeUtils.parseToLocal(json['startTime'])
          : null,
      endTime: json['endTime'] != null
          ? TimeUtils.parseToLocal(json['endTime'])
          : null,
      latitude: json['latitude'],
      longitude: json['longitude'],
      shiftName: json['shiftName'],
      performanceDiff: json['performanceDiff'] ?? 0,
      organizationCode: json['organizationCode'],
      remarks: json['remarks'],
      createdBySupervisor: json['createdBySupervisor'] ?? false,
      supervisorId: json['supervisorId'],
    );
  }
}
