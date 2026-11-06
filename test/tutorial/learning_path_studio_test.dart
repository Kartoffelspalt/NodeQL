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
      steps: [],
    );
    AuthoredLearningPath? shared;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningPathStudioDialog(
          catalog: _englishCatalog(),
          paths: const [path],
          workspaceNodes: const [],
          onSave: (_) async {},
          onDelete: (_) async {},
          onShareClassroom: (path) => shared = path,
        ),
      ),
    );
    await tester.tap(find.text('Share with class'));
    expect(shared, same(path));
  });

  testWidgets('creates a path step from workspace nodes with a callout', (
    tester,
  ) async {
    AuthoredLearningPath? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningPathStudioDialog(
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
          onSave: (path) async => saved = path,
          onDelete: (_) async {},
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
    await tester.tap(
      find.byKey(const ValueKey('workshop-action-node-enterInput')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT name FROM customers').last);
    await tester.pumpAndSettle();
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
