import 'item.dart';

enum MachineType { cnc, vmc }

class Machine {
  final String id;
  final String name;
  final MachineType type;
  final List<Item> items;

  Machine({
    required this.id,
    required this.name,
    required this.type,
    required this.items,
  });
}
