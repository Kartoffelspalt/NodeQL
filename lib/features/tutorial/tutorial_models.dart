enum TutorialKnowledgeMode { beginner, beginnerSyntax, intermediate, expert }

class TutorialLessonProgress {
  const TutorialLessonProgress({
    this.currentStep = 0,
    this.solvedSteps = const <int>{},
    this.completedPracticeSteps = const <int>{},
    this.completed = false,
    this.practiceCompleted = false,
  });

  final int currentStep;
  final Set<int> solvedSteps;
  final Set<int> completedPracticeSteps;
  final bool completed;
  final bool practiceCompleted;

  TutorialLessonProgress copyWith({
    int? currentStep,
    Set<int>? solvedSteps,
    Set<int>? completedPracticeSteps,
    bool? completed,
    bool? practiceCompleted,
  }) {
    return TutorialLessonProgress(
      currentStep: currentStep ?? this.currentStep,
      solvedSteps: solvedSteps ?? this.solvedSteps,
      completedPracticeSteps:
          completedPracticeSteps ?? this.completedPracticeSteps,
      completed: completed ?? this.completed,
      practiceCompleted: practiceCompleted ?? this.practiceCompleted,
    );
  }

  Map<String, Object> toJson() {
    final solved = solvedSteps.toList()..sort();
    final practiceSteps = completedPracticeSteps.toList()..sort();
    return {
      'currentStep': currentStep,
      'solvedSteps': solved,
      'completedPracticeSteps': practiceSteps,
      'completed': completed,
      'practiceCompleted': practiceCompleted,
    };
  }

  factory TutorialLessonProgress.fromJson(Object? value) {
    if (value is! Map) return const TutorialLessonProgress();
    final rawStep = value['currentStep'];
    final rawSolved = value['solvedSteps'];
    final rawPracticeSteps = value['completedPracticeSteps'];
    return TutorialLessonProgress(
      currentStep: rawStep is int && rawStep >= 0 ? rawStep : 0,
      solvedSteps: rawSolved is List
          ? rawSolved.whereType<int>().where((step) => step >= 0).toSet()
          : const <int>{},
      completedPracticeSteps: rawPracticeSteps is List
          ? rawPracticeSteps.whereType<int>().where((step) => step >= 0).toSet()
          : const <int>{},
      completed: value['completed'] == true,
      practiceCompleted: value['practiceCompleted'] == true,
    );
  }
}
