import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:factoryflow_core/services/version_service.dart';
import 'package:factoryflow_core/ui_components/update_dialog.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'screens/login_screen.dart';
import 'app_theme.dart';

// Background task identifiers
const String syncLocationTask = "syncLocationTask";
const String shiftEndReminderTask = "shiftEndReminderTask";
const String checkForUpdateTask = "checkForUpdateTask";

// Periodic background timer for location checks
Timer? _backgroundOneMinuteTimer;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Workmanager: Executing task "$task"');
    try {
      try {
        await SupabaseService.initialize().timeout(const Duration(seconds: 10));
        debugPrint('Supabase initialized successfully');
      } catch (e) {
        debugPrint('Supabase initialization failed or timed out: $e');
      }
      await NotificationService.initialize();

      if (task == syncLocationTask || task == Workmanager.iOSBackgroundTask) {
        debugPrint('Workmanager: Handling syncLocationTask (or iOS fetch)');
        await handleBackgroundLocation();
      } else if (task == shiftEndReminderTask) {
        debugPrint('Workmanager: Handling shiftEndReminderTask');
        await _handleShiftEndReminder();
      } else if (task == checkForUpdateTask) {
        debugPrint('Workmanager: Handling checkForUpdateTask');
        await _handleBackgroundUpdateCheck();
      }
      debugPrint('Workmanager: Task "$task" completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('Workmanager: Task "$task" failed with error: $e');
      return Future.value(false);
    }
  });
}

@pragma('vm:entry-point')
void backgroundServiceOnStart(ServiceInstance service) async {
  // Ensure plugins are registered in the background isolate
  DartPluginRegistrant.ensureInitialized();
  try {
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });

      service.on('update').listen((event) {
        if (event != null) {
          service.setForegroundNotificationInfo(
            title: event['title'] ?? "Location Tracking Active",
            content: event['content'] ?? "",
          );
        }
      });

      service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: "Location Tracking Active",
        content: "Service initializing...",
      );
    }

    WidgetsFlutterBinding.ensureInitialized();
    try {
      await SupabaseService.initialize().timeout(const Duration(seconds: 10));
    } catch (_) {}
    await NotificationService.initialize();
    await _flushQueuedGateEvents();

    await _showNotification(
      "Background Service Started",
      "FactoryFlow is now tracking your location in the background.",
    );

    // Immediate check to capture current state
    try {
      await handleBackgroundLocation(service);
    } catch (_) {}

    // Use a longer interval for the periodic timer and let the stream be the primary driver
    _backgroundOneMinuteTimer?.cancel();
    _backgroundOneMinuteTimer = Timer.periodic(const Duration(minutes: 2), (
      timer,
    ) async {
      try {
        await _flushQueuedGateEvents();
        // Periodic safety check
        debugPrint('Periodic background safety check triggered');
        await handleBackgroundLocation(service);
      } catch (e) {
        debugPrint('Periodic background scan error: $e');
      }
    });

    // More aggressive stream for background spoofing detection
    Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Smaller distance filter
        intervalDuration: const Duration(seconds: 10), // Every 10 seconds
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "FactoryFlow is tracking your location",
          notificationTitle: "Location Service",
          enableWakeLock: true,
        ),
      ),
    ).listen((position) async {
      try {
        debugPrint(
          'Background stream update: ${position.latitude}, ${position.longitude}',
        );
        LocationService.lastValidPosition = position;
        await _flushQueuedGateEvents();
        await handleBackgroundLocation(service);
      } catch (e) {
        debugPrint('Background stream location error: $e');
      }
    });
  } catch (e) {
    debugPrint('Background service start error: $e');
    await _showNotification("Service Start Failed", e.toString());
  }
}

@pragma('vm:entry-point')
bool iosBackground(ServiceInstance service) {
  return true;
}

Future<void> _handleBackgroundUpdateCheck() async {
  try {
    final updateInfo = await VersionService.checkForUpdate('worker');
    if (updateInfo != null) {
      final latestVersion = updateInfo['latestVersion'];
      await _showNotification(
        "New Update Available",
        "A new version ($latestVersion) of FactoryFlow is available. Open the app to update.",
      );
    }
  } catch (e) {
    debugPrint('Background update check error: $e');
  }
}

