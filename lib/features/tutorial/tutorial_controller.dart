import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class TutorialState {
  const TutorialState({this.loading = true, this.completed = false});

  final bool loading;
  final bool completed;
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
      state = TutorialState(
        loading: false,
        completed: decoded is Map && decoded['completed'] == true,
      );
    } catch (_) {
      state = const TutorialState(loading: false);
    }
  }

  Future<void> complete() async {
    state = const TutorialState(loading: false, completed: true);
    try {
      final file = await _storageFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'completed': true,
          'completedAt': DateTime.now().toIso8601String(),
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
