import 'item.dart';

class Machine {
  final String id;
  final String name;
  final String type;
  final List<Item> items;

  final String? photoUrl;

  Machine({
    required this.id,
    required this.name,
    required this.type,
    required this.items,
    this.photoUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Machine && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