Future<void> checkGeofence(Position pos) async {
  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getString('worker_id');
  final orgCode = prefs.getString('org_code');
  final isTimerRunning = prefs.getBool('persisted_is_timer_running') ?? false;

  if (workerId == null || orgCode == null) return;

  final lat = prefs.getDouble('factory_lat');
  final lng = prefs.getDouble('factory_lng');
  final radius =
      prefs.getDouble('geofence_radius') ?? prefs.getDouble('factory_radius');

  if (lat == null || lng == null || radius == null) {
    debugPrint('checkGeofence: Missing factory coordinates/radius');
    return;
  }

  // Local state: using 'is_inside' as requested by Core Principle
  final isInside = prefs.getBool('is_inside') ?? true;

  final distance = Geolocator.distanceBetween(
    pos.latitude,
    pos.longitude,
    lat,
    lng,
  );

  final isCurrentlyInside = distance <= radius;

  debugPrint('----------------------------------------');
  debugPrint('📍 LOCATION SCAN: ${DateTime.now().toString()}');
  debugPrint('Coords: ${pos.latitude}, ${pos.longitude}');
  debugPrint(
    'Distance: ${distance.toStringAsFixed(1)}m | Radius: ${radius.toStringAsFixed(1)}m',
  );
  debugPrint(
    'Status: ${isCurrentlyInside ? "INSIDE ✅" : "OUTSIDE ❌"} (Old: ${isInside ? "INSIDE" : "OUTSIDE"})',
  );
  debugPrint('----------------------------------------');

  const buffer = 20.0; // meters (GPS drift protection)

  // EXIT
  if (distance > radius + buffer && isInside) {
    debugPrint('checkGeofence: EXIT DETECTED');
    await prefs.setBool('is_inside', false);
    await sendGateEvent(pos, 'exit');

    if (isTimerRunning) {
      await _handleWorkAbandonment(pos, workerId, orgCode);
    } else {
      await _notifyOutsideArea(pos, workerId, orgCode);
    }
  }

  // ENTRY
  if (distance <= radius - buffer && !isInside) {
    debugPrint('checkGeofence: ENTRY DETECTED');
    await prefs.setBool('is_inside', true);
    await sendGateEvent(pos, 'entry');

    if (isTimerRunning) {
      await _handleWorkerReturn(pos, workerId, orgCode);
    }
  }
}

Future<void> sendGateEvent(Position pos, String type) async {
  debugPrint(
    'sendGateEvent: Sending $type event at ${pos.latitude}, ${pos.longitude}',
  );
  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getString('worker_id');
  final orgCode = prefs.getString('org_code');
  if (workerId == null || orgCode == null) return;

  try {
    // 1. Insert into gate_events (Newer table for summaries/attendance)
    await Supabase.instance.client.from('gate_events').insert({
      'worker_id': workerId,
      'organization_code': orgCode,
      'event_type': type,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      // 'timestamp' removed to use server-side now() for audit accuracy
    });

    // 2. Insert into worker_boundary_events (Older table used by Admin/Supervisor apps)
    await Supabase.instance.client.from('worker_boundary_events').insert({
      'id': const Uuid().v4(),
      'worker_id': workerId,
      'organization_code': orgCode,
      'type': type,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'is_inside': type == 'entry',
    });
    debugPrint('sendGateEvent: Successfully synced to both tables');
  } catch (e) {
    // Queue locally if offline
    final queuedStr = prefs.getString('queued_gate_events');
    final List<dynamic> queued = queuedStr != null ? jsonDecode(queuedStr) : [];
    queued.add({
      'worker_id': workerId,
      'organization_code': orgCode,
      'event_type': type,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      // 'timestamp' removed to use server-side now() for audit accuracy
    });
    await prefs.setString('queued_gate_events', jsonEncode(queued));
  }
}

