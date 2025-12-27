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
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/login_screen.dart';

// Background task identifiers
const String syncLocationTask = "syncLocationTask";
const String shiftEndReminderTask = "shiftEndReminderTask";

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

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
    }
    return Future.value(true);
  });
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

      bool isInside = distance <= radius;
      bool wasInside = prefs.getBool('was_inside') ?? true;

      if (wasInside && !isInside) {
        // Just went out
        final eventId = const Uuid().v4();
        await Supabase.instance.client.from('worker_boundary_events').insert({
          'id': eventId,
          'worker_id': workerId,
          'organization_code': orgCode,
          'exit_time': DateTime.now().toIso8601String(),
          'exit_latitude': position.latitude,
          'exit_longitude': position.longitude,
        });
        await prefs.setString('active_boundary_event_id', eventId);
        await prefs.setBool('was_inside', false);

        await _showNotification(
          "Out of Bounds",
          "You have left the factory premises. Your exit has been recorded.",
        );
      } else if (!wasInside && isInside) {
        // Just came back
        final eventId = prefs.getString('active_boundary_event_id');
        if (eventId != null) {
          final entryTime = DateTime.now();
          // Fetch exit time to calculate duration
          final event = await Supabase.instance.client
              .from('worker_boundary_events')
              .select('exit_time')
              .eq('id', eventId)
              .maybeSingle();

          String? durationStr;
          if (event != null) {
            final exitTime = DateTime.parse(event['exit_time']);
            final diff = entryTime.difference(exitTime);
            durationStr = "${diff.inMinutes} mins";
          }

          await Supabase.instance.client
              .from('worker_boundary_events')
              .update({
                'entry_time': entryTime.toIso8601String(),
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

      // Notify 15 minutes before shift ends if production is still running
      if (diff.inMinutes > 0 && diff.inMinutes <= 15) {
        await _showNotification(
          "Shift Ending Soon",
          "Your shift ($selectedShiftName) ends in ${diff.inMinutes} minutes. Please update and close your production tasks.",
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
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidDetails = AndroidNotificationDetails(
    'factory_flow_channel',
    'FactoryFlow Notifications',
    importance: Importance.max,
    priority: Priority.high,
  );
  const iosDetails = DarwinNotificationDetails();
  const notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
    macOS: iosDetails,
  );
  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    notificationDetails,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  // Initialize Notifications
  if (!kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows)) {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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
  }

  // Initialize Workmanager
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await Workmanager().initialize(callbackDispatcher);
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
