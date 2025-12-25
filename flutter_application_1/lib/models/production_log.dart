class ProductionLog {
  final String id;
  final String workerId;
  final String machineId;
  final String itemId;
  final String operation;
  final int quantity;
  final DateTime timestamp;
  final DateTime? startTime;
  final DateTime? endTime;
  final double latitude;
  final double longitude;
  final String? shiftName;
  final int performanceDiff;
  final String? organizationCode;
  final String? remarks;

  ProductionLog({
    required this.id,
    required this.workerId,
    required this.machineId,
    required this.itemId,
    required this.operation,
    required this.quantity,
    required this.timestamp,
    this.startTime,
    this.endTime,
    required this.latitude,
    required this.longitude,
    this.shiftName,
    this.performanceDiff = 0,
    this.organizationCode,
    this.remarks,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workerId': workerId,
      'machineId': machineId,
      'itemId': itemId,
      'operation': operation,
      'quantity': quantity,
      'timestamp': timestamp.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'shiftName': shiftName,
      'performanceDiff': performanceDiff,
      'organizationCode': organizationCode,
      'remarks': remarks,
    };
  }

  factory ProductionLog.fromJson(Map<String, dynamic> json) {
    return ProductionLog(
      id: json['id'],
      workerId: json['workerId'],
      machineId: json['machineId'],
      itemId: json['itemId'],
      operation: json['operation'],
      quantity: json['quantity'],
      timestamp: DateTime.parse(json['timestamp']),
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      latitude: json['latitude'],
      longitude: json['longitude'],
      shiftName: json['shiftName'],
      performanceDiff: json['performanceDiff'] ?? 0,
      organizationCode: json['organizationCode'],
      remarks: json['remarks'],
    );
  }
}
