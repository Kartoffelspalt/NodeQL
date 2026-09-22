import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/tutorial_controller.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';

void main() {
  test(
    'does not lose a mission saved while startup is still reading',
    () async {
      final temp = await Directory.systemTemp.createTemp('nodeql_tutorial_');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/tutorial.json');
      await file.writeAsString('{"completed":false}');

      final gate = Completer<void>();
      final controller = TutorialController(
        storageFile: () async {
          await gate.future;
          return file;
        },
      );

      final save = controller.saveLessonProgress(
        TutorialKnowledgeMode.beginner,
        const TutorialLessonProgress(completedPracticeSteps: {0}),
      );
      gate.complete();
      await save;

      expect(
        controller.state
            .progressFor(TutorialKnowledgeMode.beginner)
            .completedPracticeSteps,
        {0},
      );
      final restored = TutorialController(storageFile: () async => file);
      await restored.initialize();
      expect(
        restored.state
            .progressFor(TutorialKnowledgeMode.beginner)
            .completedPracticeSteps,
        {0},
      );
    },
  );

  test('persists and restores tutorial completion', () async {
    final temp = await Directory.systemTemp.createTemp('nodeql_tutorial_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/tutorial.json');

    final controller = TutorialController(storageFile: () async => file);
    await controller.initialize();

    expect(controller.state.loading, isFalse);
    expect(controller.state.completed, isFalse);

    await controller.complete();
    await controller.saveLessonProgress(
      TutorialKnowledgeMode.beginner,
      const TutorialLessonProgress(
        currentStep: 4,
        solvedSteps: {1, 2, 3},
        completedPracticeSteps: {0, 1, 2},
        completed: true,
        practiceCompleted: true,
      ),
    );

    expect(controller.state.completed, isTrue);
    expect(await file.readAsString(), contains('"completed":true'));

    final restored = TutorialController(storageFile: () async => file);
    await restored.initialize();

    expect(restored.state.loading, isFalse);
    expect(restored.state.completed, isTrue);
    expect(restored.state.completedLessonCount, 1);
    expect(
      restored.state.progressFor(TutorialKnowledgeMode.beginner).currentStep,
      4,
    );
    expect(
      restored.state.progressFor(TutorialKnowledgeMode.beginner).solvedSteps,
      {1, 2, 3},
    );
    expect(
      restored.state
          .progressFor(TutorialKnowledgeMode.beginner)
          .practiceCompleted,
      isTrue,
    );
    expect(
      restored.state
          .progressFor(TutorialKnowledgeMode.beginner)
          .completedPracticeSteps,
      {0, 1, 2},
    );
  });

  test('restores the legacy completion-only format', () async {
    final temp = await Directory.systemTemp.createTemp('nodeql_tutorial_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/tutorial.json');
    await file.writeAsString('{"completed":true}');

    final controller = TutorialController(storageFile: () async => file);
    await controller.initialize();

    expect(controller.state.completed, isTrue);
    expect(controller.state.lessonProgress, isEmpty);
  });

  test('storage failures never block tutorial startup', () async {
    final controller = TutorialController(
      storageFile: () async => throw const FileSystemException('unavailable'),
    );

    await controller.initialize();

    expect(controller.state.loading, isFalse);
    expect(controller.state.completed, isFalse);
  });
}
