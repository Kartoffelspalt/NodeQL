import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:url_launcher/url_launcher.dart';

import 'desktop_update_installer.dart';
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
      if (await _usesNativeMacUpdater()) {
        return;
      }
      final update = await _updateService.findUpdate();
      if (!mounted || update == null) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _UpdateDialog(update: update),
      );
    } catch (_) {
      // Update checks must never interrupt app startup.
    }
  }

  Future<bool> _usesNativeMacUpdater() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }
    const channel = MethodChannel('nodeql/macos_updater');
    try {
      return await channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  final _installer = DesktopUpdateInstaller();
  bool _installing = false;
  bool _failed = false;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _failed = false;
    });
    try {
      await _installer.install(widget.update);
    } catch (error) {
      debugPrint('NodeQL update failed: $error');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final canInstall = _installer.canInstall(update);
    final catalog = ref.watch(translationControllerProvider).catalog;

    return PopScope(
      canPop: !_installing,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded),
        title: Text(catalog.text('update.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              catalog.text('update.message', {
                'currentVersion': update.currentVersion,
                'latestVersion': update.latestVersion,
                'assetName': update.assetName,
              }),
            ),
            if (canInstall) ...[
              const SizedBox(height: 12),
              Text(catalog.text('update.restartNotice')),
            ],
            if (_installing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(catalog.text('update.installFailed')),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _installing ? null : () => Navigator.of(context).pop(),
            child: Text(catalog.text('update.later')),
          ),
          OutlinedButton(
            onPressed: _installing
                ? null
                : () {
                    _launch(update.releaseUrl);
                    Navigator.of(context).pop();
                  },
            child: Text(catalog.text('update.details')),
          ),
          if (!canInstall || (_failed && !_installing))
            FilledButton(
              onPressed: () {
                _launch(update.downloadUrl);
                Navigator.of(context).pop();
              },
              child: Text(catalog.text('update.download')),
            ),
          if (canInstall)
            FilledButton(
              onPressed: _installing ? null : _install,
              child: Text(catalog.text('update.install')),
            ),
        ],
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
