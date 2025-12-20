class Worker {
  final String id;
  final String name;
  final String username;
  final String password;
  final String? organizationCode;
  final String? panCard;
  final String? aadharCard;
  final int? age;
  final String? mobileNumber;

  Worker({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    this.organizationCode,
    this.panCard,
    this.aadharCard,
    this.age,
    this.mobileNumber,
  });

  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['worker_id'] ?? '',
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      organizationCode: json['organization_code'],
      panCard: json['pan_card'],
      aadharCard: json['aadhar_card'],
      age: json['age'],
      mobileNumber: json['mobile_number'],
    );
  }
}
