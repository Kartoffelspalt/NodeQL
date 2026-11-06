import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_studio.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_controller.dart';

import 'classroom_share_dialog.dart';

class WorkshopAdminLauncher extends ConsumerStatefulWidget {
  const WorkshopAdminLauncher({required this.onStart, super.key});

  final ValueChanged<AuthoredLearningPath> onStart;

  @override
  ConsumerState<WorkshopAdminLauncher> createState() =>
      _WorkshopAdminLauncherState();
}

class _WorkshopAdminLauncherState extends ConsumerState<WorkshopAdminLauncher> {
  AuthoredLearningPath? _draft;
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(translationControllerProvider).catalog;
    final resuming = _draft != null;
    return FilledButton.tonalIcon(
      key: const ValueKey('workshop-learning-path-studio'),
      onPressed: _opening ? null : _open,
      icon: Icon(resuming ? Icons.edit_outlined : Icons.add_road_rounded),
      label: Text(
        catalog.text(
          resuming
              ? 'tutorial.studio.resumeDraft'
              : 'tutorial.studio.adminBadge',
        ),
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final controller = ref.read(learningPathLibraryProvider.notifier);
      await controller.initialize();
      if (!mounted) return;
      final draft = _draft;
      _draft = null;
      final catalog = ref.read(translationControllerProvider).catalog;
      final workspaceNodes = ref.read(workspaceProvider.notifier).allBlocks();
      final workspaceMode =
          ref.read(sqlModeProvider) == SqlAbstractionMode.advanced
          ? LearningPathMode.advanced
          : LearningPathMode.simple;
      final selected = await showDialog<AuthoredLearningPath>(
        context: context,
        barrierDismissible: false,
        builder: (studioContext) => LearningPathStudioDialog(
          catalog: catalog,
          paths: _draftsFirst(controller),
          initialDraft: draft,
          workspaceNodes: workspaceNodes,
          workspaceMode: workspaceMode,
          onEditWorkspace: (draft) {
            setState(() => _draft = draft);
            Navigator.of(studioContext).pop();
          },
          onSave: controller.save,
          onDelete: controller.delete,
          onImport: () => _importBundle(controller),
          onExport: (_) =>
              _saveBundle(controller.exportBundle(), 'workshops.json'),
          onExportRemote: _exportRemoteBundle,
          onShareClassroom: (path) => showDialog<void>(
            context: studioContext,
            builder: (_) => ClassroomShareDialog(
              catalog: catalog,
              path: path,
              onSaveFile: () => _exportRemoteBundle(
                path,
                dialogTitle: catalog.text('tutorial.classroom.saveFile'),
              ),
            ),
          ),
        ),
      );
      if (mounted && selected != null) widget.onStart(selected);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  List<AuthoredLearningPath> _draftsFirst(
    LearningPathLibraryController controller,
  ) {
    final drafts = controller.drafts;
    final draftIds = {for (final draft in drafts) draft.id};
    return [
      ...drafts,
      for (final path in ref.read(learningPathLibraryProvider).paths)
        if (!draftIds.contains(path.id)) path,
    ];
  }

  Future<List<AuthoredLearningPath>> _importBundle(
    LearningPathLibraryController controller,
  ) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (picked != null) {
      final bundle = utf8.decode(await picked.readAsBytes());
      await controller.importBundle(bundle);
    }
    return _draftsFirst(controller);
  }

  Future<void> _exportRemoteBundle(
    AuthoredLearningPath path, {
    String? dialogTitle,
  }) async {
    final source = encodeLearningPathBundle([path]);
    validateRemoteWorkshopBundle(source);
    await _saveBundle(source, '${path.id}.json', dialogTitle: dialogTitle);
  }

  Future<void> _saveBundle(
    String source,
    String fileName, {
    String? dialogTitle,
  }) async {
    await FilePicker.saveFile(
      dialogTitle: dialogTitle ?? 'Publish NodeQL workshop bundle',
      fileName: fileName,
      bytes: utf8.encode(source),
      mimeType: 'application/json',
    );
  }
}
