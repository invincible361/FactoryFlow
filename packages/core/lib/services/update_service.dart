import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

class UpdateService {
  // Actual GitHub username and repository name
  static const String _repoOwner = 'invincible361';
  static const String _repoName = 'FactoryFlow';

  static Future<Map<String, dynamic>?> fetchVersionData(String appType) async {
    try {
      // Try app-specific version first
      String versionUrl =
          'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/apps/$appType/version.json';
      debugPrint('UpdateService: Fetching version data from: $versionUrl');
      var response = await http.get(Uri.parse(versionUrl));
      debugPrint('UpdateService: Response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('UpdateService: Response body: ${response.body}');
        return json.decode(response.body);
      }

      // Fallback to root version.json if app-specific fails
      if (response.statusCode == 404) {
        debugPrint(
          'UpdateService: App-specific version not found, trying root version.json',
        );
        versionUrl =
            'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/version.json';
        debugPrint('UpdateService: Fetching version data from: $versionUrl');
        response = await http.get(Uri.parse(versionUrl));
        debugPrint(
          'UpdateService: Response status code (root): ${response.statusCode}',
        );

        if (response.statusCode == 200) {
          debugPrint('UpdateService: Response body (root): ${response.body}');
          return json.decode(response.body);
        }
      }
    } catch (e) {
      debugPrint('UpdateService: Error fetching version data: $e');
    }
    return null;
  }

  static Future<PackageInfo> getPackageInfo() async {
    return await PackageInfo.fromPlatform();
  }

  static bool isNewerVersion(String current, String latest) {
    try {
      List<int> currentParts = current
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      List<int> latestParts = latest
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();

      for (int i = 0; i < latestParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
    } catch (e) {
      debugPrint('Error comparing versions: $e');
    }
    return false;
  }

  static Future<void> checkForUpdates(
    BuildContext context,
    String appType,
  ) async {
    debugPrint('UpdateService: Checking for updates for $appType...');
    final data = await fetchVersionData(appType);
    if (data != null) {
      final latestVersion = data['latest_version'];
      final apkUrl = data['apk_url'];
      final forceUpdate = data['force_update'] ?? false;

      final packageInfo = await getPackageInfo();
      final currentVersion = packageInfo.version;

      debugPrint('UpdateService: Current Version: $currentVersion');
      debugPrint('UpdateService: Latest Version: $latestVersion');

      if (isNewerVersion(currentVersion, latestVersion)) {
        debugPrint('UpdateService: New version available! Showing dialog...');
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion, apkUrl, forceUpdate);
        }
      } else {
        debugPrint('UpdateService: App is up to date.');
      }
    } else {
      debugPrint('UpdateService: Failed to fetch version data from GitHub.');
    }
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String url,
    bool forceUpdate,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'A new version ($version) is available. Please update for the best experience.',
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}
