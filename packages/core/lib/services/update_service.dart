import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

      final timestamp = DateTime.now().millisecondsSinceEpoch;
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
        return data;
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
      builder: (context) => WillPopScope(
        onWillPop: () async {
          if (!forceUpdate) {
            _isDialogShowing = false;
          }
          return !forceUpdate;
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
              onPressed: () {
                // Keep _isDialogShowing = true during OTA update
                Navigator.pop(context);
                _startOtaUpdate(context, url);
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }

  static void _startOtaUpdate(BuildContext context, String url) async {
    // 1. Check permissions first
    if (!kIsWeb && Platform.isAndroid) {
      debugPrint('UpdateService: Requesting permissions for OTA update...');

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      debugPrint('UpdateService: Android SDK version: $sdkInt');

      // Request Install Packages permission (Android 8.0+)
      if (sdkInt >= 26) {
        final installStatus = await Permission.requestInstallPackages.status;
        if (!installStatus.isGranted) {
          debugPrint(
            'UpdateService: Requesting install packages permission...',
          );
          await Permission.requestInstallPackages.request();
        }
      }

      // For storage:
      // - Below Android 11 (SDK 30): Need WRITE_EXTERNAL_STORAGE
      // - Android 11+: ota_update usually handles internal download without extra storage permission
      if (sdkInt < 30) {
        final storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          debugPrint(
            'UpdateService: Requesting storage permission (SDK < 30)...',
          );
          await Permission.storage.request();
        }
      }

      // Re-check install permission after requests (most critical)
      if (sdkInt >= 26) {
        final finalInstallStatus =
            await Permission.requestInstallPackages.status;
        if (!finalInstallStatus.isGranted) {
          debugPrint('UpdateService: Install permission denied.');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please allow "Install unknown apps" permission to update.',
                ),
                duration: Duration(seconds: 5),
              ),
            );
          }
          _isDialogShowing = false;
          return;
        }
      }
    }

    late StateSetter setDialogState;
    double progress = 0;
    String status = 'Starting download...';

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setDialogState = setState;
          return AlertDialog(
            title: const Text('Updating App'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress / 100),
                const SizedBox(height: 20),
                Text(status),
              ],
            ),
          );
        },
      ),
    );

    try {
      OtaUpdate()
          .execute(
            url,
            destinationFilename: 'update.apk',
            // usePackageInstaller: true can cause issues on some devices/versions
            // Setting it to false or removing it often helps with installation
          )
          .listen(
            (OtaEvent event) {
              setDialogState(() {
                switch (event.status) {
                  case OtaStatus.DOWNLOADING:
                    status = 'Downloading: ${event.value}%';
                    progress = double.tryParse(event.value!) ?? 0;
                    break;
                  case OtaStatus.INSTALLING:
                    status = 'Installing update...';
                    break;
                  default:
                    if (event.status.toString().contains('ERROR')) {
                      status = 'Update failed: ${event.status}';
                    } else {
                      status = 'Status: ${event.status}';
                    }
                    break;
                }
              });

              // Close dialog on completion or error (except downloading/installing)
              if (event.status != OtaStatus.DOWNLOADING &&
                  event.status != OtaStatus.INSTALLING) {
                _isDialogShowing = false; // Reset flag
                Future.delayed(const Duration(seconds: 2), () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                });
              }
            },
            onError: (e) {
              debugPrint('OTA Update Stream Error: $e');
              _isDialogShowing = false;
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
            },
          );
    } catch (e) {
      debugPrint('OTA Update Error: $e');
      _isDialogShowing = false;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }
}