Future<void> _handleWorkAbandonment(
  Position pos,
  String workerId,
  String orgCode,
) async {
  final prefs = await SharedPreferences.getInstance();
  final workerName = prefs.getString('worker_name') ?? 'Worker';
  final eventId = const Uuid().v4();

  try {
    await Supabase.instance.client.from('production_outofbounds').insert({
      'id': eventId,
      'worker_id': workerId,
      'worker_name': workerName,
      'organization_code': orgCode,
      // 'exit_time' omitted to use server-side now()
      'exit_latitude': pos.latitude,
      'exit_longitude': pos.longitude,
    });
    await prefs.setString('active_work_abandonment_id', eventId);
  } catch (e) {
    debugPrint('Abandonment log error: $e');
  }

  final timestamp = TimeUtils.formatTo12Hour(
    TimeUtils.nowIst(),
    format: 'hh:mm a',
  );
  final locationStr =
      "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";

  await _showNotification(
    "Work Abandonment Alert! ($timestamp)",
    "You left the factory area while production is running. Please return immediately.",
  );

  try {
    await Supabase.instance.client.from('notifications').insert({
      'organization_code': orgCode,
      'title': 'Work Abandonment Alert',
      'body':
          '$workerName left the factory area at $timestamp while production is running. Location: $locationStr',
      'type': 'work_abandonment',
      'worker_id': workerId,
      'worker_name': workerName,
    });
  } catch (_) {}
}

Future<void> _notifyOutsideArea(
  Position pos,
  String workerId,
  String orgCode,
) async {
  final prefs = await SharedPreferences.getInstance();
  final workerName = prefs.getString('worker_name') ?? 'Worker';
  final timestamp = TimeUtils.formatTo12Hour(
    TimeUtils.nowIst(),
    format: 'hh:mm a',
  );
  final locationStr =
      "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";

  try {
    await Supabase.instance.client.from('notifications').insert({
      'organization_code': orgCode,
      'title': 'Worker Outside Area',
      'body':
          '$workerName left the factory area at $timestamp. Location: $locationStr',
      'type': 'outside_area',
      'worker_id': workerId,
      'worker_name': workerName,
    });
  } catch (_) {}
}

Future<void> _handleWorkerReturn(
  Position pos,
  String workerId,
  String orgCode,
) async {
  final prefs = await SharedPreferences.getInstance();
  final activeEventId = prefs.getString('active_work_abandonment_id');
  if (activeEventId == null) return;

  final workerName = prefs.getString('worker_name') ?? 'Worker';
  final timestamp = TimeUtils.formatTo12Hour(TimeUtils.nowIst());

  try {
    await Supabase.instance.client.rpc(
      'handle_worker_return',
      params: {
        'event_id': activeEventId,
        'entry_lat': pos.latitude,
        'entry_lng': pos.longitude,
      },
    );
  } catch (e) {
    debugPrint('RPC handle_worker_return failed: $e');
    try {
      await Supabase.instance.client
          .from('production_outofbounds')
          .update({
            // 'entry_time' omitted to use server-side now() via column default or trigger if possible
            // But since it's an update, we should use DB-side now() if possible.
            // In Flutter Supabase client, we can't easily do 'entry_time': 'now()'.
            // However, our RPC handles this. If RPC fails, we fallback to update.
            'entry_time': DateTime.now().toUtc().toIso8601String(),
            'entry_latitude': pos.latitude,
            'entry_longitude': pos.longitude,
          })
          .eq('id', activeEventId);
    } catch (_) {}
  }

  await prefs.remove('active_work_abandonment_id');

  try {
    await Supabase.instance.client.from('notifications').insert({
      'organization_code': orgCode,
      'title': 'Worker Returned to Work',
      'body': '$workerName returned to the factory area at $timestamp.',
      'type': 'return',
      'worker_id': workerId,
      'worker_name': workerName,
    });
  } catch (_) {}
}

bool _isLocationHandling = false;

