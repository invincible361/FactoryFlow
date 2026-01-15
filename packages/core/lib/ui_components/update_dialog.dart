import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../services/version_service.dart';

class UpdateDialog extends StatefulWidget {
  final String latestVersion;
  final String apkUrl;
  final bool isForceUpdate;
  final String releaseNotes;

  const UpdateDialog({
    super.key,
    required this.latestVersion,
    required this.apkUrl,
    required this.isForceUpdate,
    required this.releaseNotes,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  OtaEvent? _otaEvent;
  bool _isDownloading = false;

  void _startUpdate() {
    setState(() {
      _isDownloading = true;
    });

    VersionService.updateApp(widget.apkUrl).listen(
      (event) {
        setState(() {
          _otaEvent = event;
        });
      },
      onError: (e) {
        debugPrint('Update error: $e');
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to download update. Please try again.'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.isForceUpdate,
      child: AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Update Available',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version (${widget.latestVersion}) is available.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.releaseNotes.isNotEmpty) ...[
              const Text(
                'What\'s new:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(widget.releaseNotes),
              const SizedBox(height: 16),
            ],
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value:
                    _otaEvent != null &&
                        _otaEvent!.value != null &&
                        _otaEvent!.value!.isNotEmpty
                    ? (double.tryParse(_otaEvent!.value!) ?? 0) / 100
                    : null,
                backgroundColor: Colors.blue.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _otaEvent?.status == OtaStatus.DOWNLOADING
                      ? 'Downloading: ${_otaEvent?.value}%'
                      : _otaEvent?.status == OtaStatus.INSTALLING
                      ? 'Preparing to install...'
                      : 'Starting download...',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ] else
              Text(
                widget.isForceUpdate
                    ? 'This update is required to continue using the app.'
                    : 'Would you like to update now?',
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ),
        actions: _isDownloading
            ? []
            : [
                if (!widget.isForceUpdate)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('SKIP'),
                  ),
                ElevatedButton(
                  onPressed: _startUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('UPDATE NOW'),
                ),
              ],
      ),
    );
  }
}
