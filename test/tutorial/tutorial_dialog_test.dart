import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
  testWidgets('requires the correct exercise answer before continuing', (
    tester,
  ) async {
    var completed = false;
    final catalog = _englishCatalog();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: TutorialDialog(
          catalog: catalog,
          onComplete: () async => completed = true,
        ),
      ),
    );

    expect(find.text('Build SQL without losing sight of SQL'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();

    expect(find.text('Three areas, one workflow'), findsOneWidget);
    final nextButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('tutorial-next')),
    );
    expect(nextButton.onPressed, isNull);

    final wrongAnswer = find.byKey(const ValueKey('tutorial-answer-1-0'));
    await tester.ensureVisible(wrongAnswer);
    await tester.tap(wrongAnswer);
    await tester.pump();
    expect(find.text('Not quite. Try another answer.'), findsOneWidget);

    final correctAnswer = find.byKey(const ValueKey('tutorial-answer-1-1'));
    await tester.ensureVisible(correctAnswer);
    await tester.tap(correctAnswer);
    await tester.pump();
    expect(find.text('Correct. You can continue.'), findsOneWidget);

    final enabledNext = tester.widget<FilledButton>(
      find.byKey(const ValueKey('tutorial-next')),
    );
    expect(enabledNext.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('uses readable theme colors in White Mode', (tester) async {
    final catalog = _englishCatalog();
    final lightTheme = themeFor(NodeQlTheme.light);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: TutorialDialog(catalog: catalog, onComplete: () async {}),
      ),
    );

    final body = tester.widget<Text>(
      find.text(
        'NodeQL combines visual blocks with real SQL output. You can '
        'learn query structure, experiment locally and inspect every '
        'generated statement.',
      ),
    );
    final colors = lightTheme.extension<NodeQlWorkbenchColors>()!;

    expect(body.style?.color, lightTheme.colorScheme.onSurfaceVariant);
    expect(
      ThemeData.estimateBrightnessForColor(colors.panel),
      Brightness.light,
    );
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
