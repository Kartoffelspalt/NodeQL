import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
  testWidgets('published overview reports progress and resume actions', (
    tester,
  ) async {
    const first = AuthoredLearningPath(
      id: 'first',
      title: 'First workshop',
      description: 'Completed.',
      steps: [LearningPathStep(id: 'one', title: 'One', instruction: '')],
    );
    const second = AuthoredLearningPath(
      id: 'second',
      title: 'Second workshop',
      description: 'In progress.',
      steps: [
        LearningPathStep(id: 'two', title: 'Two', instruction: ''),
        LearningPathStep(id: 'three', title: 'Three', instruction: ''),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TutorialDialog(
          catalog: _englishCatalog(),
          authoredPaths: const [first, second],
          workshopProgress: const {
            'first': NodeQlWorkshopProgress(
              completed: true,
              completedStepIds: {'one'},
            ),
            'second': NodeQlWorkshopProgress(
              currentStepId: 'three',
              completedStepIds: {'two'},
            ),
          },
          onStartAuthoredPath: (_) async {},
          onComplete: () async {},
        ),
      ),
    );

    expect(find.text('1 of 1 steps completed'), findsOneWidget);
    expect(find.text('1 of 2 steps completed'), findsOneWidget);
    expect(find.text('Repeat in workspace'), findsOneWidget);
    expect(find.text('Continue in workspace'), findsOneWidget);
    expect(find.text('1 of 2 workshops completed'), findsWidgets);
  });

  testWidgets('starts a published authored workshop from the overview', (
    tester,
  ) async {
    AuthoredLearningPath? started;
    const path = AuthoredLearningPath(
      id: 'published-select',
      title: 'Published SELECT tour',
      description: 'A bundled workshop.',
      steps: [
        LearningPathStep(
          id: 'projection',
          title: 'Projection',
          instruction: 'Inspect SELECT.',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: TutorialDialog(
          catalog: _englishCatalog(),
          authoredPaths: const [path],
          onStartAuthoredPath: (value) async => started = value,
          onComplete: () async {},
        ),
      ),
    );

    final card = find.byKey(
      const ValueKey('authored-learning-path-published-select'),
    );
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(started?.id, 'published-select');
    expect(find.byType(TutorialDialog), findsNothing);
  });

  testWidgets('published workshop overview uses readable light surfaces', (
    tester,
  ) async {
    const path = AuthoredLearningPath(
      id: 'light-workshop',
      title: 'Light workshop',
      description: 'A published workshop rendered with the light theme.',
      steps: [LearningPathStep(id: 'start', title: 'Start', instruction: '')],
    );
    final lightTheme = themeFor(NodeQlTheme.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: TutorialDialog(
          catalog: _englishCatalog(),
          authoredPaths: const [path],
          onComplete: () async {},
        ),
      ),
    );

    expect(find.text('NodeQL Workshops'), findsOneWidget);
    final colors = lightTheme.extension<NodeQlWorkbenchColors>()!;
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
