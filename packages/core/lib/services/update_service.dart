import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/time_utils.dart';

class UpdateService {
  // Actual GitHub username and repository name
  static const String _repoOwner = 'invincible361';
  static const String _repoName = 'FactoryFlow';

  // Flag to prevent multiple dialogs
  static bool _isDialogShowing = false;

  static Future<Map<String, dynamic>?> fetchVersionData(String appType) async {
    try {
      // Clean appType to ensure no leading/trailing spaces
      final cleanAppType = appType.trim().toLowerCase();

      final timestamp = TimeUtils.nowUtc().millisecondsSinceEpoch;
      // Use the specific path structure: apps/[appType]/version.json
      String versionUrl =
          'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/apps/$cleanAppType/version.json?t=$timestamp';

      debugPrint(
        'UpdateService: [DEBUG] Attempting to fetch version data for [$cleanAppType]',
      );
      debugPrint('UpdateService: [DEBUG] Primary URL: $versionUrl');

      var response = await http.get(Uri.parse(versionUrl));
      debugPrint(
        'UpdateService: [DEBUG] Primary fetch status code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('UpdateService: [DEBUG] Successfully fetched data: $data');
        return data;
      }

      // If specific app fails, try the root fallback
      debugPrint(
        'UpdateService: [DEBUG] [$cleanAppType] specific fetch failed, trying root fallback...',
      );
      versionUrl =
          'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/version.json?t=$timestamp';
      debugPrint('UpdateService: [DEBUG] Fallback URL: $versionUrl');
      response = await http.get(Uri.parse(versionUrl));
      debugPrint(
        'UpdateService: [DEBUG] Fallback fetch status code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint(
          'UpdateService: [DEBUG] Successfully fetched root data: $data',
        );
        // Root version.json has appType keys (admin, supervisor, worker)
        if (data is Map<String, dynamic> && data.containsKey(cleanAppType)) {
          return data[cleanAppType] as Map<String, dynamic>;
        }
        return data as Map<String, dynamic>;
      }

      debugPrint('UpdateService: [DEBUG] All fetch attempts failed.');
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
      // Clean versions by removing build numbers (anything after +)
      String cleanCurrent = current.split('+')[0];
      String cleanLatest = latest.split('+')[0];

      debugPrint(
        'UpdateService: Comparing clean versions: Current [$cleanCurrent] vs Latest [$cleanLatest]',
      );

      List<int> currentParts = cleanCurrent
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      List<int> latestParts = cleanLatest
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();

      // Compare major, minor, patch
      int length = currentParts.length > latestParts.length
          ? currentParts.length
          : latestParts.length;

      for (int i = 0; i < length; i++) {
        int vCurrent = i < currentParts.length ? currentParts[i] : 0;
        int vLatest = i < latestParts.length ? latestParts[i] : 0;

        if (vLatest > vCurrent) return true;
        if (vLatest < vCurrent) return false;
      }
    } catch (e) {
      debugPrint('Error comparing versions: $e');
    }
    return false;
  }

  static bool isMajorOrMinorUpdate(String current, String latest) {
    try {
      String cleanCurrent = current.split('+')[0];
      String cleanLatest = latest.split('+')[0];

      List<int> currentParts = cleanCurrent
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      List<int> latestParts = cleanLatest
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();

      // Compare Major (index 0) and Minor (index 1)
      for (int i = 0; i < 2; i++) {
        int vCurrent = i < currentParts.length ? currentParts[i] : 0;
        int vLatest = i < latestParts.length ? latestParts[i] : 0;
        if (vLatest > vCurrent) return true;
      }
    } catch (e) {
      debugPrint('Error comparing major/minor versions: $e');
    }
    return false;
  }

  static Future<void> checkForUpdates(
    BuildContext context,
    String appType,
  ) async {
    // Don't check for updates on web
    if (kIsWeb) {
      debugPrint('UpdateService: Skipping update check on web.');
      return;
    }

    debugPrint('UpdateService: Checking for updates for $appType...');

    // Check for Full APK Updates (OTA)
    final data = await fetchVersionData(appType);
    if (data != null) {
      final latestVersion = data['latest_version'];
      final apkUrl = data['apk_url'];
      final forceUpdate = data['force_update'] ?? false;

      final packageInfo = await getPackageInfo();
      final currentVersion = packageInfo.version;

      debugPrint('UpdateService: Current Version: [$currentVersion]');
      debugPrint('UpdateService: Latest Version: [$latestVersion]');

      if (isNewerVersion(currentVersion, latestVersion)) {
        debugPrint('UpdateService: Showing full APK update dialog...');
        if (_isDialogShowing) return;

        if (context.mounted) {
          _isDialogShowing = true;
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
      builder: (context) => PopScope(
        canPop: !forceUpdate,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop && !forceUpdate) {
            _isDialogShowing = false;
          }
        },
        child: AlertDialog(
          title: const Text('Update Available'),
          content: Text(
            'A new version ($version) is available. Please update for the best experience.',
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () {
                  _isDialogShowing = false;
                  Navigator.pop(context);
                },
                child: const Text('Later'),
              ),
            ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (!forceUpdate) {
                  _isDialogShowing = false;
                  Navigator.pop(context);
                }
              },
              child: const Text('Download Update'),
            ),
          ],
        ),
      ),
    );
  }
}
