import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:uuid/uuid.dart';
import 'screens/login_screen.dart';
import 'app_theme.dart';

// Background task identifiers
const String syncLocationTask = "syncLocationTask";
const String shiftEndReminderTask = "shiftEndReminderTask";
const String checkForUpdateTask = "checkForUpdateTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Workmanager: Executing task "$task"');
    try {
      await SupabaseService.initialize();
      await NotificationService.initialize();

      if (task == syncLocationTask) {
        debugPrint('Workmanager: Handling syncLocationTask');
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

Future<void> _handleBackgroundUpdateCheck() async {
  try {
    final response = await UpdateService.fetchVersionData('worker');
    if (response != null) {
      final latestVersion = response['latest_version'];
      final packageInfo = await UpdateService.getPackageInfo();
      final currentVersion = packageInfo.version;

      if (UpdateService.isNewerVersion(currentVersion, latestVersion)) {
        await _showNotification(
          "New Update Available",
          "A new version ($latestVersion) of FactoryFlow is available. Open the app to update.",
        );
      }
    }
  } catch (e) {
    debugPrint('Background update check error: $e');
  }
}

Future<Map<String, dynamic>> handleBackgroundLocation() async {
  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getString('worker_id');
  final orgCode = prefs.getString('org_code');
  final isTimerRunning = prefs.getBool('persisted_is_timer_running') ?? false;

  if (workerId == null || orgCode == null)
    return {'isInside': null, 'position': null};

  try {
    // Check if we should log a periodic event even if state hasn't changed
    // We'll log a 'periodic' event every 30 minutes to ensure visibility in dashboard
    final lastPeriodicLog = prefs.getInt('last_periodic_location_log') ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final shouldLogPeriodic =
        (nowMs - lastPeriodicLog) > (30 * 60 * 1000); // 30 mins

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    // Try to get cached factory info first to reduce API calls
    double? lat = prefs.getDouble('factory_lat');
    double? lng = prefs.getDouble('factory_lng');
    double? radius = prefs.getDouble('factory_radius');

    // Fallback to API only if not cached
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

        // Cache for next time
        await prefs.setDouble('factory_lat', lat!);
        await prefs.setDouble('factory_lng', lng!);
        await prefs.setDouble('factory_radius', radius!);
      }
    }

    if (lat != null && lng != null && radius != null) {
      // Using LocationService for consistency and accuracy-aware check
      final locationService = LocationService();
      bool isInside = locationService.isInside(
        position,
        lat,
        lng,
        radius,
        bufferMultiplier: 1.0,
      );

      final workerName = prefs.getString('worker_name') ?? 'Worker';
      bool? wasInside = prefs.containsKey('was_inside')
          ? prefs.getBool('was_inside')
          : null;

      // Log if state changed OR if this is the first time we're checking OR if periodic log is due
      if (wasInside == null || wasInside != isInside || shouldLogPeriodic) {
        final eventId = const Uuid().v4();
        final eventType = shouldLogPeriodic && (wasInside == isInside)
            ? 'periodic'
            : (isInside ? 'entry' : 'exit');

        final isViolation = !isInside && isTimerRunning;

        // Log to worker_boundary_events for real-time status
        await Supabase.instance.client.from('worker_boundary_events').insert({
          'id': const Uuid().v4(),
          'worker_id': workerId,
          'organization_code': orgCode,
          'type': eventType,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'remarks': isViolation
              ? 'OUT_OF_BOUNDS_PRODUCTION'
              : (eventType == 'periodic'
                    ? 'STILL_${isInside ? 'INSIDE' : 'OUTSIDE'}'
                    : null),
          if (isInside)
            'entry_latitude': position.latitude
          else
            'exit_latitude': position.latitude,
          if (isInside)
            'entry_longitude': position.longitude
          else
            'exit_longitude': position.longitude,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });

        if (shouldLogPeriodic) {
          await prefs.setInt('last_periodic_location_log', nowMs);
        }

        // Only log out-of-bounds violations if leaving while production is running
        if (!isInside && isTimerRunning && eventType == 'exit') {
          try {
            await Supabase.instance.client
                .from('production_outofbounds')
                .insert({
                  'id': eventId,
                  'worker_id': workerId,
                  'worker_name': workerName,
                  'organization_code': orgCode,
                  'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  'exit_time': DateTime.now().toUtc().toIso8601String(),
                  'exit_latitude': position.latitude,
                  'exit_longitude': position.longitude,
                });
            await prefs.setString('active_boundary_event_id', eventId);
          } catch (e) {
            debugPrint('Background log error (outofbounds): $e');
          }

          final timestamp = DateFormat('hh:mm a').format(DateTime.now());
          await _showNotification(
            "Return to Factory! ($timestamp)",
            "You left the factory area at $timestamp while production is running. Please return immediately.",
          );

          try {
            // Notify Admin
            await Supabase.instance.client.from('notifications').insert({
              'organization_code': orgCode,
              'title': 'Worker Left Factory',
              'body':
                  '$workerName left the factory area at $timestamp while production is running.',
              'type': 'out_of_bounds',
              'worker_id': workerId,
              'worker_name': workerName,
            });
          } catch (e) {
            debugPrint('Background notification error: $e');
          }
        }

        // Handle return during production
        if (isInside && isTimerRunning) {
          final activeEventId = prefs.getString('active_boundary_event_id');
          if (activeEventId != null) {
            final entryTime = DateTime.now();
            try {
              final event = await Supabase.instance.client
                  .from('production_outofbounds')
                  .select('exit_time')
                  .eq('id', activeEventId)
                  .maybeSingle();

              String? durationStr;
              if (event != null) {
                final exitTime = TimeUtils.parseToLocal(event['exit_time']);
                final diff = entryTime.difference(exitTime);
                durationStr = "${diff.inMinutes} mins";
              }

              await Supabase.instance.client
                  .from('production_outofbounds')
                  .update({
                    'entry_time': entryTime.toUtc().toIso8601String(),
                    'entry_latitude': position.latitude,
                    'entry_longitude': position.longitude,
                    'duration_minutes': durationStr,
                  })
                  .eq('id', activeEventId);
            } catch (e) {
              debugPrint('Background update error (outofbounds): $e');
            }

            await prefs.remove('active_boundary_event_id');

            final timestamp = DateFormat('hh:mm a').format(DateTime.now());
            try {
              // Notify Admin
              await Supabase.instance.client.from('notifications').insert({
                'organization_code': orgCode,
                'title': 'Worker Returned',
                'body':
                    '$workerName returned to the factory area at $timestamp.',
                'type': 'return',
                'worker_id': workerId,
                'worker_name': workerName,
              });
            } catch (e) {
              debugPrint('Background notification error (return): $e');
            }
          }
        }

        await prefs.setBool('was_inside', isInside);
      }
      return {'isInside': isInside, 'position': position};
    }
  } catch (e) {
    debugPrint('Background location error: $e');
  }
  return {'isInside': null, 'position': null};
}

