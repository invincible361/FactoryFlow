import 'package:flutter/material.dart';
import '../services/version_service.dart';

class UpdateDialog extends StatefulWidget {
  final String latestVersion;
  final String apkUrl;
  final bool isForceUpdate;
  final String releaseNotes;
  final Map<String, String>? headers;

  const UpdateDialog({
    super.key,
    required this.latestVersion,
    required this.apkUrl,
    required this.isForceUpdate,
    required this.releaseNotes,
    this.headers,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isLaunching = false;

  Future<void> _startUpdate() async {
    setState(() {
      _isLaunching = true;
    });

    await VersionService.launchUpdateUrl(widget.apkUrl);

    if (mounted && !widget.isForceUpdate) {
      Navigator.of(context).pop();
    } else if (mounted) {
      setState(() {
        _isLaunching = false;
      });
    }
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
            if (_isLaunching) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('Opening browser...')),
            ] else
              Text(
                widget.isForceUpdate
                    ? 'This update is required to continue using the app.'
                    : 'Would you like to download the update now?',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
              ),
          ],
        ),
        actions: [
          if (!widget.isForceUpdate && !_isLaunching)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          ElevatedButton(
            onPressed: _isLaunching ? null : _startUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(_isLaunching ? 'Opening...' : 'Download Now'),
          ),
        ],
      ),
    );
  }
}
