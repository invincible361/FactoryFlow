import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class UpdateService {
  // Actual GitHub username and repository name
  static const String _repoOwner = 'invincible361';
  static const String _repoName = 'FactoryFlow';

  // Flag to prevent multiple dialogs
  static bool _isDialogShowing = false;

  // Shorebird instance
  static final _shorebirdCodePush = ShorebirdCodePush();

  static Future<Map<String, dynamic>?> fetchVersionData(String appType) async {
    try {
      // Clean appType to ensure no leading/trailing spaces
      final cleanAppType = appType.trim().toLowerCase();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Use the specific path structure: apps/[appType]/version.json
      String versionUrl =
          'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/apps/$cleanAppType/version.json?t=$timestamp';

      debugPrint(
        'UpdateService: Fetching version data for [$cleanAppType] from: $versionUrl',
      );
      var response = await http.get(Uri.parse(versionUrl));
      debugPrint(
        'UpdateService: Response status code for [$cleanAppType]: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('UpdateService: Successfully fetched data: $data');
        return data;
      }

      // If specific app fails, try the root fallback
      debugPrint(
        'UpdateService: [$cleanAppType] specific fetch failed (${response.statusCode}), trying root fallback...',
      );
      versionUrl =
          'https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/version.json?t=$timestamp';
      response = await http.get(Uri.parse(versionUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('UpdateService: Successfully fetched root data: $data');
        return data;
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

    // 1. First, check for Shorebird patches (Code Push)
    try {
      final isShorebirdAvailable = await _shorebirdCodePush
          .isShorebirdAvailable();
      if (isShorebirdAvailable) {
        debugPrint(
          'UpdateService: Shorebird is available, checking for patches...',
        );
        final isNewPatchAvailable = await _shorebirdCodePush
            .isNewPatchAvailableForDownload();

        if (isNewPatchAvailable) {
          debugPrint(
            'UpdateService: New Shorebird patch available! Downloading...',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Downloading background optimization...'),
                duration: Duration(seconds: 2),
              ),
            );
          }

          await _shorebirdCodePush.downloadUpdateIfAvailable();
          debugPrint(
            'UpdateService: Shorebird patch downloaded. It will apply on next restart.',
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Update downloaded! It will be applied when you restart the app.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          }
          // After a patch is handled, we still check for full APK updates
        } else {
          debugPrint('UpdateService: No new Shorebird patch available.');
        }
      }
    } catch (e) {
      debugPrint('UpdateService: Shorebird check error: $e');
    }

    // 2. Check for Full APK Updates (OTA)
    final data = await fetchVersionData(appType);
    if (data != null) {
      final latestVersion = data['latest_version'];
      final apkUrl = data['apk_url'];
      final forceUpdate = data['force_update'] ?? false;

      final packageInfo = await getPackageInfo();
      final currentVersion = packageInfo.version;

      debugPrint('UpdateService: Current Version: [$currentVersion]');
      debugPrint('UpdateService: Latest Version: [$latestVersion]');
      debugPrint('UpdateService: App Type: [$appType]');

      if (isNewerVersion(currentVersion, latestVersion)) {
        debugPrint(
          'UpdateService: New version available! Checking if dialog already showing...',
        );
        if (_isDialogShowing) {
          debugPrint(
            'UpdateService: Dialog already showing, skipping duplicate.',
          );
          return;
        }

        if (context.mounted) {
          _isDialogShowing = true;
          _showUpdateDialog(context, latestVersion, apkUrl, forceUpdate);
        }
      } else {
        debugPrint(
          'UpdateService: App is up to date (Current: $currentVersion, Latest: $latestVersion).',
        );
      }
    } else {
      debugPrint('UpdateService: Failed to fetch version data for $appType.');
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
      final status = await Permission.requestInstallPackages.request();
      final storageStatus = await Permission.storage.request();

      if (!status.isGranted || !storageStatus.isGranted) {
        debugPrint(
          'UpdateService: Missing required permissions for OTA update',
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please grant storage and install permissions to update.',
              ),
            ),
          );
        }
        _isDialogShowing = false;
        return;
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
            usePackageInstaller: true,
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
