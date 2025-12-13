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

  OperationDetail({
    required this.name,
    required this.target,
    this.imageUrl,
  });

  factory OperationDetail.fromJson(Map<String, dynamic> json) {
    return OperationDetail(
      name: json['name'] ?? '',
      target: json['target'] ?? 0,
      imageUrl: json['image_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'target': target,
      'image_url': imageUrl,
    };
  }
}