Future<Map<String, dynamic>> handleBackgroundLocation([
  ServiceInstance? service,
]) async {
  if (_isLocationHandling) {
    debugPrint('handleBackgroundLocation: Already running, skipping');
    return {'isInside': null, 'position': null};
  }
  _isLocationHandling = true;

  try {
    try {
      debugPrint('handleBackgroundLocation: Triggered');
      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getString('worker_id');
      final workerRole = (prefs.getString('worker_role') ?? 'worker')
          .toLowerCase();
      final orgCode = prefs.getString('org_code');

      if (workerId == null || orgCode == null) {
        return {'isInside': null, 'position': null};
      }

      // Only track boundary events and abandonment for 'worker' role
      if (workerRole != 'worker') {
        return {'isInside': null, 'position': null};
      }

      final locationService = LocationService();
      final position = await locationService
          .getCurrentLocation(
            requestAlways: false,
            allowPermissionDialog: false,
          )
          .timeout(
            const Duration(seconds: 180),
          ) // Safety timeout for all stages
          .catchError((e) async {
            final errorStr = e.toString();
            debugPrint('Location fetch error: $errorStr');

            // Only notify if it's a permanent error (permissions/disabled)
            // Don't spam notifications for transient timeouts in background
            if (errorStr.contains('denied') ||
                errorStr.contains('disabled') ||
                errorStr.contains('permanently')) {
              await _showNotification("Location Permission Error", errorStr);
            } else {
              // Log timeout but don't show intrusive notification
              debugPrint('Transient location error (will retry): $errorStr');
            }

            // Return the globally cached last valid position if available
            if (LocationService.lastValidPosition != null) {
              debugPrint(
                'handleBackgroundLocation: Returning cached lastValidPosition after fetch error',
              );
              return LocationService.lastValidPosition!;
            }

            return Position(
              longitude: 0,
              latitude: 0,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
          });

      if (position.latitude == 0 && position.longitude == 0) {
        return {'isInside': null, 'position': null};
      }

      // Ensure factory info is cached
      double? lat = prefs.getDouble('factory_lat');
      double? lng = prefs.getDouble('factory_lng');
      double? radius =
          prefs.getDouble('geofence_radius') ??
          prefs.getDouble('factory_radius');

      if (lat == null || lng == null || radius == null) {
        final org = await Supabase.instance.client
            .from('organizations')
            .select()
            .eq('organization_code', orgCode)
            .maybeSingle();

        if (org != null) {
          lat = (org['latitude'] ?? 0.0) * 1.0;
          lng = (org['longitude'] ?? 0.0) * 1.0;
          radius = (org['radius_meters'] ?? 1000.0) * 1.0;

          await prefs.setDouble('factory_lat', lat!);
          await prefs.setDouble('factory_lng', lng!);
          await prefs.setDouble('factory_radius', radius!);
          await prefs.setDouble('geofence_radius', radius);
        }
      }

      if (lat != null && lng != null && radius != null) {
        if (!prefs.containsKey('is_inside')) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            lat,
            lng,
          );
          final initiallyInside = distance <= radius;
          await prefs.setBool('is_inside', initiallyInside);
          debugPrint(
            'handleBackgroundLocation: Initialized is_inside to $initiallyInside (distance: ${distance.toStringAsFixed(1)}m, radius: ${radius}m)',
          );
        }

        final oldIsInside = prefs.getBool('is_inside');

        debugPrint(
          'handleBackgroundLocation: Triggering geofence check at ${position.latitude}, ${position.longitude}',
        );
        // Use the unified geofence logic
        await checkGeofence(position);

        final isInside = prefs.getBool('is_inside') ?? true;

        // Only notify if state changed (or if it was never set)
        final timestamp = TimeUtils.formatTo12Hour(
          TimeUtils.nowIst(),
          format: 'hh:mm a',
        );
        if (oldIsInside != isInside) {
          await _showNotification(
            "Location Status Changed ($timestamp)",
            "You are now ${isInside ? 'INSIDE' : 'OUTSIDE'} the factory area.",
          );
        }

        // Heartbeat notification update for testing visibility
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "Tracking Active ($timestamp)",
            content:
                "Status: ${isInside ? 'INSIDE' : 'OUTSIDE'} | Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}",
          );
        } else if (service != null) {
          service.invoke('update', {
            "title": "Tracking Active ($timestamp)",
            "content":
                "Status: ${isInside ? 'INSIDE' : 'OUTSIDE'} | Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}",
          });
        }

        return {'isInside': isInside, 'position': position};
      }
    } catch (e) {
      debugPrint('Background location error: $e');
    }
    return {'isInside': null, 'position': null};
  } finally {
    _isLocationHandling = false;
  }
}

