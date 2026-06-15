import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum SqlAbstractionMode { advanced, simple }

final sqlModeProvider =
    StateNotifierProvider<SqlModeController, SqlAbstractionMode>(
      (_) => SqlModeController(),
    );

class SqlModeController extends StateNotifier<SqlAbstractionMode> {
  SqlModeController({Future<File> Function()? storageFile})
    : _storageFile = storageFile ?? _defaultStorageFile,
      super(SqlAbstractionMode.advanced) {
    initialize();
  }

  final Future<File> Function() _storageFile;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _restore();

  Future<void> setMode(SqlAbstractionMode mode) async {
    await initialize();
    if (state == mode) return;
    state = mode;
    try {
      final file = await _storageFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'mode': mode.name,
          'savedAt': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final storedName = '${decoded['mode'] ?? ''}';
      final storedModes = SqlAbstractionMode.values.where(
        (mode) => mode.name == storedName,
      );
      if (storedModes.isNotEmpty) {
        state = storedModes.first;
      }
    } catch (_) {}
  }

  static Future<File> _defaultStorageFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/nodeql_sql_mode.json');
  }
}
