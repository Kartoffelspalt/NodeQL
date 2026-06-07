import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_release_update_service.dart';

class UpdateCheckGate extends StatefulWidget {
  const UpdateCheckGate({
    required this.child,
    super.key,
    GitHubReleaseUpdateService? updateService,
  }) : _updateService = updateService;

  final Widget child;
  final GitHubReleaseUpdateService? _updateService;

  @override
  State<UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends State<UpdateCheckGate> {
  late final GitHubReleaseUpdateService _updateService =
      widget._updateService ?? GitHubReleaseUpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    try {
      final update = await _updateService.findUpdate();
      if (!mounted || update == null) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => _UpdateDialog(update: update),
      );
    } catch (_) {
      // Update checks must never interrupt app startup.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final copy = _UpdateDialogCopy.forLocale(locale);

    return AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded),
      title: Text(copy.title),
      content: Text(
        copy.message(
          currentVersion: update.currentVersion,
          latestVersion: update.latestVersion,
          assetName: update.assetName,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.later),
        ),
        OutlinedButton(
          onPressed: () {
            _launch(update.releaseUrl);
            Navigator.of(context).pop();
          },
          child: Text(copy.releaseNotes),
        ),
        FilledButton(
          onPressed: () {
            _launch(update.downloadUrl);
            Navigator.of(context).pop();
          },
          child: Text(copy.download),
        ),
      ],
    );
  }

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _UpdateDialogCopy {
  const _UpdateDialogCopy({
    required this.title,
    required this.later,
    required this.releaseNotes,
    required this.download,
    required String Function({
      required String currentVersion,
      required String latestVersion,
      required String assetName,
    })
    messageBuilder,
  }) : _message = messageBuilder;

  final String title;
  final String later;
  final String releaseNotes;
  final String download;
  final String Function({
    required String currentVersion,
    required String latestVersion,
    required String assetName,
  })
  _message;

  String message({
    required String currentVersion,
    required String latestVersion,
    required String assetName,
  }) {
    return _message(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      assetName: assetName,
    );
  }

  static _UpdateDialogCopy forLocale(String languageCode) {
    if (languageCode == 'de') {
      return _UpdateDialogCopy(
        title: 'Update verfuegbar',
        later: 'Spaeter',
        releaseNotes: 'Details',
        download: 'Update laden',
        messageBuilder:
            ({
              required currentVersion,
              required latestVersion,
              required assetName,
            }) =>
                'Version $latestVersion ist verfuegbar. Installiert ist '
                'Version $currentVersion.\n\nDownload: $assetName',
      );
    }

    return _UpdateDialogCopy(
      title: 'Update available',
      later: 'Later',
      releaseNotes: 'Details',
      download: 'Download update',
      messageBuilder:
          ({
            required currentVersion,
            required latestVersion,
            required assetName,
          }) =>
              'Version $latestVersion is available. You are currently running '
              'version $currentVersion.\n\nDownload: $assetName',
    );
  }
}
