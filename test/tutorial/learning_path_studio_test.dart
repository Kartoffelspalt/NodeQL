import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_studio.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
  testWidgets('shares the workshop selected in the studio', (tester) async {
    const path = AuthoredLearningPath(
      id: 'classroom-example',
      title: 'My classroom workshop',
      description: '',
      steps: [_task],
    );
    AuthoredLearningPath? shared;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LearningPathStudioPanel(
            catalog: _englishCatalog(),
            paths: const [path],
            workspaceNodes: const [],
            onStart: (_) async {},
            onSave: (_) async {},
            onDelete: (_) async {},
            onShareClassroom: (path) => shared = path,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Share with class'));
    await tester.pumpAndSettle();
    expect(shared, same(path));
  });

  testWidgets('blocks sharing an unfinished draft and explains why', (
    tester,
  ) async {
    var shared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LearningPathStudioPanel(
            catalog: _englishCatalog(),
            paths: const [_unfinished],
            workspaceNodes: const [],
            onStart: (_) async {},
            onSave: (_) async {},
            onDelete: (_) async {},
            onShareClassroom: (_) => shared = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Share with class'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(shared, isFalse);
    expect(
      find.widgetWithText(AlertDialog, 'Add at least one step.'),
      findsOneWidget,
    );
  });

  testWidgets('reviews import and inserts a copy without replacing an ID', (
    tester,
  ) async {
    final batches = <List<AuthoredLearningPath>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LearningPathStudioPanel(
            catalog: _englishCatalog(),
            paths: const [_unfinished],
            workspaceNodes: const [],
            onStart: (_) async {},
            onSave: (_) async {},
            onDelete: (_) async {},
            onImport: () async => const [
              AuthoredLearningPath(
                id: 'draft',
                title: 'Incoming workshop',
                description: '',
                steps: [_task],
              ),
            ],
            onImportSave: (drafts) async => batches.add(drafts),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Incoming workshop'), findsOneWidget);
    expect(batches, isEmpty);
    await tester.tap(find.text('Import as drafts'));
    await tester.pumpAndSettle();
    final imported = batches.single.single;
    expect(imported.id, isNot(_unfinished.id));
    expect(imported.steps.single.id, _task.id);
    expect(find.text('Unfinished draft'), findsOneWidget);
    expect(find.text('Incoming workshop'), findsOneWidget);
  });

  testWidgets('keeps unsaved changes when canceling the discard prompt', (
    tester,
  ) async {
    AuthoredLearningPath? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LearningPathStudioPanel(
            catalog: _englishCatalog(),
            paths: const [],
            workspaceNodes: const [],
            onStart: (_) async {},
            onSave: (path) async => saved = path,
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('learning-path-create')));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('learning-path-title'));
    await tester.enterText(title, 'Keep this draft');
    final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Back to editing'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(title).controller!.text, 'Keep this draft');
    await tester.tap(find.byKey(const ValueKey('learning-path-save')));
    await tester.pumpAndSettle();
    expect(saved?.title, 'Keep this draft');
    expect(saved?.steps, isEmpty);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Keep this draft'), findsOneWidget);
  });

  testWidgets('exports only selected catalog workshops that pass review', (
    tester,
  ) async {
    const official = AuthoredLearningPath(
      id: 'official',
      title: 'Official workshop',
      description: '',
      steps: [_task],
    );
    const readyDraft = AuthoredLearningPath(
      id: 'ready-draft',
      title: 'Ready draft',
      description: '',
      steps: [_task],
    );
    List<AuthoredLearningPath>? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LearningPathStudioPanel(
            catalog: _englishCatalog(),
            paths: const [_unfinished, official, readyDraft],
            draftIds: const {'draft', 'ready-draft'},
            workspaceNodes: const [],
            onStart: (_) async {},
            onSave: (_) async {},
            onDelete: (_) async {},
            onExport: (paths) async => exported = paths,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export catalog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final unfinished = find.byKey(const ValueKey('catalog-draft'));
    expect(tester.widget<CheckboxListTile>(unfinished).onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('catalog-official')));
    await tester.pump();
    await tester.tap(find.text('Export selection'));
    await tester.pumpAndSettle();
    expect(exported, [readyDraft]);
  });

  testWidgets('creates a path step from workspace nodes with a callout', (
    tester,
  ) async {
    AuthoredLearningPath? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LearningPathStudioPanel(
            catalog: _englishCatalog(),
            paths: const [],
            workspaceNodes: [
              OperatorBlock(
                id: 'select-node',
                position: Offset.zero,
                operatorType: BlockType.sqlSelect,
                inputs: {'columns': 'name', 'table': 'customers'},
              ),
              OperatorBlock(
                id: 'where-node',
                position: const Offset(0, 80),
                operatorType: BlockType.sqlWhere,
              ),
            ],
            onStart: (_) async {},
            onSave: (path) async => saved = path,
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('learning-path-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-path-title')),
      'SELECT explained',
    );
    await tester.tap(find.byKey(const ValueKey('learning-path-add-step')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('learning-callout-title')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('learning-step-title')),
      'Projection',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-step-instruction')),
      'Inspect the SELECT node.',
    );
    final nodes = find.byKey(const ValueKey('learning-step-nodes'));
    await tester.ensureVisible(nodes);
    await tester.tap(nodes);
    await tester.pumpAndSettle();
    final filter = find.byKey(const ValueKey('learning-step-node-where-node'));
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    final labels = find.byKey(const ValueKey('learning-step-callouts'));
    await tester.ensureVisible(labels);
    await tester.tap(labels);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-callout-title')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-callout-title')),
      'SELECT',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-callout-body')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-callout-body')),
      'Chooses the returned columns.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-callout-add')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('learning-callout-add')));
    await tester.pumpAndSettle();
    final interactions = find.byKey(
      const ValueKey('learning-step-interactions'),
    );
    await tester.ensureVisible(interactions);
    await tester.tap(interactions);
    await tester.pumpAndSettle();
    final highlight = find.widgetWithText(
      FilterChip,
      'SELECT name FROM customers',
    );
    await tester.ensureVisible(highlight);
    await tester.tap(highlight);
    await tester.pumpAndSettle();
    final addRule = find.byKey(const ValueKey('workshop-action-add'));
    await tester.ensureVisible(addRule);
    await tester.tap(addRule);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('workshop-action-node-enterInput')),
    );
    await tester.tap(
      find.byKey(const ValueKey('workshop-action-node-enterInput')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT name FROM customers').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('workshop-action-input-enterInput-select-node'),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('workshop-action-input-enterInput-select-node'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workshop-action-value')),
      'customers',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('workshop-action-apply')),
    );
    await tester.tap(find.byKey(const ValueKey('workshop-action-apply')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-step-apply')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-step-apply')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-path-save')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-path-save')));
    await tester.pumpAndSettle();

    expect(saved?.title, 'SELECT explained');
    expect(saved?.steps.single.nodes.single.type, BlockType.sqlSelect);
    expect(saved?.steps.single.callouts.single.targetRef, 'select-node');
    expect(saved?.steps.single.highlights, ['select-node']);
    expect(
      saved?.steps.single.requirements.single.action,
      LearningPathAction.enterInput,
    );
    expect(saved?.steps.single.requirements.single.input, 'table');
    expect(saved?.steps.single.requirements.single.value, 'customers');
  });
}

const _task = LearningPathStep(
  id: 'task',
  title: 'Explain SELECT',
  instruction: 'Describe what the query returns.',
);

const _unfinished = AuthoredLearningPath(
  id: 'draft',
  title: 'Unfinished draft',
  description: '',
  steps: [],
);

TranslationCatalog _englishCatalog() {
  final decoded =
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
  final messages = (decoded['messages'] as Map<String, dynamic>).map(
    (key, value) => MapEntry(key, value as String),
  );
  return TranslationCatalog(
    locale: 'en',
    messages: messages,
    englishMessages: messages,
  );
}