Future<void> _flushQueuedGateEvents() async {
  final prefs = await SharedPreferences.getInstance();
  final queuedStr = prefs.getString('queued_gate_events');
  if (queuedStr == null) return;
  final List<dynamic> queued = jsonDecode(queuedStr);
  if (queued.isEmpty) return;
  final List<Map<String, dynamic>> events = queued
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  try {
    await Supabase.instance.client.from('gate_events').insert(events);
    await prefs.remove('queued_gate_events');
  } catch (_) {}
}

Future<void> _handleShiftEndReminder() async {
  if (_isLocationHandling) {
    debugPrint('_handleShiftEndReminder: Location check in progress, skipping');
    return;
  }
  _isLocationHandling = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getString('worker_id');
    final orgCode = prefs.getString('org_code');
    if (workerId == null || orgCode == null) {
      _isLocationHandling = false;
      return;
    }

    final locationService = LocationService();
    final position = await locationService
        .getCurrentLocation(requestAlways: false, allowPermissionDialog: false)
        .timeout(const Duration(seconds: 120))
        .catchError(
          (_) =>
              LocationService.lastValidPosition ??
              Position(
                longitude: 0,
                latitude: 0,
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                heading: 0,
                speed: 0,
                speedAccuracy: 0,
                altitudeAccuracy: 0,
                headingAccuracy: 0,
              ),
        );

    if (position.latitude == 0) {
      _isLocationHandling = false;
      return;
    }

    final isTimerRunning = prefs.getBool('persisted_is_timer_running') ?? false;
    final selectedShiftName = prefs.getString('persisted_shift');

    if (!isTimerRunning || selectedShiftName == null) {
      _isLocationHandling = false;
      return;
    }
    final now = TimeUtils.nowIst();
    final shift = await Supabase.instance.client
        .from('shifts')
        .select()
        .eq('organization_code', orgCode)
        .eq('name', selectedShiftName)
        .maybeSingle();

    if (shift != null) {
      final startDt = TimeUtils.parseShiftTime(shift['start_time']);
      final endDt = TimeUtils.parseShiftTime(shift['end_time']);

      if (startDt == null || endDt == null) {
        _isLocationHandling = false;
        return;
      }

      DateTime startToday = DateTime(
        now.year,
        now.month,
        now.day,
        startDt.hour,
        startDt.minute,
      );
      DateTime endToday = DateTime(
        now.year,
        now.month,
        now.day,
        endDt.hour,
        endDt.minute,
      );
      DateTime effectiveEnd;
      if (endDt.isBefore(startDt)) {
        if (!now.isBefore(startToday)) {
          effectiveEnd = endToday.add(const Duration(days: 1));
        } else if (now.isBefore(endToday)) {
          effectiveEnd = endToday;
        } else {
          final diffToStart = startToday.difference(now);
          if (diffToStart.inMinutes > 0 && diffToStart.inMinutes <= 15) {
            await _showNotification(
              "Shift Starting Soon",
              "Your shift ($selectedShiftName) starts in ${diffToStart.inMinutes} minutes.",
            );
          }
          return;
        }
      } else {
        if (now.isBefore(startToday)) {
          final diffToStart = startToday.difference(now);
          if (diffToStart.inMinutes > 0 && diffToStart.inMinutes <= 15) {
            await _showNotification(
              "Shift Starting Soon",
              "Your shift ($selectedShiftName) starts in ${diffToStart.inMinutes} minutes.",
            );
          }
          return;
        }
        effectiveEnd = endToday;
      }
      final diff = effectiveEnd.difference(now);

      if (diff.inMinutes > 0 && diff.inMinutes <= 15) {
        await _showNotification(
          "Shift Ending Soon",
          "Your shift ($selectedShiftName) ends in ${diff.inMinutes} minutes. Please update and close your production tasks.",
        );
      } else if (diff.isNegative) {
        await _showNotification(
          "Shift Ended",
          "Your shift ($selectedShiftName) has ended, but production is still running. Please close your production tasks.",
        );
      }
    }
  } catch (e) {
    debugPrint('Shift end reminder error: $e');
  } finally {
    _isLocationHandling = false;
  }
}

Future<void> _showNotification(String title, String body) async {
  await NotificationService.showNotification(
    id: TimeUtils.nowUtc().millisecond,
    title: title,
    body: body,
  );
}

