import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class VersionService {
  static const String _tableName = 'app_versions';

  /// Checks if an update is available for the given app type (worker, admin, supervisor)
  /// Now defaults to returning null as we are moving to GitHub-based versioning via UpdateService
  static Future<Map<String, dynamic>?> checkForUpdate(String appType) async {
    return null;
  }

  /// Launches the update URL in the browser
  static Future<void> launchUpdateUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching update URL: $e');
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
