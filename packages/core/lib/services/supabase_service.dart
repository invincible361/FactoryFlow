import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://gxeglfjlxdpcliptmunu.supabase.co',
      anonKey: 'sb_publishable_JWHoTte803314NYuJeGb4Q_0kE0OioE',
    );
  }
}