void main() async {
  debugPrint('!!! APP STARTING !!!');
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase
    try {
      await Firebase.initializeApp();
      debugPrint('Firebase initialized successfully');
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
      // Continue even if Firebase fails, as local notifications still work
    }

    try {
      await SupabaseService.initialize().timeout(const Duration(seconds: 15));
      debugPrint('Supabase initialized successfully');
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
    }
    await TimeUtils.syncServerTime();
    await NotificationService.initialize();

    // Request notification permissions early
    await NotificationService.requestPermissions();

    // Initialize Workmanager
    if (!kIsWeb) {
      Workmanager().initialize(callbackDispatcher);
    }

    // Configure Foreground Service (Android)
    if (!kIsWeb) {
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: backgroundServiceOnStart,
          isForegroundMode: true,
          autoStart: true,
          autoStartOnBoot: true, // Ensure it starts on phone restart
        ),
        iosConfiguration: IosConfiguration(
          onForeground: backgroundServiceOnStart,
          onBackground: iosBackground,
        ),
      );

      // Start the service immediately if it's not running
      final service = FlutterBackgroundService();
      bool isRunning = await service.isRunning();
      if (!isRunning) {
        service.startService();
      }
    }

    runApp(const WorkerApp());
  } catch (e) {
    debugPrint('Initialization error: $e');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Failed to initialize app: $e')),
        ),
      ),
    );
  }
}

class WorkerApp extends StatefulWidget {
  const WorkerApp({super.key});

  @override
  State<WorkerApp> createState() => _WorkerAppState();
}

class _WorkerAppState extends State<WorkerApp> {
  AppThemeMode _themeMode = AppThemeMode.auto;
  bool _isDarkMode = false;
  late Timer _themeTimer;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _updateThemeBasedOnTime();
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateThemeBasedOnTime();
    });
  }

  @override
  void dispose() {
    _themeTimer.cancel();
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt('theme_mode') ?? AppThemeMode.auto.index;
    if (mounted) {
      setState(() {
        _themeMode = AppThemeMode.values[modeIndex];
        _updateThemeBasedOnTime();
      });
    }
  }

  void _updateThemeBasedOnTime() {
    bool shouldBeDark;
    switch (_themeMode) {
      case AppThemeMode.day:
        shouldBeDark = false;
        break;
      case AppThemeMode.night:
        shouldBeDark = true;
        break;
      case AppThemeMode.auto:
        final hour = TimeUtils.nowIst().hour;
        shouldBeDark = !(hour >= 6 && hour < 18);
        break;
    }

    if (_isDarkMode != shouldBeDark) {
      setState(() {
        _isDarkMode = shouldBeDark;
      });
    }
  }

  Future<void> _setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    setState(() {
      _themeMode = mode;
      _updateThemeBasedOnTime();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ThemeController(
      themeMode: _themeMode,
      isDarkMode: _isDarkMode,
      onThemeModeChanged: _setThemeMode,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Worker App',
        theme: _isDarkMode ? _darkTheme : _lightTheme,
        home: const Initializer(),
      ),
    );
  }

  ThemeData get _lightTheme => ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.green,
    scaffoldBackgroundColor: AppColors.lightBackground,
    textTheme: AppTheme.textTheme,
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: AppTheme.darkText),
      hintStyle: TextStyle(color: AppTheme.lightText),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppTheme.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.green),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );

  ThemeData get _darkTheme => ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.teal,
    scaffoldBackgroundColor: AppColors.darkBackground,
    textTheme: AppTheme.darkTextTheme,
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      hintStyle: const TextStyle(color: Colors.white60),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.tealAccent, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

class Initializer extends StatefulWidget {
  const Initializer({super.key});

  @override
  State<Initializer> createState() => _InitializerState();
}

class _InitializerState extends State<Initializer> {
  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    // Wait a bit for the app to settle
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateInfo = await VersionService.checkForUpdate('worker');
    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: !updateInfo['isForceUpdate'],
        builder: (context) => UpdateDialog(
          latestVersion: updateInfo['latestVersion'],
          apkUrl: updateInfo['apkUrl'],
          isForceUpdate: updateInfo['isForceUpdate'],
          releaseNotes: updateInfo['releaseNotes'],
          headers: updateInfo['headers'],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}
