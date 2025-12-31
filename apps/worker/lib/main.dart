import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:uuid/uuid.dart';
import 'screens/login_screen.dart';

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
        await _handleBackgroundLocation();
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
        final eventId = prefs.getString('active_boundary_event_id');
        if (eventId != null) {
          final entryTime = DateTime.now();
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
      Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
    }

    runApp(const WorkerApp());
  } catch (e) {
    debugPrint('Initialization error: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Failed to initialize app: $e'),
        ),
      ),
    ));
  }
}

class WorkerApp extends StatelessWidget {
  const WorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Worker App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF6C5CE7),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
