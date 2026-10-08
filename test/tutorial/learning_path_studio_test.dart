import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_studio.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
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
    await tester.enterText(
      find.byKey(const ValueKey('learning-step-title')),
      'Projection',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-step-instruction')),
      'Inspect the SELECT node.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-callout-title')),
      'SELECT',
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
    await tester.pump();
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
