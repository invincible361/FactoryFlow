import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ota_update/ota_update.dart';
import 'package:flutter/foundation.dart';

class VersionService {
  static const String _tableName = 'app_versions';

  /// Checks if an update is available for the given app type (worker, admin, supervisor)
  static Future<Map<String, dynamic>?> checkForUpdate(String appType) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await Supabase.instance.client
          .from(_tableName)
          .select()
          .eq('app_type', appType)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response == null) {
        return null;
      }

      final latestVersion = response['version'] as String;
      final apkUrl = response['apk_url'] as String;
      final isForceUpdate = response['is_force_update'] as bool? ?? false;
      final releaseNotes = response['release_notes'] as String? ?? '';

      final isGreater = _isVersionGreater(latestVersion, currentVersion);

      if (isGreater) {
        return {
          'currentVersion': currentVersion,
          'latestVersion': latestVersion,
          'apkUrl': apkUrl,
          'isForceUpdate': isForceUpdate,
          'releaseNotes': releaseNotes,
        };
      }
    } catch (e) {
      debugPrint('Error checking for update: $e');
    }
    return null;
  }

  /// Triggers the OTA update flow (Android only)
  static Stream<OtaEvent> updateApp(String url) {
    try {
      return OtaUpdate().execute(
        url,
        destinationFilename: 'factoryflow_update.apk',
      );
    } catch (e) {
      debugPrint('OTA Update Error: $e');
      rethrow;
    }
  }

  /// Helper to compare semantic versions (e.g., 1.2.0 > 1.1.9)
  static bool _isVersionGreater(String latest, String current) {
    try {
      // Remove any build number (+1) if present for comparison
      String latestClean = latest.split('+')[0];
      String currentClean = current.split('+')[0];

      List<int> latestParts = latestClean.split('.').map(int.parse).toList();
      List<int> currentParts = currentClean.split('.').map(int.parse).toList();

      int maxLength = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;

      for (int i = 0; i < maxLength; i++) {
        int latestPart = i < latestParts.length ? latestParts[i] : 0;
        int currentPart = i < currentParts.length ? currentParts[i] : 0;

        if (latestPart > currentPart) return true;
        if (latestPart < currentPart) return false;
      }
    } catch (e) {
      debugPrint('VersionService: Error comparing versions: $e');
    }
    return false;
  }
}
