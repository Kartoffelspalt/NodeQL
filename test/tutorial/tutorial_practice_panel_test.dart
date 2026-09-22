import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';
import 'package:nodeql/features/tutorial/tutorial_practice_panel.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_controller.dart';

void main() {
  test(
    'every practical mission and node explanation has English and German copy',
    () {
      final english = _englishCatalog().messages;
      final german = builtInMessages['de']!;
      for (final definition in tutorialPracticeDefinitions.values) {
        for (var index = 0; index < definition.stepCount; index++) {
          final prefix = definition.stepKey(index);
          for (final field in [
            'title',
            'instruction',
            'hint',
            'example',
            'concept',
          ]) {
            expect(
              english['$prefix.$field'],
              isNotEmpty,
              reason: '$prefix.$field',
            );
            expect(
              german['$prefix.$field'],
              isNotEmpty,
              reason: '$prefix.$field',
            );
          }
          for (final node in definition.steps[index].focusNodes) {
            final nodeKey = 'tutorial.practice.node.${node.name}';
            expect(english['$nodeKey.title'], isNotEmpty, reason: nodeKey);
            expect(english['$nodeKey.body'], isNotEmpty, reason: nodeKey);
            expect(german['$nodeKey.title'], isNotEmpty, reason: nodeKey);
            expect(german['$nodeKey.body'], isNotEmpty, reason: nodeKey);
          }
          for (final check in definition.steps[index].checks) {
            final checkKey = 'tutorial.practice.check.${check.name}';
            expect(english[checkKey], isNotEmpty, reason: checkKey);
            expect(german[checkKey], isNotEmpty, reason: checkKey);
          }
        }
      }
    },
  );

  testWidgets('Simple Mode explains labels while showing live SQLite', (
    tester,
  ) async {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginner]!;
    final result = definition.evaluate([
      EventBlock(id: 'event', position: Offset.zero),
    ], 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: TutorialPracticePanel(
            catalog: _englishCatalog(),
            session: const TutorialPracticeSession(
              mode: TutorialKnowledgeMode.beginner,
            ),
            definition: definition,
            result: result,
            abstractionMode: SqlAbstractionMode.simple,
            localeCode: 'en',
            liveSql: 'SELECT * FROM customers;',
            onCheck: () {},
            onHint: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.text('Simple Mode'), findsOneWidget);
    expect(find.textContaining('plain-language node labels'), findsOneWidget);
    expect(find.text('0 of 2 requirements complete'), findsOneWidget);
    expect(
      find.text('Next: SELECT is connected to EXECUTE QUERY'),
      findsOneWidget,
    );
    expect(find.text('Understand these nodes'), findsOneWidget);
    expect(find.textContaining('Simple Mode label:'), findsWidgets);
    expect(find.textContaining('SQLite label:'), findsWidgets);
    expect(
      find.byKey(const ValueKey('tutorial-practice-progress')),
      findsOneWidget,
    );
    expect(find.text('SELECT * FROM customers;'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('description panel can be resized within its safe limits', (
    tester,
  ) async {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginner]!;
    final result = definition.evaluate([
      EventBlock(id: 'event', position: Offset.zero),
    ], 0);
    double? resizedHeight;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TutorialPracticePanel(
            catalog: _englishCatalog(),
            session: const TutorialPracticeSession(
              mode: TutorialKnowledgeMode.beginner,
            ),
            definition: definition,
            result: result,
            abstractionMode: SqlAbstractionMode.simple,
            localeCode: 'en',
            liveSql: '',
            onCheck: () {},
            onHint: () {},
            onClose: () {},
            height: 300,
            minHeight: 220,
            maxHeight: 360,
            onHeightChanged: (height) => resizedHeight = height,
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('tutorial-practice-resize-handle')),
      const Offset(0, 140),
    );
    expect(resizedHeight, 360);
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
