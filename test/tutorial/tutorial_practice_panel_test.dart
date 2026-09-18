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

void main() {
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
