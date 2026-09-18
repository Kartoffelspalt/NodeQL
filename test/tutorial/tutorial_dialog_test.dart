import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
  testWidgets('launches a practical path directly in the real workspace', (
    tester,
  ) async {
    TutorialKnowledgeMode? startedMode;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: TutorialDialog(
          catalog: _englishCatalog(),
          onStartPractice: (mode) async => startedMode = mode,
          onComplete: () async {},
        ),
      ),
    );

    expect(find.text('Choose a practical learning path'), findsOneWidget);
    expect(find.text('About 15 min'), findsOneWidget);
    expect(find.byKey(const ValueKey('tutorial-answer-1-0')), findsNothing);

    final beginner = find.byKey(const ValueKey('tutorial-lesson-beginner'));
    await tester.ensureVisible(beginner);
    await tester.tap(beginner);
    await tester.pumpAndSettle();

    expect(startedMode, TutorialKnowledgeMode.beginner);
    expect(find.byType(TutorialDialog), findsNothing);
  });

  testWidgets('shows mission progress instead of quiz progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: TutorialDialog(
          catalog: _englishCatalog(),
          initialProgress: const {
            TutorialKnowledgeMode.beginnerSyntax: TutorialLessonProgress(
              completedPracticeSteps: {0, 1},
            ),
          },
          onStartPractice: (mode) async {},
          onComplete: () async {},
        ),
      ),
    );

    expect(find.text('2 of 3 workspace missions'), findsOneWidget);
    expect(find.text('Continue in workspace'), findsOneWidget);
  });

  testWidgets('uses readable workshop colors in White Mode', (tester) async {
    final lightTheme = themeFor(NodeQlTheme.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: TutorialDialog(
          catalog: _englishCatalog(),
          onStartPractice: (mode) async {},
          onComplete: () async {},
        ),
      ),
    );

    final body = tester.widget<Text>(
      find.text(
        'Every path opens a real query tab. Drag, connect and configure '
        'NodeQL nodes yourself while the workshop validates the graph and '
        'shows the generated SQLite live — no quiz questions.',
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

  testWidgets('the fallback lesson view contains no answer buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: TutorialDialog(
          catalog: _englishCatalog(),
          startOnOverview: false,
          onComplete: () async {},
        ),
      ),
    );

    expect(
      find.text('Build SQLite without losing sight of SQLite'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tutorial-answer-0-0')), findsNothing);
    final next = tester.widget<FilledButton>(
      find.byKey(const ValueKey('tutorial-next')),
    );
    expect(next.onPressed, isNotNull);
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
