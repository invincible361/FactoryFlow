import '../models/machine.dart';
import '../models/employee.dart';
import '../models/item.dart';

class MockData {
  static final List<Machine> machines = _generateMachines();
  static final List<Employee> employees = _generateEmployees();

  static List<Employee> _generateEmployees() {
    List<Employee> list = [];
    for (int i = 1; i <= 50; i++) {
      list.add(Employee(
        id: 'E-${i.toString().padLeft(3, '0')}',
        name: 'Employee $i',
        username: 'employee$i',
        password: 'password$i',
      ));
    }
    return list;
  }

  static List<Machine> _generateMachines() {
    List<Machine> list = [];
    
    // Operations sets
    final retailerOps = ['Operation 1', 'Operation 2', 'Operation 3'];
    final seatPipeOps = ['Operation 1', 'Operation 2'];
    final gear1568Ops = ['Operation 1'];
    final gear122Ops = [
      'CNC Op 1', 'CNC Op 2', 'CNC Op 3', 'CNC Op 4',
      'VMC Op 1', 'VMC Op 2'
    ];
    final gear1708kOps = ['Operation 1', 'Operation 2', 'Operation 3'];
    final washerOps = ['Operation 1', 'Operation 2'];
    final shaftOps = ['Operation 1', 'Operation 2', 'Operation 3'];
    final gear24178Ops = ['Operation 1', 'Operation 2', 'Operation 3'];
    final flangeBoltOps = ['Operation 1'];

    // Create items
    final items = [
      Item(id: 'RET-001', name: 'Retailer', operations: retailerOps),
      Item(id: 'SP-001', name: 'Seat Pipe', operations: seatPipeOps),
      Item(id: 'GR-1568', name: 'Gear 1568', operations: gear1568Ops),
      Item(id: 'GR-122', name: 'Gear 122', operations: gear122Ops),
      Item(id: 'GR-1708K', name: 'Gear 1708k', operations: gear1708kOps),
      Item(id: 'WS-001', name: 'Washer', operations: washerOps),
      Item(id: 'SH-001', name: 'Shaft', operations: shaftOps),
      Item(id: 'GR-24178', name: 'Gear 24178', operations: gear24178Ops),
      Item(id: 'FB-001', name: 'Flange Bolt', operations: flangeBoltOps),
    ];

    // 25 CNC Machines
    for (int i = 1; i <= 25; i++) {
      list.add(Machine(
        id: 'CNC-$i',
        name: 'CNC Machine $i',
        type: 'CNC',
        items: items, // All items available for now
      ));
    }
    // 4 VMC Machines
    for (int i = 1; i <= 4; i++) {
      list.add(Machine(
        id: 'VMC-$i',
        name: 'VMC Machine $i',
        type: 'VMC',
        items: items, // All items available for now
      ));
    }
    return list;
  }

  // Factory Location (Updated: 28°53'09.5"N 76°37'43.3"E)
  // Decimal: 28.885972, 76.628694  
  static const double factoryLat = 28.885977164518724 ; 
  static const double factoryLng =76.62871441958333 ;
  static const double factoryRadiusMeters = 500.0; // 500 meters radius  28.72761822694236    76.87084350897517
}
