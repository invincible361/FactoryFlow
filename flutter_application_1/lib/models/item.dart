import 'package:image_picker/image_picker.dart';

class Item {
  final String id;
  final String name;
  final List<String> operations; // Legacy support or just names
  final List<OperationDetail> operationDetails;

  Item({
    required this.id,
    required this.name,
    required this.operations,
    this.operationDetails = const [],
  });
}

class OperationDetail {
  final String name;
  final int target;
  final String? imageUrl;
  final XFile? imageFile; // For local upload handling (Web compatible)

  OperationDetail({
    required this.name,
    required this.target,
    this.imageUrl,
    this.imageFile,
  });

  factory OperationDetail.fromJson(Map<String, dynamic> json) {
    return OperationDetail(
      name: json['name'] ?? '',
      target: json['target'] ?? 0,
      imageUrl: json['imageUrl'] ?? json['image_url'], // Handle both cases if needed
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'target': target,
      'imageUrl': imageUrl, // Consistent naming
    };
  }
}
