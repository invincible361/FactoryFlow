import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';

class VersionService {
  /// Checks if an update is available for the given app type (worker, admin, supervisor)
  /// Uses UpdateService to fetch version data from GitHub.
  static Future<Map<String, dynamic>?> checkForUpdate(String appType) async {
    try {
      final versionData = await UpdateService.fetchVersionData(appType);
      if (versionData == null) return null;

      final packageInfo = await UpdateService.getPackageInfo();
      final currentVersion = packageInfo.version;
      final latestVersion = versionData['latest_version'] ?? '';

      debugPrint(
        'VersionService: Checking update for $appType. Current: $currentVersion, Latest: $latestVersion',
      );

      if (UpdateService.isNewerVersion(currentVersion, latestVersion)) {
        return {
          'latestVersion': latestVersion,
          'apkUrl': versionData['apk_url'],
          'isForceUpdate': versionData['force_update'] ?? false,
          'releaseNotes':
              versionData['release_notes'] ?? 'A new update is available.',
          'headers': versionData['headers'],
        };
      }
    } catch (e) {
      debugPrint('VersionService: Error checking for update: $e');
    }
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
