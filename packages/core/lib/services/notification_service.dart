import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) return;

    // Use a try-catch and check kIsWeb again just to be safe,
    // although kIsWeb should be enough to skip Platform calls.
    try {
      if (!(Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows)) {
        return;
      }

      const androidInit = AndroidInitializationSettings('ic_notification');
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

      await _notificationsPlugin.initialize(initSettings);

      if (Platform.isAndroid) {
        // Create notification channel
        const channel = AndroidNotificationChannel(
          'factory_flow_channel',
          'FactoryFlow Notifications',
          description: 'Notifications for FactoryFlow tasks and alerts',
          importance: Importance.max,
        );

        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);
      }
    } catch (e) {
      debugPrint('NotificationService initialization error: $e');
    }
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb) return;

    try {
      if (Platform.isAndroid) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('NotificationService requestPermissions error: $e');
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;

    try {
      if (!(Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows)) {
        return;
      }

      final androidDetails = AndroidNotificationDetails(
        'factory_flow_channel',
        'FactoryFlow Notifications',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_notification',
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('NotificationService showNotification error: $e');
    }
  }
}
