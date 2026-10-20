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

/// Progress for an official, bundled workshop, keyed by stable content IDs.
class NodeQlWorkshopProgress {
  const NodeQlWorkshopProgress({
    this.currentStepId = '',
    this.currentNodeRef = '',
    this.nodeInserted = false,
    this.completedStepIds = const <String>{},
    this.completed = false,
    this.workspaceJson,
    this.nodeIds = const <String, String>{},
    this.abstractionMode = 'simple',
  });

  final String currentStepId;
  final String currentNodeRef;
  final bool nodeInserted;
  final Set<String> completedStepIds;
  final bool completed;
  final String? workspaceJson;
  final Map<String, String> nodeIds;
  final String abstractionMode;

  bool get started => currentStepId.isNotEmpty;

  int completedCount(Iterable<String> stepIds) =>
      stepIds.where(completedStepIds.contains).length;

  bool isCompleteFor(Iterable<String> stepIds) =>
      completed && stepIds.every(completedStepIds.contains);

  Map<String, dynamic> toJson() => {
    'currentStepId': currentStepId,
    'currentNodeRef': currentNodeRef,
    'nodeInserted': nodeInserted,
    'completedStepIds': completedStepIds.toList()..sort(),
    'completed': completed,
    'workspaceJson': workspaceJson,
    'nodeIds': nodeIds,
    'abstractionMode': abstractionMode,
  };

  factory NodeQlWorkshopProgress.fromJson(Object? value) {
    if (value is! Map) return const NodeQlWorkshopProgress();
    return NodeQlWorkshopProgress(
      currentStepId: value['currentStepId'] is String
          ? value['currentStepId'] as String
          : '',
      currentNodeRef: value['currentNodeRef'] is String
          ? value['currentNodeRef'] as String
          : '',
      nodeInserted: value['nodeInserted'] == true,
      completedStepIds: value['completedStepIds'] is List
          ? (value['completedStepIds'] as List).whereType<String>().toSet()
          : const <String>{},
      completed: value['completed'] == true,
      workspaceJson: value['workspaceJson'] is String
          ? value['workspaceJson'] as String
          : null,
      nodeIds: {
        if (value['nodeIds'] is Map)
          for (final entry in (value['nodeIds'] as Map).entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      abstractionMode: value['abstractionMode'] == 'advanced'
          ? 'advanced'
          : 'simple',
    );
  }
}

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
