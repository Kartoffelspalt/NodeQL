import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';

void main() {
  test(
    'published workshops replace the retired workspace-practice catalog',
    () {
      expect(tutorialPracticeDefinitions, isEmpty);
      expect(
        workshopTutorialCatalog.tutorials.map((tutorial) => tutorial.id),
        <String>['database-tools', 'plugins'],
      );
      expect(
        workshopTutorialCatalog.tutorials.every(
          (tutorial) => tutorial.hasWorkspacePractice == false,
        ),
        isTrue,
      );
    },
  );

  test('legacy mode aliases still resolve to persisted enum values', () {
    expect(
      TutorialKnowledgeMode.beginner,
      TutorialKnowledgeMode.selectAndSimpleFilters,
    );
    expect(
      TutorialKnowledgeMode.beginnerSyntax,
      TutorialKnowledgeMode.advancedFilters,
    );
  });
}
