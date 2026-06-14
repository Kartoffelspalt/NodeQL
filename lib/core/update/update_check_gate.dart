import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/localization/translation_controller.dart';
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

class _UpdateDialog extends ConsumerWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(translationControllerProvider).catalog;

    return AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded),
      title: Text(catalog.text('update.title')),
      content: Text(
        catalog.text('update.message', {
          'currentVersion': update.currentVersion,
          'latestVersion': update.latestVersion,
          'assetName': update.assetName,
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(catalog.text('update.later')),
        ),
        OutlinedButton(
          onPressed: () {
            _launch(update.releaseUrl);
            Navigator.of(context).pop();
          },
          child: Text(catalog.text('update.details')),
        ),
        FilledButton(
          onPressed: () {
            _launch(update.downloadUrl);
            Navigator.of(context).pop();
          },
          child: Text(catalog.text('update.download')),
        ),
      ],
    );
  }

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
