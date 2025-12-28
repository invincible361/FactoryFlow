import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

class UpdateService {
  // Actual GitHub username and repository name
  static const String _repoOwner = 'invincible361';
  static const String _repoName = 'FactoryFlow';
  static const String _versionUrl =
      'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/version.json';

  static Future<Map<String, dynamic>?> fetchVersionData() async {
    try {
      final response = await http.get(Uri.parse(_versionUrl));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching version data: $e');
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

  static Future<void> checkForUpdates(BuildContext context) async {
    final data = await fetchVersionData();
    if (data != null) {
      final latestVersion = data['latest_version'];
      final apkUrl = data['apk_url'];
      final forceUpdate = data['force_update'] ?? false;

      final packageInfo = await getPackageInfo();
      final currentVersion = packageInfo.version;

      if (isNewerVersion(currentVersion, latestVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion, apkUrl, forceUpdate);
        }
      }
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
