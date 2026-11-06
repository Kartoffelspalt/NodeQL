import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nodeql/localization/translation_catalog.dart';

import 'classroom_workshop_code.dart';
import 'remote_workshop.dart';

class RemoteWorkshopDialog extends StatefulWidget {
  const RemoteWorkshopDialog({
    required this.catalog,
    required this.repository,
    super.key,
  });

  final TranslationCatalog catalog;
  final RemoteWorkshopRepository repository;

  @override
  State<RemoteWorkshopDialog> createState() => _RemoteWorkshopDialogState();
}

class _RemoteWorkshopDialogState extends State<RemoteWorkshopDialog> {
  final _link = TextEditingController();
  WorkshopDownload? _bundle;
  String? _source;
  String? _error;
  bool _busy = false;
  bool _showLink = false;

  TranslationCatalog get catalog => widget.catalog;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final input = _link.text.trim();
    if (_busy || input.isEmpty) return;
    final classroom =
        input.startsWith(ClassroomWorkshopCode.prefix) ||
        (!_showLink && !input.startsWith('https://'));
    try {
      if (classroom) {
        final code = ClassroomWorkshopCode.parse(input);
        await _preview(
          () => widget.repository.downloadClassroom(code),
          catalog.text('tutorial.classroom.verified'),
          'tutorial.classroom.joinFailed',
        );
      } else {
        final link = WorkshopDownloadLink.parse(input);
        await _preview(
          () => widget.repository.download(link),
          catalog.text('tutorial.download.source', {'host': link.uri.host}),
          'tutorial.download.failed',
        );
      }
    } on FormatException {
      setState(() {
        _error = classroom
            ? 'tutorial.classroom.invalidCode'
            : 'tutorial.download.invalidLink';
      });
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _busy || _bundle != null) return;
      final text = data?.text?.trim() ?? '';
      setState(() {
        if (text.isNotEmpty && text.length <= 2048) {
          _link.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          _error = null;
        } else {
          _error = 'tutorial.classroom.pasteFailed';
        }
      });
    } on PlatformException {
      if (mounted) setState(() => _error = 'tutorial.classroom.pasteFailed');
    }
  }

  Future<void> _pickFile() => _preview(
    () async {
      final file = await FilePicker.pickFile(
        dialogTitle: catalog.text('tutorial.classroom.openFile'),
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return null;
      return widget.repository.readFile(file.xFile.openRead());
    },
    catalog.text('tutorial.classroom.filePreview'),
    'tutorial.classroom.fileFailed',
  );

  Future<void> _preview(
    Future<WorkshopDownload?> Function() receive,
    String source,
    String errorKey,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bundle = await receive();
      if (!mounted || bundle == null) return;
      _link.clear();
      setState(() {
        _bundle = bundle;
        _source = source;
      });
    } on Exception {
      if (mounted) setState(() => _error = errorKey);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install(WorkshopDownload bundle) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.install(bundle);
      if (mounted) Navigator.of(context).pop(bundle.path);
    } on WorkshopLibraryFull {
      if (mounted) setState(() => _error = 'tutorial.download.full');
    } on Exception {
      if (mounted) setState(() => _error = 'tutorial.download.storageError');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildInput() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        catalog.text(
          _showLink
              ? 'tutorial.download.linkHelp'
              : 'tutorial.classroom.codeHelp',
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _link,
        autofocus: true,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 2048,
        keyboardType: TextInputType.url,
        textDirection: TextDirection.ltr,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _download(),
        decoration: InputDecoration(
          labelText: catalog.text(
            _showLink ? 'tutorial.download.link' : 'tutorial.classroom.code',
          ),
          border: const OutlineInputBorder(),
          counterText: '',
          suffixIcon: TextButton(
            onPressed: _busy ? null : _paste,
            child: Text(catalog.text('tutorial.classroom.paste')),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(catalog.text('tutorial.classroom.openFile')),
          ),
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _showLink = !_showLink;
                    _link.clear();
                    _error = null;
                  }),
            icon: Icon(_showLink ? Icons.key_outlined : Icons.link),
            label: Text(
              catalog.text(
                _showLink
                    ? 'tutorial.classroom.enterCode'
                    : 'tutorial.download.link',
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildPreview(WorkshopDownload bundle) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final path = bundle.path;
    final description = path.descriptionFor(catalog.locale);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_source!, style: theme.textTheme.labelLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              path.titleFor(catalog.locale),
              style: theme.textTheme.titleLarge,
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description),
            ],
            const SizedBox(height: 12),
            Text(catalog.text('tutorial.download.readOnly')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    final error = _error;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          catalog.text(
            bundle == null
                ? 'tutorial.download.title'
                : 'tutorial.download.preview',
          ),
        ),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bundle == null) _buildInput() else _buildPreview(bundle),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    catalog.text(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(catalog.text('tutorial.studio.cancel')),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : bundle == null
                ? (_link.text.trim().isEmpty ? null : _download)
                : () => _install(bundle),
            child: Text(
              catalog.text(
                bundle == null
                    ? 'tutorial.download.check'
                    : 'tutorial.download.install',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
