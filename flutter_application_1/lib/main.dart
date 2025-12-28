import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'utils/time_utils.dart';
import 'screens/login_screen.dart';
import 'services/update_service.dart';

// Background task identifiers
const String syncLocationTask = "syncLocationTask";
const String shiftEndReminderTask = "shiftEndReminderTask";
const String checkForUpdateTask = "checkForUpdateTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Initialize Supabase in background
    await Supabase.initialize(
      url: 'https://gxeglfjlxdpcliptmunu.supabase.co',
      anonKey: 'sb_publishable_JWHoTte803314NYuJeGb4Q_0kE0OioE',
    );

    if (task == syncLocationTask) {
      await _handleBackgroundLocation();
    } else if (task == shiftEndReminderTask) {
      await _handleShiftEndReminder();
    } else if (task == checkForUpdateTask) {
      // In background, we just check and show a notification if update available
      // BuildContext is not available here, so we use a custom check
      await _handleBackgroundUpdateCheck();
    }
    return Future.value(true);
  });
}

Future<void> _handleBackgroundUpdateCheck() async {
  // Logic to check for updates in background and show notification
  // This is similar to UpdateService but without UI
  try {
    final response = await UpdateService.fetchVersionData();
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

Future<void> _handleBackgroundLocation() async {
  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getString('worker_id');
  final orgCode = prefs.getString('org_code');
  final isTimerRunning = prefs.getBool('persisted_is_timer_running') ?? false;

  if (workerId == null || orgCode == null || !isTimerRunning) return;

  try {
    final position = await Geolocator.getCurrentPosition();
    final org = await Supabase.instance.client
        .from('organizations')
        .select()
        .eq('organization_code', orgCode)
        .maybeSingle();

    if (org != null) {
      final lat = (org['latitude'] ?? 0.0) * 1.0;
      final lng = (org['longitude'] ?? 0.0) * 1.0;
      final radius = (org['radius_meters'] ?? 500.0) * 1.0;

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      final workerName = prefs.getString('worker_name') ?? 'Unknown Worker';
      bool isInside = distance <= radius;
      bool wasInside = prefs.getBool('was_inside') ?? true;

      if (wasInside && !isInside) {
        // Just went out
        final eventId = const Uuid().v4();
        await Supabase.instance.client.from('production_outofbounds').insert({
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
        await prefs.setBool('was_inside', false);

        await _showNotification(
          "Return to Factory!",
          "You have left the factory area during production. Please return immediately.",
        );
      } else if (!wasInside && isInside) {
        // Just came back
        final eventId = prefs.getString('active_boundary_event_id');
        if (eventId != null) {
          final entryTime = DateTime.now();
          // Fetch exit time to calculate duration
          final event = await Supabase.instance.client
              .from('production_outofbounds')
              .select('exit_time')
              .eq('id', eventId)
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
              .eq('id', eventId);

          await prefs.remove('active_boundary_event_id');
        }
        await prefs.setBool('was_inside', true);
        await _showNotification(
          "Back in Bounds",
          "You have returned to the factory premises.",
        );
      }
    }
  } catch (e) {
    debugPrint('Background location error: $e');
  }
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

      // Handle night shift end time crossing midnight
      final startDt = format.parse(shift['start_time'] as String);
      DateTime adjustedShiftEnd = shiftEndToday;
      if (endDt.isBefore(startDt)) {
        // If end time is before start time, it belongs to the next day
        // unless we are already in that next day's early hours.
        if (now.hour >= startDt.hour) {
          adjustedShiftEnd = shiftEndToday.add(const Duration(days: 1));
        }
      }

      final diff = adjustedShiftEnd.difference(now);

      // Notify if shift ends in <= 15 minutes OR if shift has already ended
      if (diff.inMinutes > 0 && diff.inMinutes <= 15) {
        await _showNotification(
          "Shift Ending Soon",
          "Your shift ($selectedShiftName) ends in ${diff.inMinutes} minutes. Please update and close your production tasks.",
        );
      } else if (diff.isNegative) {
        // Shift has already ended
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
  if (kIsWeb ||
      !(Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows)) {
    return;
  }
  try {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidDetails = AndroidNotificationDetails(
      'factory_flow_channel',
      'FactoryFlow Notifications',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'launcher_icon',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
  } catch (e) {
    debugPrint('Error showing notification: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Notifications
  if (!kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows)) {
    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('launcher_icon');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
      );
      await flutterLocalNotificationsPlugin.initialize(initSettings);

      // Specifically for Android 13+ and iOS permissions
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  // Initialize Workmanager
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await Workmanager().initialize(callbackDispatcher);

    // Register the periodic update check task
    // It will run every 2 hours in the background
    await Workmanager().registerPeriodicTask(
      "periodic-update-check",
      checkForUpdateTask,
      frequency: const Duration(hours: 2),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  try {
    await Supabase.initialize(
      url: 'https://gxeglfjlxdpcliptmunu.supabase.co',
      anonKey: 'sb_publishable_JWHoTte803314NYuJeGb4Q_0kE0OioE',
    );
    debugPrint('Supabase initialized successfully');
  } catch (e) {
    debugPrint('Supabase initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FactoryFlow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF6C5CE7),
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style:
              ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ).copyWith(
                overlayColor: WidgetStateProperty.resolveWith<Color?>((
                  Set<WidgetState> states,
                ) {
                  if (states.contains(WidgetState.pressed)) {
                    return Colors.white.withValues(alpha: 0.1);
                  }
                  return null;
                }),
              ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
