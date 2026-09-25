enum TutorialKnowledgeMode {
  selectAndSimpleFilters,
  dataTypes,
  advancedFilters,
  sortingAndWhere,
  complexQueries,
  dataManipulation,
  schemaObjects,
  transactions,
  databaseTools,
  plugins;

  /// Compatibility aliases for progress files and integrations created before
  /// the curriculum was split into topic-based workshops.
  @Deprecated('Use selectAndSimpleFilters')
  static const beginner = TutorialKnowledgeMode.selectAndSimpleFilters;

  @Deprecated('Use advancedFilters')
  static const beginnerSyntax = TutorialKnowledgeMode.advancedFilters;

  @Deprecated('Use complexQueries')
  static const intermediate = TutorialKnowledgeMode.complexQueries;

  @Deprecated('Use complexQueries')
  static const expert = TutorialKnowledgeMode.complexQueries;
}

enum TutorialWorkshopArea { sqlite, nodeQl }

extension TutorialKnowledgeModeMetadata on TutorialKnowledgeMode {
  TutorialWorkshopArea get area => switch (this) {
    TutorialKnowledgeMode.databaseTools ||
    TutorialKnowledgeMode.plugins => TutorialWorkshopArea.nodeQl,
    _ => TutorialWorkshopArea.sqlite,
  };

  bool get hasWorkspacePractice => area == TutorialWorkshopArea.sqlite;
}

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
