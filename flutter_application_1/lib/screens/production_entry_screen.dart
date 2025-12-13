import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/machine.dart';
import '../models/production_log.dart';
import '../models/worker.dart';
import '../models/item.dart';
import '../services/location_service.dart';
import '../services/log_service.dart';

class ProductionEntryScreen extends StatefulWidget {
  final Worker worker;
  const ProductionEntryScreen({super.key, required this.worker});

  @override
  State<ProductionEntryScreen> createState() => _ProductionEntryScreenState();
}

class _ProductionEntryScreenState extends State<ProductionEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final LocationService _locationService = LocationService();
  
  Machine? _selectedMachine;
  Item? _selectedItem;
  String? _selectedOperation;
  final TextEditingController _quantityController = TextEditingController();
  
  bool _isSaving = false;
  String _statusMessage = '';

  // Data State
  List<Machine> _machines = [];
  List<Item> _items = [];
  bool _isLoadingData = true;

  // Location State
  Position? _currentPosition;
  String _locationStatus = 'Checking location...';
  bool _isLocationLoading = false;

  // Timer State
  Timer? _timer;
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  bool _isTimerRunning = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _checkLocation();
  }

  Future<void> _fetchData() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Fetch Machines
      final machinesResponse = await supabase.from('machines').select();
      final machinesList = (machinesResponse as List).map((data) {
        return Machine(
          id: data['machine_id'],
          name: data['name'],
          type: data['type'] == 'CNC' ? MachineType.cnc : MachineType.vmc,
          items: [], // Will link items later if needed, or keep empty for now as selection is separate
        );
      }).toList();

      // Fetch Items
      final itemsResponse = await supabase.from('items').select();
      final itemsList = (itemsResponse as List).map((data) {
        return Item(
          id: data['item_id'],
          name: data['name'],
          operations: List<String>.from(data['operations'] ?? []),
          operationDetails: (data['operation_details'] as List? ?? [])
              .map((od) => OperationDetail.fromJson(od))
              .toList(),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _machines = machinesList;
          _items = itemsList;
          _isLoadingData = false;
          
          // Reset selections to avoid Dropdown error since object references changed
          _selectedMachine = null;
          _selectedItem = null;
          _selectedOperation = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
        setState(() => _isLoadingData = false);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _checkLocation() async {
    setState(() {
      _isLocationLoading = true;
      _locationStatus = 'Fetching location...';
    });

    try {
      final position = await _locationService.getCurrentLocation();
      final isInside = _locationService.isInsideFactory(position);
      
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _locationStatus = isInside 
              ? 'Inside Factory ✅' 
              : 'Outside Factory ❌';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationStatus = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
      }
    }
  }

  void _startTimer() {
    if (_selectedMachine == null || _selectedItem == null || _selectedOperation == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select Machine, Item and Operation first.')));
       return;
    }

    setState(() {
      _isTimerRunning = true;
      _startTime = DateTime.now();
      _elapsed = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  String _getShiftName(DateTime time) {
    // Shift 1: 7:30 AM to 7:30 PM (Day)
    // Shift 2: 7:30 PM to 7:30 AM (Night)
    
    final minutes = time.hour * 60 + time.minute;
    final dayStart = 7 * 60 + 30; // 450
    final dayEnd = 19 * 60 + 30; // 1170
    
    if (minutes >= dayStart && minutes < dayEnd) {
      return 'Day Shift (7:30 AM - 7:30 PM)';
    } else {
      return 'Night Shift (7:30 PM - 7:30 AM)';
    }
  }

  OperationDetail? _getCurrentOperationDetail() {
    if (_selectedItem == null || _selectedOperation == null) return null;
    try {
      return _selectedItem!.operationDetails.firstWhere(
        (d) => d.name == _selectedOperation,
      );
    } catch (e) {
      return null;
    }
  }

  void _stopTimerAndFinish() {
    _timer?.cancel();
    final endTime = DateTime.now();
    
    // Show dialog to enter quantity
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Production Finished'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Duration: ${_formatDuration(_elapsed)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Enter Quantity Produced',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
               if (_quantityController.text.isEmpty) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter quantity')));
                 return;
               }
               final quantity = int.tryParse(_quantityController.text);
               if (quantity == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid quantity')));
                  return;
               }

               // Target Validation
               final detail = _getCurrentOperationDetail();
               if (detail != null && detail.target > 0) {
                 final diff = quantity - detail.target;
                 final isTargetMet = diff >= 0;
                 
                 Navigator.pop(context); // Close input dialog
                 
                 // Show Result Dialog
                 showDialog(
                   context: context,
                   barrierDismissible: false,
                   builder: (context) => AlertDialog(
                     title: Text(isTargetMet ? 'Target Met! 🎉' : 'Target Missed ⚠️'),
                     content: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         isTargetMet 
                            ? const Icon(Icons.sentiment_very_satisfied, size: 60, color: Colors.green)
                            : const Icon(Icons.sentiment_dissatisfied, size: 60, color: Colors.orange),
                         const SizedBox(height: 16),
                         Text(
                           isTargetMet 
                              ? 'Produced: $quantity (Target: ${detail.target})\nSurplus: +$diff' 
                              : 'Produced: $quantity (Target: ${detail.target})\nDeficit: $diff',
                           textAlign: TextAlign.center,
                           style: TextStyle(
                             fontWeight: FontWeight.bold,
                             color: isTargetMet ? Colors.green : Colors.red,
                             fontSize: 16,
                           ),
                         ),
                       ],
                     ),
                     actions: [
                       TextButton(
                         onPressed: () {
                           Navigator.pop(context);
                           _saveLog(endTime, diff);
                         },
                         child: const Text('Save Log'),
                       )
                     ],
                   ),
                 );
               } else {
                 Navigator.pop(context);
                 _saveLog(endTime, 0); 
               }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _saveLog(DateTime endTime, int performanceDiff) async {
    setState(() {
      _isSaving = true;
      _statusMessage = 'Saving log...';
    });

    try {
      // Re-fetch location for the record
      Position position;
      try {
        position = await _locationService.getCurrentLocation();
      } catch (e) {
        // Use last known position if fetch fails
        if (_currentPosition != null) {
          position = _currentPosition!;
        } else {
           throw Exception('Could not verify location');
        }
      }

      final log = ProductionLog(
        id: DateTime.now().toIso8601String(),
        workerId: widget.worker.id,
        machineId: _selectedMachine!.id,
        itemId: _selectedItem!.id,
        operation: _selectedOperation!,
        quantity: int.parse(_quantityController.text),
        timestamp: DateTime.now(),
        startTime: _startTime,
        endTime: endTime,
        latitude: position.latitude,
        longitude: position.longitude,
        shiftName: _getShiftName(DateTime.now()),
        performanceDiff: performanceDiff,
      );

      await LogService().addLog(log);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log saved successfully to database!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Reset State
      setState(() {
         _isTimerRunning = false;
         _selectedOperation = null;
         _selectedItem = null;
         _selectedMachine = null;
         _quantityController.clear();
         _elapsed = Duration.zero;
      });

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = '';
        });
      }
    }
  }

  List<String> _getFilteredOperations() {
    if (_selectedItem == null) return [];
    List<String> ops = _selectedItem!.operations;
    
    // Logic for Gear 122 based on machine type
    if (_selectedItem!.id == 'GR-122' && _selectedMachine != null) {
       if (_selectedMachine!.type == MachineType.cnc) {
         ops = ops.where((op) => op.contains('CNC')).toList();
       } else if (_selectedMachine!.type == MachineType.vmc) {
         ops = ops.where((op) => op.contains('VMC')).toList();
       }
    }
    return ops;
  }

  Widget _buildErrorWidget() {
    return Container(
      height: 250,
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 50, color: Colors.grey),
            Text('Could not load image'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Production'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              _fetchData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing data...')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              // Assuming navigating back to root handles logout or we push LoginScreen
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Location Status Card
              Card(
                color: _locationStatus.contains('Inside') ? Colors.green[50] : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Current Location:', style: TextStyle(fontWeight: FontWeight.bold)),
                          if (_isLocationLoading)
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _checkLocation,
                              tooltip: 'Refresh Location',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentPosition != null 
                          ? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}'
                          : 'Unknown',
                        style: const TextStyle(fontFamily: 'Monospace'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _locationStatus,
                        style: TextStyle(
                          color: _locationStatus.contains('Inside') ? Colors.green[800] : Colors.red[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_isLoadingData)
                const Center(child: CircularProgressIndicator())
              else ...[
                DropdownButtonFormField<Machine>(
                  decoration: const InputDecoration(labelText: 'Select Machine'),
                  value: _selectedMachine,
                  items: _machines.map((machine) {
                    return DropdownMenuItem(
                      value: machine,
                      child: Text('${machine.name} (${machine.id})'),
                    );
                  }).toList(),
                  onChanged: _isTimerRunning ? null : (Machine? newValue) {
                    setState(() {
                      _selectedMachine = newValue;
                      _selectedItem = null;
                      _selectedOperation = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Item>(
                  decoration: const InputDecoration(labelText: 'Select Item/Component'),
                  value: _selectedItem,
                  items: _items.map((item) {
                    return DropdownMenuItem(
                      value: item,
                      child: Text('${item.name} (${item.id})'),
                    );
                  }).toList(),
                  onChanged: _isTimerRunning ? null : (Item? newValue) {
                    setState(() {
                      _selectedItem = newValue;
                      _selectedOperation = null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 10),
              
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Select Operation'),
                value: _selectedOperation,
                items: _getFilteredOperations().map((op) {
                  return DropdownMenuItem(
                    value: op,
                    child: Text(op),
                  );
                }).toList(),
                onChanged: _isTimerRunning ? null : (value) {
                  setState(() {
                    _selectedOperation = value;
                  });
                },
              ),
              if (_selectedOperation != null) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final detail = _getCurrentOperationDetail();
                    if (detail != null && detail.imageUrl != null && detail.imageUrl!.isNotEmpty && detail.imageUrl != 'logo.png') {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Operation Image:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          detail.imageUrl!.startsWith('http') 
                          ? Image.network(
                              detail.imageUrl!,
                              height: 250,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return SizedBox(
                                  height: 250,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return _buildErrorWidget();
                              },
                            )
                          : Image.asset(
                              'assets/images/${detail.imageUrl!}',
                              height: 250,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildErrorWidget();
                              },
                            ),
                          if (detail.target > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text('Target: ${detail.target}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            ),
                        ],
                      );
                    } else if (detail != null && detail.target > 0) {
                       return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text('Target: ${detail.target}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
              const SizedBox(height: 30),

              if (!_isTimerRunning)
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    onPressed: (_selectedMachine != null && _selectedItem != null && _selectedOperation != null)
                        ? _startTimer
                        : null,
                    child: const Text('Start Production Timer', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                )
              else
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Column(
                        children: [
                           const Text('Production In Progress', style: TextStyle(fontSize: 16, color: Colors.blue)),
                           const SizedBox(height: 10),
                           Text(
                             _formatDuration(_elapsed),
                             style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, fontFamily: 'Monospace'),
                           ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: _stopTimerAndFinish,
                        child: const Text('Stop & Enter Quantity', style: TextStyle(color: Colors.white, fontSize: 18)),
                      ),
                    ),
                  ],
                ),
                
              if (_isSaving)
                 const Padding(
                   padding: EdgeInsets.only(top: 20),
                   child: Center(child: CircularProgressIndicator()),
                 ),
            ],
          ),
        ),
      ),
    );
  }
}
