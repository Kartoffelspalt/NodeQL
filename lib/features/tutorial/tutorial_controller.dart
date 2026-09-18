import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:path_provider/path_provider.dart';

class TutorialState {
  const TutorialState({
    this.loading = true,
    this.completed = false,
    this.lessonProgress = const {},
  });

  final bool loading;
  final bool completed;
  final Map<TutorialKnowledgeMode, TutorialLessonProgress> lessonProgress;

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
          lessonProgress[mode] = TutorialLessonProgress.fromJson(
            rawLessons[mode.name],
          );
        }
      }
      state = TutorialState(
        loading: false,
        completed: decoded is Map && decoded['completed'] == true,
        lessonProgress: lessonProgress,
      );
    } catch (_) {
      state = const TutorialState(loading: false);
    }
  }

  Future<void> complete() async {
    state = TutorialState(
      loading: false,
      completed: true,
      lessonProgress: state.lessonProgress,
    );
    await _persist();
  }

  Future<void> saveLessonProgress(
    TutorialKnowledgeMode mode,
    TutorialLessonProgress progress,
  ) async {
    state = TutorialState(
      loading: false,
      completed: state.completed,
      lessonProgress: {...state.lessonProgress, mode: progress},
    );
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final file = await _storageFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 3,
          'completed': state.completed,
          'updatedAt': DateTime.now().toIso8601String(),
          'lessons': {
            for (final entry in state.lessonProgress.entries)
              entry.key.name: entry.value.toJson(),
          },
        }),
        flush: true,
      );
    } catch (_) {}
  }

  static Future<File> _defaultStorageFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/nodeql_tutorial.json');
  }
}
