import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://gxeglfjlxdpcliptmunu.supabase.co',
      anonKey: 'sb_publishable_JWHoTte803314NYuJeGb4Q_0kE0OioE',
    );
  }

  static Future<void> updateWorkerFCMToken(String workerId, String? token) async {
    if (token == null) return;
    try {
      await Supabase.instance.client
          .from('workers')
          .update({'fcm_token': token})
          .eq('worker_id', workerId);
    } catch (e) {
      print('Error updating worker FCM token: $e');
    }
  }
}
