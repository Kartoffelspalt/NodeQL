import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/localization/translation_catalog.dart';

import 'classroom_workshop_session.dart';

class ClassroomShareDialog extends StatefulWidget {
  const ClassroomShareDialog({
    required this.catalog,
    required this.path,
    required this.onSaveFile,
    super.key,
  });

  final TranslationCatalog catalog;
  final AuthoredLearningPath path;
  final Future<void> Function() onSaveFile;

  @override
  State<ClassroomShareDialog> createState() => _ClassroomShareDialogState();
}

class _ClassroomShareDialogState extends State<ClassroomShareDialog> {
  List<ClassroomNetwork> _networks = [];
  InternetAddress? _address;
  ClassroomWorkshopSession? _session;
  String? _error;
  bool _busy = true;
  bool _expired = false;
  bool _copied = false;

  TranslationCatalog get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    unawaited(_findAddresses());
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(session.stop());
    super.dispose();
  }

  Future<void> _findAddresses() async {
    try {
      final networks = await ClassroomWorkshopSession.networks();
      if (!mounted) return;
      setState(() {
        _networks = networks;
        _address = networks.firstOrNull?.address;
      });
    } on Exception {
      if (mounted) setState(() => _error = 'tutorial.classroom.hostFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final address = _address;
    if (address == null || _busy || _session != null) return;
    setState(() {
      _busy = true;
      _error = null;
      _expired = false;
    });
    try {
      final session = await ClassroomWorkshopSession.start(
        address: address,
        source: encodeLearningPathBundle([widget.path]),
      );
      if (!mounted) {
        await session.stop();
        return;
      }
      setState(() => _session = session);
      unawaited(_waitForEnd(session));
    } on FormatException {
      if (mounted) setState(() => _error = 'tutorial.download.exportError');
    } on Exception {
      if (mounted) setState(() => _error = 'tutorial.classroom.hostFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _waitForEnd(ClassroomWorkshopSession session) async {
    await session.closed;
    if (!mounted || _session != session) return;
    setState(() {
      _session = null;
      _copied = false;
      _expired = true;
    });
  }

  Future<void> _copy(ClassroomWorkshopSession session) async {
    try {
      await Clipboard.setData(ClipboardData(text: session.code.encode()));
      if (mounted && _session == session) {
        setState(() {
          _copied = true;
          _error = null;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _error = 'tutorial.classroom.copyFailed');
    }
  }

  Future<void> _saveFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSaveFile();
    } on FormatException {
      if (mounted) setState(() => _error = 'tutorial.download.exportError');
    } on Exception {
      if (mounted) setState(() => _error = 'tutorial.classroom.saveFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    final session = _session;
    if (session != null) unawaited(session.stop());
    Navigator.of(context).pop();
  }

  Widget _buildCodeCard(ClassroomWorkshopSession session) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final expires = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(session.expiresAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    catalog.text('tutorial.classroom.codeReady'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              session.code.encode(),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              catalog.text('tutorial.classroom.until', {'time': expires}),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final error = _error;
    final canStart = _address != null;
    return AlertDialog(
      title: Text(catalog.text('tutorial.classroom.share')),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.path.titleFor(catalog.locale),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (session == null) ...[
              if (canStart)
                Text(catalog.text('tutorial.classroom.hostHelp'))
              else if (!_busy && error == null)
                Text(catalog.text('tutorial.classroom.noAddress')),
              if (_networks.length > 1)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  expandedAlignment: AlignmentDirectional.centerStart,
                  title: Text(catalog.text('tutorial.classroom.changeNetwork')),
                  children: [
                    DropdownMenu<InternetAddress>(
                      initialSelection: _address,
                      label: Text(catalog.text('tutorial.classroom.interface')),
                      enabled: !_busy,
                      dropdownMenuEntries: [
                        for (final network in _networks)
                          DropdownMenuEntry(
                            value: network.address,
                            label:
                                '${network.name} · ${network.address.address}',
                          ),
                      ],
                      onSelected: (address) =>
                          setState(() => _address = address),
                    ),
                  ],
                ),
              if (_expired) Text(catalog.text('tutorial.classroom.expired')),
            ] else ...[
              _buildCodeCard(session),
              const SizedBox(height: 12),
              Text(catalog.text('tutorial.classroom.shareHelp')),
            ],
            if (canStart || session != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _saveFile,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(catalog.text('tutorial.classroom.saveFile')),
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  catalog.text(error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: Text(
            catalog.text(
              session == null
                  ? 'tutorial.studio.cancel'
                  : 'tutorial.classroom.stop',
            ),
          ),
        ),
        if (session != null)
          FilledButton.icon(
            onPressed: _busy ? null : () => _copy(session),
            icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
            label: Semantics(
              liveRegion: true,
              child: Text(
                catalog.text(
                  _copied
                      ? 'tutorial.classroom.copied'
                      : 'tutorial.classroom.copy',
                ),
              ),
            ),
          )
        else
          FilledButton.icon(
            onPressed: _busy ? null : (canStart ? _start : _saveFile),
            icon: Icon(canStart || _busy ? Icons.key_outlined : Icons.save_alt),
            label: Text(
              catalog.text(
                canStart || _busy
                    ? 'tutorial.classroom.start'
                    : 'tutorial.classroom.saveFile',
              ),
            ),
          ),
      ],
    );
  }
}