Future<void> _handleShiftEndReminder() async {
  final prefs = await SharedPreferences.getInstance();
  final isTimerRunning = prefs.getBool('persisted_is_timer_running') ?? false;
  final selectedShiftName = prefs.getString('persisted_shift');

  if (!isTimerRunning || selectedShiftName == null) return;

  final orgCode = prefs.getString('org_code');
  if (orgCode == null) return;

  try {
    final now = DateTime.now();
    final shift = await Supabase.instance.client
        .from('shifts')
        .select()
        .eq('organization_code', orgCode)
        .eq('name', selectedShiftName)
        .maybeSingle();

    if (shift != null) {
      final endTimeStr = shift['end_time'] as String;
      final format = DateFormat('hh:mm a');
      final endDt = format.parse(endTimeStr);

      final shiftEndToday = DateTime(
        now.year,
        now.month,
        now.day,
        endDt.hour,
        endDt.minute,
      );

      final startDt = format.parse(shift['start_time'] as String);
      DateTime adjustedShiftEnd = shiftEndToday;
      if (endDt.isBefore(startDt)) {
        if (now.hour >= startDt.hour) {
          adjustedShiftEnd = shiftEndToday.add(const Duration(days: 1));
        }
      }

      final diff = adjustedShiftEnd.difference(now);

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
    debugPrint('Shift reminder error: $e');
  }
}

Future<void> _showNotification(String title, String body) async {
  await NotificationService.showNotification(
    id: DateTime.now().millisecond,
    title: title,
    body: body,
  );
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await SupabaseService.initialize();
    await NotificationService.initialize();

    // Initialize Workmanager
    if (!kIsWeb) {
      Workmanager().initialize(callbackDispatcher);
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
        final hour = DateTime.now().hour;
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
        home: const LoginScreen(),
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
