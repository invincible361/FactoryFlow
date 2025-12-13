import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/item.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 30,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.factory),
            ),
            const SizedBox(width: 10),
            const Text('Admin Dashboard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Reports'),
            Tab(text: 'Workers'),
            Tab(text: 'Machines'),
            Tab(text: 'Items'),
            Tab(text: 'Shifts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ReportsTab(),
          WorkersTab(),
          MachinesTab(),
          ItemsTab(),
          ShiftsTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. REPORTS TAB
// ---------------------------------------------------------------------------
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _filter = 'All'; // All, Today, Week, Month

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  // Build the query based on filter
  dynamic _buildQuery({bool isExport = false}) {
    var query = _supabase
          .from('production_logs')
          .select('*, workers(name)'); // Join with workers table
      
    final now = DateTime.now();
    if (_filter == 'Today') {
      final startOfDay = DateTime(now.year, now.month, now.day);
      query = query.gte('created_at', startOfDay.toIso8601String());
    } else if (_filter == 'Week') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1)); // Monday
      // Reset to start of day
      final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      query = query.gte('created_at', startOfWeekDay.toIso8601String());
    } else if (_filter == 'Month') {
      final startOfMonth = DateTime(now.year, now.month, 1);
      query = query.gte('created_at', startOfMonth.toIso8601String());
    }
    
    // Apply sorting
    var transformQuery = query.order('created_at', ascending: false);

    // Apply limit if needed (only for UI view, not export)
    if (_filter == 'All' && !isExport) {
      transformQuery = transformQuery.limit(100);
    }
    
    return transformQuery;
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _buildQuery(isExport: false);
      
      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      final response = await _buildQuery(isExport: true);
      final logsToExport = List<Map<String, dynamic>>.from(response);

      if (logsToExport.isEmpty) {
        throw 'No data to export for selected filter';
      }

      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Production Report'];
      excel.delete('Sheet1'); // Remove default sheet

      // Add Headers
      sheetObject.appendRow([
        TextCellValue('Date'),
        TextCellValue('Time'),
        TextCellValue('Worker Name'),
        TextCellValue('Worker ID'),
        TextCellValue('Item ID'),
        TextCellValue('Operation'),
        TextCellValue('Quantity'),
        TextCellValue('Target'),
        TextCellValue('Surplus/Deficit'),
      ]);

      // Add Data
      for (var log in logsToExport) {
        final createdAt = DateTime.parse(log['created_at']).toLocal();
        final dateStr = DateFormat('yyyy-MM-dd').format(createdAt);
        final timeStr = DateFormat('HH:mm:ss').format(createdAt);
        
        final workerName = (log['workers'] != null && log['workers']['name'] != null) 
            ? log['workers']['name'] 
            : 'Unknown';
        
        final diff = (log['performance_diff'] ?? 0) as int;
        // Target isn't directly stored in log, but we can infer it roughly if we want, 
        // or just rely on diff. Target = Quantity - Diff.
        final qty = log['quantity'] as int;
        final target = qty - diff;

        sheetObject.appendRow([
          TextCellValue(dateStr),
          TextCellValue(timeStr),
          TextCellValue(workerName),
          TextCellValue(log['worker_id'] ?? ''),
          TextCellValue(log['item_id'] ?? ''),
          TextCellValue(log['operation'] ?? ''),
          IntCellValue(qty),
          IntCellValue(target),
          IntCellValue(diff),
        ]);
      }

      // Save and Share
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/production_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(path);
      final fileBytes = excel.save();
      if (fileBytes != null) {
        await file.writeAsBytes(fileBytes);
        
        await Share.shareXFiles([XFile(path)], text: 'Production Report ($_filter)');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export ready')));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // Aggregate logs: Worker -> Item -> Operation -> {qty, diff, workerName}
  Map<String, Map<String, Map<String, Map<String, dynamic>>>> _getAggregatedData() {
    final Map<String, Map<String, Map<String, Map<String, dynamic>>>> data = {};

    for (var log in _logs) {
      final worker = log['worker_id'] as String;
      // Extract worker name from the joined table
      final workerName = (log['workers'] != null && log['workers']['name'] != null) 
          ? log['workers']['name'] 
          : 'Unknown';
          
      final item = log['item_id'] as String;
      final op = log['operation'] as String;
      final qty = log['quantity'] as int;
      final diff = (log['performance_diff'] ?? 0) as int;

      data.putIfAbsent(worker, () => {});
      data[worker]!.putIfAbsent(item, () => {});
      data[worker]![item]!.putIfAbsent(op, () => {'qty': 0, 'diff': 0, 'workerName': workerName});
      
      final current = data[worker]![item]![op]!;
      data[worker]![item]![op] = {
        'qty': current['qty'] + qty,
        'diff': current['diff'] + diff,
        'workerName': workerName,
      };
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final aggregatedData = _getAggregatedData();

    return Column(
      children: [
        // Filter Bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Text('Filter by: ', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('Recent (100)')),
                  DropdownMenuItem(value: 'Today', child: Text('Today')),
                  DropdownMenuItem(value: 'Week', child: Text('This Week')),
                  DropdownMenuItem(value: 'Month', child: Text('This Month')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _filter = val);
                    _fetchLogs();
                  }
                },
              ),
              const Spacer(),
              if (_isExporting)
                 const Padding(
                   padding: EdgeInsets.only(right: 8.0),
                   child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                 )
              else
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.green),
                  tooltip: 'Export Excel',
                  onPressed: _exportToExcel,
                ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLogs),
            ],
          ),
        ),
        
        // Content
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty 
               ? const Center(child: Text('No records found.'))
               : ListView.builder(
                   itemCount: aggregatedData.length,
                   itemBuilder: (context, index) {
                     final workerId = aggregatedData.keys.elementAt(index);
                     final workerItems = aggregatedData[workerId]!;

                     // Calculate total surplus/deficit for worker
                     int totalWorkerDiff = 0;
                     String workerName = 'Unknown';
                     
                     workerItems.forEach((_, ops) {
                       ops.forEach((_, stats) {
                         totalWorkerDiff += (stats['diff'] as int);
                         workerName = stats['workerName'] as String;
                       });
                     });

                     final isPositive = totalWorkerDiff >= 0;

                     return Card(
                       margin: const EdgeInsets.all(8),
                       child: ExpansionTile(
                         title: Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                             Expanded(child: Text('$workerName ($workerId)', style: const TextStyle(fontWeight: FontWeight.bold))),
                             Text(
                               'Perf: ${isPositive ? '+' : ''}$totalWorkerDiff',
                               style: TextStyle(
                                 fontWeight: FontWeight.bold,
                                 color: isPositive ? Colors.green : Colors.red,
                               ),
                             ),
                           ],
                         ),
                         subtitle: Text('Worked on ${workerItems.length} Items'),
                         children: workerItems.entries.map((itemEntry) {
                           final itemId = itemEntry.key;
                           final ops = itemEntry.value;
                           
                           return Padding(
                             padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text('Item: $itemId', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                 ...ops.entries.map((opEntry) {
                                    final stats = opEntry.value;
                                    final qty = stats['qty'];
                                    final diff = stats['diff']!;
                                    final opIsPositive = diff >= 0;

                                   return Padding(
                                     padding: const EdgeInsets.only(left: 16.0, top: 2),
                                     child: Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                       children: [
                                          Text(opEntry.key),
                                          Row(
                                            children: [
                                              Text('Qty: $qty ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                              Text(
                                                '(${opIsPositive ? '+' : ''}$diff)',
                                                style: TextStyle(
                                                  color: opIsPositive ? Colors.green : Colors.red,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                       ],
                                     ),
                                   );
                                 }),
                                 const Divider(),
                               ],
                             ),
                           );
                         }).toList(),
                       ),
                     );
                   },
                 ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. WORKERS TAB
// ---------------------------------------------------------------------------
class WorkersTab extends StatefulWidget {
  const WorkersTab({super.key});

  @override
  State<WorkersTab> createState() => _WorkersTabState();
}

class _WorkersTabState extends State<WorkersTab> {
  final _supabase = Supabase.instance.client;
  final _workerIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _panController = TextEditingController();
  final _aadharController = TextEditingController();
  final _ageController = TextEditingController();
  final _mobileController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase.from('workers').select().order('name', ascending: true);
      if (mounted) {
        setState(() {
          _workers = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // Silent fail or show snackbar? Better silent for init
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteWorker(String workerId) async {
    try {
      // First delete associated production logs
      await _supabase.from('production_logs').delete().eq('worker_id', workerId);

      // Then delete the worker
      await _supabase.from('workers').delete().eq('worker_id', workerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Worker and associated logs deleted')));
        _fetchWorkers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addWorker() async {
    // Basic validation
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    final aadharRegex = RegExp(r'^[0-9]{12}$');

    if (!_panController.text.contains(panRegex)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid PAN Card Format')));
      return;
    }

    if (!_aadharController.text.contains(aadharRegex)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Aadhar Card Format (must be 12 digits)')));
      return;
    }

    try {
      await _supabase.from('workers').insert({
        'worker_id': _workerIdController.text,
        'name': _nameController.text,
        'pan_card': _panController.text,
        'aadhar_card': _aadharController.text,
        'age': int.tryParse(_ageController.text),
        'mobile_number': _mobileController.text,
        'username': _usernameController.text,
        'password': _passwordController.text, // Note: Should hash in real app
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Worker added!')));
        _clearControllers();
        _fetchWorkers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _clearControllers() {
    _workerIdController.clear();
    _nameController.clear();
    _panController.clear();
    _aadharController.clear();
    _ageController.clear();
    _mobileController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            flex: 2, // Give form some space, but list needs to scroll
            child: ListView(
              children: [
                const Text('Add New Worker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                TextField(controller: _workerIdController, decoration: const InputDecoration(labelText: 'Worker ID (e.g. W-001)')),
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full Name')),
                TextField(controller: _panController, decoration: const InputDecoration(labelText: 'PAN Card')),
                TextField(controller: _aadharController, decoration: const InputDecoration(labelText: 'Aadhar Card')),
                TextField(controller: _ageController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age')),
                TextField(controller: _mobileController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number')),
                const SizedBox(height: 16),
                const Text('Credentials (Created by Admin)', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username')),
                TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _addWorker, child: const Text('Add Worker')),
              ],
            ),
          ),
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Existing Workers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          Expanded(
            flex: 3,
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : _workers.isEmpty 
                ? const Center(child: Text('No workers found.'))
                : ListView.builder(
                    itemCount: _workers.length,
                    itemBuilder: (context, index) {
                      final worker = _workers[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text('${worker['name']} (${worker['worker_id']})'),
                          subtitle: Text('User: ${worker['username']} | Mobile: ${worker['mobile_number'] ?? 'N/A'}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteWorker(worker['worker_id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. MACHINES TAB
// ---------------------------------------------------------------------------
class MachinesTab extends StatefulWidget {
  const MachinesTab({super.key});

  @override
  State<MachinesTab> createState() => _MachinesTabState();
}

class _MachinesTabState extends State<MachinesTab> {
  final _supabase = Supabase.instance.client;
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String _type = 'CNC'; // Default

  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchMachines();
  }

  Future<void> _fetchMachines() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase.from('machines').select().order('machine_id', ascending: true);
      if (mounted) {
        setState(() {
          _machines = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMachine(String id) async {
    try {
      await _supabase.from('machines').delete().eq('machine_id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Machine deleted')));
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addMachine() async {
    try {
      await _supabase.from('machines').insert({
        'machine_id': _idController.text,
        'name': _nameController.text,
        'type': _type,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Machine added!')));
        _idController.clear();
        _nameController.clear();
        _fetchMachines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text('Add New Machine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          TextField(controller: _idController, decoration: const InputDecoration(labelText: 'Machine ID (e.g. CNC-01)')),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Machine Name')),
          DropdownButton<String>(
            value: _type,
            items: const [
              DropdownMenuItem(value: 'CNC', child: Text('CNC')),
              DropdownMenuItem(value: 'VMC', child: Text('VMC')),
            ],
            onChanged: (val) => setState(() => _type = val!),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _addMachine, child: const Text('Add Machine')),
          
          const Divider(height: 40, thickness: 2),
          const Text('Existing Machines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _machines.isEmpty 
                ? const Center(child: Text('No machines found.'))
                : ListView.builder(
                    itemCount: _machines.length,
                    itemBuilder: (context, index) {
                      final machine = _machines[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.precision_manufacturing),
                          title: Text('${machine['name']} (${machine['machine_id']})'),
                          subtitle: Text('Type: ${machine['type']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteMachine(machine['machine_id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. ITEMS TAB
// ---------------------------------------------------------------------------
class ItemsTab extends StatefulWidget {
  const ItemsTab({super.key});

  @override
  State<ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<ItemsTab> {
  final _supabase = Supabase.instance.client;
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  
  // List of operations being added
  List<OperationDetail> _operations = [];
  
  // Controllers for the current operation being added
  final _opNameController = TextEditingController();
  final _opTargetController = TextEditingController();
  XFile? _selectedImage;
  String? _uploadedImageUrl;
  bool _isUploading = false;

  List<Map<String, dynamic>> _items = [];
  bool _isLoadingItems = false;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final response = await _supabase.from('items').select().order('item_id', ascending: true);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(response);
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingItems = false);
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await _supabase.from('items').delete().eq('item_id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted')));
        _fetchItems();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = pickedFile;
        _uploadedImageUrl = null; // Reset upload status
      });
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;
    
    setState(() => _isUploading = true);
    try {
      // Use a structured path: components/{item_name}/{timestamp}_filename
      final itemNameRaw = _nameController.text.trim();
      final itemName = itemNameRaw.isNotEmpty 
          ? itemNameRaw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') 
          : 'uncategorized';
          
      final originalName = _selectedImage!.name;
      final dotIndex = originalName.lastIndexOf('.');
      
      String fileExt;
      String nameWithoutExt;
      
      if (dotIndex != -1 && dotIndex < originalName.length - 1) {
        fileExt = originalName.substring(dotIndex + 1).toLowerCase();
        nameWithoutExt = originalName.substring(0, dotIndex);
      } else {
        fileExt = 'jpg'; // Default fallback
        nameWithoutExt = originalName;
      }

      final sanitizedName = nameWithoutExt.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = 'components/$itemName/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName.$fileExt';
      
      final bytes = await _selectedImage!.readAsBytes();

      // Upload to 'factory-assets' bucket
      await _supabase.storage.from('factory-assets').uploadBinary(
        fileName,
        bytes,
        fileOptions: FileOptions(contentType: 'image/$fileExt', upsert: true),
      );
      
      final publicUrl = _supabase.storage.from('factory-assets').getPublicUrl(fileName);
      setState(() {
        _uploadedImageUrl = publicUrl;
        _isUploading = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image Uploaded!')));
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload Error: $e')));
    }
  }

  Future<void> _addOperationToList() async {
    if (_opNameController.text.isEmpty || _opTargetController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Target are required')));
       return;
    }

    // Auto-upload if image is selected but not uploaded yet
    if (_selectedImage != null && _uploadedImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading image...')));
      await _uploadImage();
      // If upload failed (url still null), stop here
      if (_uploadedImageUrl == null) return;
    }
    
    // If no image is uploaded, we just pass null
    
    setState(() {
      _operations.add(OperationDetail(
        name: _opNameController.text,
        target: int.parse(_opTargetController.text),
        imageUrl: _uploadedImageUrl,
      ));
      
      // Reset Op controllers
      _opNameController.clear();
      _opTargetController.clear();
      _selectedImage = null;
      _uploadedImageUrl = null;
    });
  }

  Future<void> _addItem() async {
    if (_idController.text.isEmpty || _nameController.text.isEmpty || _operations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields and add at least one operation')));
      return;
    }

    try {
      await _supabase.from('items').insert({
        'item_id': _idController.text,
        'name': _nameController.text,
        'operations': _operations.map((e) => e.name).toList(), // Legacy
        'operation_details': _operations.map((e) => e.toJson()).toList(), // New JSONB
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item added successfully!')));
        _idController.clear();
        _nameController.clear();
        setState(() {
          _operations.clear();
        });
        _fetchItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: ListView(
              children: [
                const Text('1. Item Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextField(controller: _idController, decoration: const InputDecoration(labelText: 'Item ID (e.g. GR-122)')),
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Item Name')),
                
                const SizedBox(height: 20),
                const Text('2. Add Operations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Card(
                  color: Colors.grey[100],
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        TextField(controller: _opNameController, decoration: const InputDecoration(labelText: 'Operation Name')),
                        TextField(
                  controller: _opTargetController, 
                  keyboardType: TextInputType.number, 
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Target Quantity'),
                ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image),
                              label: const Text('Pick Image'),
                            ),
                            const SizedBox(width: 10),
                            if (_selectedImage != null) ...[
                              Text('Image selected', style: TextStyle(color: Colors.green[800])),
                              const SizedBox(width: 10),
                              if (_uploadedImageUrl == null)
                                _isUploading 
                                   ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                                   : ElevatedButton(onPressed: _uploadImage, child: const Text('Upload'))
                              else
                                const Icon(Icons.check_circle, color: Colors.green)
                            ]
                          ],
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(onPressed: _addOperationToList, child: const Text('Add Operation to List')),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 10),
                if (_operations.isNotEmpty) ...[
                  const Text('Operations List:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._operations.map((op) => ListTile(
                    title: Text(op.name),
                    subtitle: Text('Target: ${op.target}'),
                    trailing: op.imageUrl != null ? const Icon(Icons.image, color: Colors.blue) : null,
                  )),
                ],

                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  onPressed: _addItem, 
                  child: const Text('Save Item to Database'),
                ),
              ],
            ),
          ),
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Existing Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          Expanded(
            flex: 4,
            child: _isLoadingItems
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty 
                 ? const Center(child: Text('No items found.'))
                 : ListView.builder(
                     itemCount: _items.length,
                     itemBuilder: (context, index) {
                       final item = _items[index];
                       // Count operations if possible
                       final ops = item['operation_details'] as List? ?? [];
                       return Card(
                         child: ListTile(
                           title: Text('${item['name']} (${item['item_id']})'),
                           subtitle: Text('${ops.length} Operations'),
                           trailing: IconButton(
                             icon: const Icon(Icons.delete, color: Colors.red),
                             onPressed: () => _deleteItem(item['item_id']),
                           ),
                         ),
                       );
                     },
                   ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. SHIFTS TAB
// ---------------------------------------------------------------------------
class ShiftsTab extends StatefulWidget {
  const ShiftsTab({super.key});

  @override
  State<ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<ShiftsTab> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  Future<void> _addShift() async {
    try {
      await _supabase.from('shifts').insert({
        'name': _nameController.text,
        'start_time': _startController.text,
        'end_time': _endController.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift added!')));
        _nameController.clear();
        _startController.clear();
        _endController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Shift Name (e.g. Morning)')),
          TextField(controller: _startController, decoration: const InputDecoration(labelText: 'Start Time (e.g. 08:00)')),
          TextField(controller: _endController, decoration: const InputDecoration(labelText: 'End Time (e.g. 16:00)')),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _addShift, child: const Text('Add Shift')),
        ],
      ),
    );
  }
}
