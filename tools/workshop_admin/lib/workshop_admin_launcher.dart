import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_studio.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_controller.dart';

class WorkshopAdminLauncher extends ConsumerWidget {
  const WorkshopAdminLauncher({required this.onStart, super.key});

  final ValueChanged<AuthoredLearningPath> onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(translationControllerProvider).catalog;
    return FilledButton.tonalIcon(
      key: const ValueKey('workshop-learning-path-studio'),
      onPressed: () => _open(context, ref),
      icon: const Icon(Icons.add_road_rounded),
      label: Text(catalog.text('tutorial.studio.adminBadge')),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(learningPathLibraryProvider.notifier);
    await controller.initialize();
    if (!context.mounted) return;
    final selected = await showDialog<AuthoredLearningPath>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LearningPathStudioDialog(
        catalog: ref.read(translationControllerProvider).catalog,
        paths: ref.read(learningPathLibraryProvider).paths,
        workspaceNodes: ref
            .read(workspaceProvider.notifier)
            .allBlocks()
            .toList(growable: false),
        onSave: controller.save,
        onDelete: controller.delete,
        onImport: () => _importBundle(ref, controller),
        onExport: _exportBundle,
      ),
    );
    if (selected != null) onStart(selected);
  }

  Future<List<AuthoredLearningPath>> _importBundle(
    WidgetRef ref,
    LearningPathLibraryController controller,
  ) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (picked == null) return ref.read(learningPathLibraryProvider).paths;
    final bundle = utf8.decode(await picked.readAsBytes());
    await controller.importBundle(bundle);
    return ref.read(learningPathLibraryProvider).paths;
  }

  Future<void> _exportBundle(List<AuthoredLearningPath> paths) async {
    await FilePicker.saveFile(
      dialogTitle: 'Publish NodeQL workshop bundle',
      fileName: 'workshops.json',
      bytes: utf8.encode(encodeLearningPathBundle(paths)),
      mimeType: 'application/json',
    );
  }
}
