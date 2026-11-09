import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_studio.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';
import 'package:nodeql/features/tutorial/workshop_admin_extension.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_controller.dart';

import 'classroom_share_panel.dart';

class WorkshopAdminLauncher extends ConsumerWidget {
  const WorkshopAdminLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authoring = ref.watch(workshopAuthoringProvider);
    final catalog = ref.watch(translationControllerProvider).catalog;
    return FilledButton.tonalIcon(
      key: const ValueKey('workshop-learning-path-studio'),
      onPressed: authoring
          ? null
          : () => ref.read(workshopAuthoringProvider.notifier).state = true,
      icon: const Icon(Icons.edit_outlined),
      label: Text(catalog.text('tutorial.studio.returnToEditor')),
    );
  }
}

class WorkshopAdminPanel extends ConsumerStatefulWidget {
  const WorkshopAdminPanel({required this.onStart, super.key});

  final Future<void> Function(AuthoredLearningPath) onStart;

  @override
  ConsumerState<WorkshopAdminPanel> createState() => _WorkshopAdminPanelState();
}

class _WorkshopAdminPanelState extends ConsumerState<WorkshopAdminPanel> {
  late final Future<void> _initialization;
  AuthoredLearningPath? _sharing;

  @override
  void initState() {
    super.initState();
    _initialization = ref
        .read(learningPathLibraryProvider.notifier)
        .initialize();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(translationControllerProvider).catalog;
    ref.watch(workspaceProvider.select((state) => state.revision));
    final mode = ref.watch(sqlModeProvider);
    final controller = ref.read(learningPathLibraryProvider.notifier);
    return Stack(
      children: [
        Offstage(
          offstage: _sharing != null,
          child: FutureBuilder<void>(
            future: _initialization,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return LearningPathStudioPanel(
                catalog: catalog,
                paths: _draftsFirst(controller),
                workspaceNodes: ref
                    .read(workspaceProvider.notifier)
                    .allBlocks(),
                workspaceMode: mode == SqlAbstractionMode.advanced
                    ? LearningPathMode.advanced
                    : LearningPathMode.simple,
                onHighlightsChanged: (ids) =>
                    ref
                            .read(workshopAuthoringHighlightsProvider.notifier)
                            .state =
                        ids,
                onStart: widget.onStart,
                onSave: controller.save,
                onDelete: controller.delete,
                onImport: () => _importBundle(controller),
                onExport: (_) =>
                    _saveBundle(controller.exportBundle(), 'workshops.json'),
                onExportRemote: _exportRemoteBundle,
                onShareClassroom: (path) => setState(() => _sharing = path),
              );
            },
          ),
        ),
        if (_sharing case final path?)
          Positioned.fill(
            child: ClassroomSharePanel(
              catalog: catalog,
              path: path,
              onClose: () => setState(() => _sharing = null),
              onSaveFile: () => _exportRemoteBundle(
                path,
                dialogTitle: catalog.text('tutorial.classroom.saveFile'),
              ),
            ),
          ),
      ],
    );
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
