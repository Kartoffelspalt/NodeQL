import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:nodeql/localization/translation_repository.dart';
import 'package:nodeql_workshop_admin/workshop_admin_launcher.dart';

void main() {
  testWidgets('exposes the private Workshop Studio action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: WorkshopAdminLauncher(onStart: (_) {})),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workshop-learning-path-studio')),
      findsOneWidget,
    );
  });

  testWidgets(
    'resumes a draft after editing nodes and opens the saved workshop',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'nodeql-studio-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/drafts.json');
      final library = await tester.runAsync(() async {
        final controller = LearningPathLibraryController(
          storageFile: () async => file,
          bundledPaths: () async => const [],
        );
        await controller.initialize();
        return controller;
      });
      final workspace = WorkspaceController()..resetWithRoot();
      final mode = SqlModeController.session();
      AuthoredLearningPath? started;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            learningPathLibraryProvider.overrideWith((_) => library!),
            workspaceProvider.overrideWith((_) => workspace),
            sqlModeProvider.overrideWith((_) => mode),
            translationControllerProvider.overrideWith(
              (_) => _StudioTranslationController(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WorkshopAdminLauncher(onStart: (path) => started = path),
            ),
          ),
        ),
      );

      final launcher = find.byKey(
        const ValueKey('workshop-learning-path-studio'),
      );
      final addStep = find.byKey(const ValueKey('learning-path-add-step'));
      final workshopTitle = find.byKey(const ValueKey('learning-path-title'));
      Future<void> openStudio() async {
        await tester.runAsync(() async {
          await tester.tap(launcher);
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
      }

      Future<void> addTask(String title, String task) async {
        await tester.ensureVisible(addStep);
        await tester.tap(addStep);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('learning-step-title')),
          title,
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-step-instruction')),
          task,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('learning-step-apply')));
        await tester.pumpAndSettle();
      }

      await openStudio();
      await tester.tap(find.byKey(const ValueKey('learning-path-create')));
      await tester.pumpAndSettle();
      await tester.enterText(workshopTitle, 'Customer queries');
      await addTask('Read the task', 'Explain what SELECT does.');
      final workspaceAction = find.text('tutorial.studio.editWorkspace');
      await tester.ensureVisible(workspaceAction);
      await tester.runAsync(() async {
        await tester.tap(workspaceAction);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('tutorial.studio.resumeDraft'), findsOneWidget);
      expect(tester.widget<FilledButton>(launcher).onPressed, isNotNull);
      expect(file.existsSync(), isFalse);
      workspace.addTemplate(
        BlockType.sqlSelect,
        const Offset(80, 40),
        defaults: {'table': 'customers', 'columns': 'name'},
      );
      await mode.setMode(SqlAbstractionMode.advanced);

      await openStudio();
      expect(
        tester.widget<TextField>(workshopTitle).controller!.text,
        'Customer queries',
      );
      expect(find.text('Read the task'), findsOneWidget);
      await addTask('Choose columns', 'Show the customers’ names.');
      final tryButton = find.byKey(const ValueKey('learning-path-try'));
      expect(tester.widget<FilledButton>(tryButton).onPressed, isNotNull);
      await tester.runAsync(() async {
        final saved = Completer<void>.sync();
        final removeListener = library!.addListener((state) {
          if (state.paths.isNotEmpty && !saved.isCompleted) saved.complete();
        }, fireImmediately: false);
        try {
          await tester.tap(tryButton);
          await saved.future.timeout(const Duration(seconds: 3));
          await Future<void>.delayed(Duration.zero);
        } finally {
          removeListener();
        }
      });
      await tester.pumpAndSettle();

      expect(started, isNotNull);
      final path = started!;
      expect(path.steps, hasLength(2));
      expect(path.steps.first.nodes, isEmpty);
      expect(path.steps.last.mode, LearningPathMode.advanced);
      expect(path.steps.last.nodes.single.type, BlockType.sqlSelect);
      expect(path.steps.last.nodes.single.defaults['table'], 'customers');
      expect(library!.state.paths.single.id, path.id);
      expect(
        validateRemoteWorkshopBundle(file.readAsStringSync()).title,
        path.title,
      );
    },
  );
}

class _StudioTranslationController extends TranslationController {
  _StudioTranslationController() : super(FileTranslationRepository());

  @override
  Future<void> initialize() async {}
}
