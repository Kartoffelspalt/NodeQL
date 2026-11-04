import 'dart:convert';
import 'package:nodeql/core/platform/storage.dart';

import 'package:flutter_riverpod/legacy.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';

class TutorialState {
  const TutorialState({
    this.loading = true,
    this.completed = false,
    this.lessonProgress = const {},
    this.workshopProgress = const {},
  });

  final bool loading;
  final bool completed;
  final Map<TutorialKnowledgeMode, TutorialLessonProgress> lessonProgress;
  final Map<String, NodeQlWorkshopProgress> workshopProgress;

  NodeQlWorkshopProgress workshopProgressFor(String id) =>
      workshopProgress[id] ?? const NodeQlWorkshopProgress();

  TutorialLessonProgress progressFor(TutorialKnowledgeMode mode) =>
      lessonProgress[mode] ?? const TutorialLessonProgress();

  int get completedLessonCount => lessonProgress.values
      .where((progress) => progress.practiceCompleted)
      .length;
}

final tutorialControllerProvider =
    StateNotifierProvider<TutorialController, TutorialState>(
      (_) => TutorialController(),
    );

class TutorialController extends StateNotifier<TutorialState> {
  TutorialController({Future<File> Function()? storageFile})
    : _storageFile = storageFile ?? _defaultStorageFile,
      super(const TutorialState()) {
    initialize();
  }

  final Future<File> Function() _storageFile;
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future<void>.value();

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        state = const TutorialState(loading: false);
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      final rawLessons = decoded is Map ? decoded['lessons'] : null;
      final lessonProgress = <TutorialKnowledgeMode, TutorialLessonProgress>{};
      if (rawLessons is Map) {
        for (final mode in TutorialKnowledgeMode.values) {
          final current = rawLessons[mode.name];
          final legacyKey = switch (mode) {
            TutorialKnowledgeMode.selectAndSimpleFilters => 'beginner',
            TutorialKnowledgeMode.advancedFilters => 'beginnerSyntax',
            TutorialKnowledgeMode.complexQueries => 'intermediate',
            _ => null,
          };
          lessonProgress[mode] = TutorialLessonProgress.fromJson(
            current ?? (legacyKey == null ? null : rawLessons[legacyKey]),
          );
        }
      }
      state = TutorialState(
        loading: false,
        completed: decoded is Map && decoded['completed'] == true,
        lessonProgress: lessonProgress,
        workshopProgress: {
          if (decoded is Map && decoded['workshops'] is Map)
            for (final entry in (decoded['workshops'] as Map).entries)
              if (entry.key is String)
                entry.key as String: NodeQlWorkshopProgress.fromJson(
                  entry.value,
                ),
        },
      );
    } catch (_) {
      state = const TutorialState(loading: false);
    }
  }

  Future<void> complete() async {
    if (state.loading) await initialize();
    if (!mounted) return;
    state = TutorialState(
      loading: false,
      completed: true,
      lessonProgress: state.lessonProgress,
      workshopProgress: state.workshopProgress,
    );
    await _persist();
  }

  Future<void> saveLessonProgress(
    TutorialKnowledgeMode mode,
    TutorialLessonProgress progress,
  ) async {
    if (state.loading) await initialize();
    if (!mounted) return;
    state = TutorialState(
      loading: false,
      completed: state.completed,
      lessonProgress: {...state.lessonProgress, mode: progress},
      workshopProgress: state.workshopProgress,
    );
    await _persist();
  }

  Future<void> saveWorkshopProgress(
    String id,
    NodeQlWorkshopProgress progress,
  ) async {
    if (state.loading) await initialize();
    if (!mounted) return;
    state = TutorialState(
      loading: false,
      completed: state.completed,
      lessonProgress: state.lessonProgress,
      workshopProgress: {...state.workshopProgress, id: progress},
    );
    await _persist();
  }

  Future<void> _persist() {
    final payload = jsonEncode({
      'schemaVersion': 5,
      'completed': state.completed,
      'updatedAt': DateTime.now().toIso8601String(),
      'lessons': {
        for (final entry in state.lessonProgress.entries)
          entry.key.name: entry.value.toJson(),
      },
      'workshops': {
        for (final entry in state.workshopProgress.entries)
          entry.key: entry.value.toJson(),
      },
    });
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final file = await _storageFile();
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
      } catch (_) {}
    });
    return _pendingWrite;
  }

  static Future<File> _defaultStorageFile() async {
    final support = await getApplicationSupportDirectory();
    return fileAt('${support.path}/nodeql_tutorial.json');
  }
}
