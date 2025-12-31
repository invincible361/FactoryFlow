import 'package:file_picker/file_picker.dart';

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Item && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class OperationDetail {
  final String name;
  final int target;
  final String? imageUrl;
  final String? pdfUrl;
  final PlatformFile? newFile; // For local upload handling
  final String? existingUrl; // To keep track of existing image URL during edit
  final String? existingPdfUrl; // To keep track of existing PDF URL during edit
  final String? createdAt;

  OperationDetail({
    required this.name,
    required this.target,
    this.imageUrl,
    this.pdfUrl,
    this.newFile,
    this.existingUrl,
    this.existingPdfUrl,
    this.createdAt,
  });

  factory OperationDetail.fromJson(Map<String, dynamic> json) {
    return OperationDetail(
      name: json['name'] ?? '',
      target: json['target'] ?? 0,
      imageUrl: json['imageUrl'] ?? json['image_url'],
      pdfUrl: json['pdfUrl'] ?? json['pdf_url'],
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'target': target,
      'imageUrl': imageUrl,
      'pdfUrl': pdfUrl,
      'createdAt': createdAt,
    };
  }
}
