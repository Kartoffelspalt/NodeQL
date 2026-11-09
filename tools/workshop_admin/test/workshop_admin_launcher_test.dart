import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/app/nodeql_app.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/workshop_admin_extension.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:nodeql/localization/translation_repository.dart';
import 'package:nodeql_workshop_admin/workshop_admin_launcher.dart';

void main() {
  testWidgets('creates beside the live canvas and restores it after testing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final directory = Directory.systemTemp.createTempSync(
      'nodeql-inline-studio-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        null,
      ),
    );
    final file = File('${directory.path}/drafts.json');
    final library = await tester.runAsync(() async {
      final controller = LearningPathLibraryController(
        storageFile: () async => file,
        bundledPaths: () async => const [],
      );
      await controller.initialize();
      return controller;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          learningPathLibraryProvider.overrideWith((_) => library!),
          translationControllerProvider.overrideWith(
            (_) => _StudioTranslationController(),
          ),
          workshopAdminPanelProvider.overrideWithValue(
            (context, ref, onStart) => WorkshopAdminPanel(onStart: onStart),
          ),
          workshopAdminActionProvider.overrideWithValue(
            (context, ref, onStart) => const WorkshopAdminLauncher(),
          ),
        ],
        child: const NodeQlApp(),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 1');
    final panel = find.byKey(const ValueKey('workshop-creation-panel'));
    expect(panel, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('workshop-run-sqlite')), findsNothing);
    final scope = ProviderScope.containerOf(tester.element(panel));
    final workspace = scope.read(workspaceProvider.notifier);
    final initialIds = workspace.allBlocks().map((node) => node.id).toSet();
    await tester.tap(find.byKey(const ValueKey('learning-path-create')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 2');
    await tester.enterText(
      find.byKey(const ValueKey('learning-path-title')),
      'Customers from Berlin',
    );
    await tester.tap(find.byKey(const ValueKey('learning-path-add-step')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 3');
    await tester.enterText(
      find.byKey(const ValueKey('learning-step-title')),
      'Choose a table',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-step-instruction')),
      'Enter customers in the table field.',
    );
    // A node added while a step is being edited is available without leaving the form.
    final select = workspace.addTemplate(
      BlockType.sqlSelect,
      workspace.suggestedTemplatePosition(BlockType.sqlSelect),
      defaults: {'table': 'customers', 'columns': 'name'},
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 4');
    final useNodes = find.byKey(const ValueKey('learning-step-use-workspace'));
    await tester.ensureVisible(useNodes);
    await tester.tap(useNodes);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 5');
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('learning-step-apply')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 6');
    expect(find.text('Choose a table'), findsOneWidget);
    final testButton = find.byKey(const ValueKey('learning-path-try'));
    await tester.runAsync(() async {
      await tester.tap(testButton);
      for (
        var attempt = 0;
        attempt < 50 && scope.read(workshopAuthoringProvider);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 7');
    expect(scope.read(workshopAuthoringProvider), isFalse);
    expect(find.byKey(const ValueKey('workshop-run-sqlite')), findsOneWidget);
    expect(workspace.findById(select.id), isNull);
    expect(file.existsSync(), isTrue);
    expect(library!.drafts.single.steps.single.nodes.single.ref, select.id);
    await tester.tap(
      find.byKey(const ValueKey('workshop-learning-path-studio')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'stage 8');
    expect(panel, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('workshop-run-sqlite')), findsNothing);
    expect(workspace.allBlocks().map((node) => node.id).toSet(), {
      ...initialIds,
      select.id,
    });
    expect(workspace.findById(select.id)?.inputs['table'], 'customers');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('learning-path-title')))
          .controller!
          .text,
      'Customers from Berlin',
    );
    expect(find.text('Choose a table'), findsOneWidget);
    expect(scope.read(sqlModeProvider), SqlAbstractionMode.simple);
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.binding.setSurfaceSize(const Size(1024, 720));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'compact editor');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });
}

class _StudioTranslationController extends TranslationController {
  _StudioTranslationController() : super(FileTranslationRepository()) {
    final decoded =
        jsonDecode(File('../../assets/translations/en.json').readAsStringSync())
            as Map<String, dynamic>;
    final messages = Map<String, String>.from(decoded['messages'] as Map);
    state = TranslationState(
      loading: false,
      locale: const Locale('en'),
      catalog: TranslationCatalog(
        locale: 'en',
        messages: messages,
        englishMessages: messages,
      ),
    );
  }

  @override
  Future<void> initialize() async {}
}
