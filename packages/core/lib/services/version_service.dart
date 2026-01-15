import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ota_update/ota_update.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
      final headersRaw = response['headers'] as Map<String, dynamic>? ?? {};
      final headers = headersRaw.map(
        (key, value) => MapEntry(key, value.toString()),
      );

      final isGreater = _isVersionGreater(latestVersion, currentVersion);

      if (isGreater) {
        return {
          'currentVersion': currentVersion,
          'latestVersion': latestVersion,
          'apkUrl': apkUrl,
          'isForceUpdate': isForceUpdate,
          'releaseNotes': releaseNotes,
          'headers': headers,
        };
      }
    } catch (e) {
      debugPrint('Error checking for update: $e');
    }
    return null;
  }

  /// Triggers the OTA update flow (Android only)
  static Stream<OtaEvent> updateApp(
    String url, {
    Map<String, String>? headers,
  }) async* {
    String directUrl = url;
    
    // Follow redirects to get the final direct download link
    // This is crucial for GitHub releases as they redirect to objects.githubusercontent.com
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url))..followRedirects = true;
      final streamedResponse = await client.send(request);
      
      if (streamedResponse.request != null) {
        directUrl = streamedResponse.request!.url.toString();
      }
      
      // Close the stream immediately as we only need the URL
      await streamedResponse.stream.listen((_) {}).cancel();
      debugPrint('VersionService: Resolved direct URL: $directUrl');
    } catch (e) {
      debugPrint('VersionService: Error resolving direct URL: $e');
    }

    try {
      yield* OtaUpdate().execute(
        directUrl,
        destinationFilename: 'factoryflow_${DateTime.now().millisecondsSinceEpoch}.apk',
        headers: headers ?? {},
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
