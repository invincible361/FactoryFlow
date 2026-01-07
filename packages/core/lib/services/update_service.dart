import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
            _showInstallPermissionDialog(context, url);
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
            actions: [
              TextButton(
                onPressed: () async {
                  if (await canLaunchUrl(Uri.parse(url))) {
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: const Text('Download in Browser'),
              ),
            ],
          );
        },
      ),
    );

    try {
      // Follow redirects to get the final direct download link
      // This is crucial for GitHub releases as they redirect to objects.githubusercontent.com
      String directUrl = url;
      try {
        final client = http.Client();
        // Use GET instead of HEAD because some servers (like GitHub) might
        // handle redirects differently or block HEAD requests for binaries
        final request = http.Request('GET', Uri.parse(url))
          ..followRedirects = true;

        // We only need the headers to find the final URL, so we can close the stream early
        final streamedResponse = await client.send(request);

        // The final URL after all redirects is stored in the request.url of the response
        if (streamedResponse.request != null) {
          directUrl = streamedResponse.request!.url.toString();
        }

        // IMPORTANT: Close the stream to avoid hanging or memory leaks
        // Since we only want the URL, we don't need to read the body
        await streamedResponse.stream.listen((_) {}).cancel();

        debugPrint('UpdateService: Direct URL resolved to: $directUrl');

        // Final sanity check: if the URL doesn't look like an APK and we are on GitHub,
        // it might have failed to resolve properly
        if (!directUrl.toLowerCase().contains('.apk') &&
            directUrl.contains('github.com')) {
          debugPrint(
            'UpdateService: Warning: Resolved URL does not contain .apk extension',
          );
        }
      } catch (e) {
        debugPrint(
          'UpdateService: Error resolving direct URL, using original: $e',
        );
      }

      // Use a unique filename for each download to avoid issues with old/corrupted files
      final downloadId = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'update_$downloadId.apk';

      OtaUpdate()
          .execute(directUrl, destinationFilename: fileName)
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
                  case OtaStatus.ALREADY_RUNNING_ERROR:
                    status = 'An update is already in progress';
                    break;
                  case OtaStatus.DOWNLOAD_ERROR:
                    status = 'Download failed. Check internet.';
                    break;
                  case OtaStatus.CHECKSUM_ERROR:
                    status = 'Update file corrupted (Checksum error)';
                    break;
                  case OtaStatus.INTERNAL_ERROR:
                    status = 'Internal update error';
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

                // If it failed, show browser option more prominently
                if (event.status.toString().contains('ERROR')) {
                  _showErrorDialog(
                    context,
                    url,
                    "Update failed: ${event.status}",
                  );
                }

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
              _showErrorDialog(context, url, 'Update failed: $e');
            },
          );
    } catch (e) {
      debugPrint('OTA Update Error: $e');
      _isDialogShowing = false;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showErrorDialog(context, url, 'Error: $e');
    }
  }

  static void _showInstallPermissionDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Please allow "Install unknown apps" permission to update the app automatically. Alternatively, you can download it manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: const Text('Download Manually'),
          ),
        ],
      ),
    );
  }

  static void _showErrorDialog(
    BuildContext context,
    String url,
    String message,
  ) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 10),
            const Text(
              'You can try downloading the update manually via browser.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: const Text('Open Browser'),
          ),
        ],
      ),
    );
  }
}
