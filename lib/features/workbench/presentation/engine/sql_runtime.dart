import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TableSchema {
  const TableSchema({required this.name, required this.columns});

  final String name;
  final List<String> columns;
}

class SqlRuntimeState {
  const SqlRuntimeState({
    this.dbPath,
    this.schemas = const <TableSchema>[],
    this.lastSql = '',
    this.lastRows = const <Map<String, String>>[],
    this.lastMessage,
  });

  final String? dbPath;
  final List<TableSchema> schemas;
  final String lastSql;
  final List<Map<String, String>> lastRows;
  final String? lastMessage;

  SqlRuntimeState copyWith({
    String? dbPath,
    List<TableSchema>? schemas,
    String? lastSql,
    List<Map<String, String>>? lastRows,
    String? lastMessage,
  }) {
    return SqlRuntimeState(
      dbPath: dbPath ?? this.dbPath,
      schemas: schemas ?? this.schemas,
      lastSql: lastSql ?? this.lastSql,
      lastRows: lastRows ?? this.lastRows,
      lastMessage: lastMessage,
    );
  }
}

final sqlRuntimeProvider =
    StateNotifierProvider<SqlRuntimeController, SqlRuntimeState>(
      (ref) => SqlRuntimeController(),
    );

class SqlRuntimeController extends StateNotifier<SqlRuntimeState> {
  SqlRuntimeController() : super(const SqlRuntimeState());
  static const _securityChannel = MethodChannel('nodeql/security_scope');
  static const int _maxPreviewRows = 500;

  Future<void> pickDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select SQLite database',
      type: FileType.custom,
      allowedExtensions: <String>['db', 'sqlite', 'sqlite3'],
      withData: true,
    );
    final file = result?.files.single;
    final sourcePath = file?.path;
    if (sourcePath == null) return;

    try {
      if (Platform.isMacOS) {
        await _securityChannel.invokeMethod<bool>('start', <String, dynamic>{
          'path': sourcePath,
        });
      }

      final localDbPath = await _copyIntoSandbox(
        sourcePath: sourcePath,
        bytes: file?.bytes,
      );
      await attachDatabasePath(localDbPath);
    } catch (e) {
      state = state.copyWith(
        lastMessage: 'Failed to open DB on macOS sandbox: $e',
      );
    }
  }

  Future<void> attachDatabasePath(String dbPath) async {
    if (!await File(dbPath).exists()) {
      state = state.copyWith(lastMessage: 'Database file not found: $dbPath');
      return;
    }
    final schemas = await _reflectSchema(dbPath);
    state = state.copyWith(
      dbPath: dbPath,
      schemas: schemas,
      lastMessage: schemas.isEmpty
          ? 'DB loaded, but no user tables found.'
          : 'DB loaded: ${schemas.length} table(s)',
    );
  }

  Future<String> createEmptyDatabase({String? preferredName}) async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'nodeql_db'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final base = (preferredName == null || preferredName.trim().isEmpty)
        ? 'project_${DateTime.now().millisecondsSinceEpoch}'
        : preferredName.trim();
    final fileName = base.endsWith('.db') ? base : '$base.db';
    final targetPath = p.join(dbDir.path, fileName);
    final create = await Process.run('/usr/bin/sqlite3', <String>[
      targetPath,
      'PRAGMA user_version = 1;',
    ]);
    if (create.exitCode != 0) {
      throw Exception((create.stderr as String).trim());
    }
    await attachDatabasePath(targetPath);
    return targetPath;
  }

  Future<void> executeWithSnapshot(String sql) async {
    final dbPath = state.dbPath;
    if (dbPath == null) {
      state = state.copyWith(lastMessage: 'No database connected.');
      return;
    }
    final needsSnapshot = _isWriteSql(sql);
    File? snapshot;
    if (needsSnapshot) {
      snapshot = await _createSnapshot(dbPath);
    }
    try {
      final rows = await _runQuery(dbPath, sql);
      final clipped = rows.length > _maxPreviewRows
          ? rows.take(_maxPreviewRows).toList(growable: false)
          : rows;
      final message = rows.length > _maxPreviewRows
          ? 'OK (${rows.length} rows, showing first $_maxPreviewRows)'
          : 'OK';
      state = state.copyWith(
        lastSql: sql,
        lastRows: clipped,
        lastMessage: message,
      );
    } catch (e) {
      if (snapshot != null) {
        await _restoreSnapshot(dbPath, snapshot);
      }
      state = state.copyWith(
        lastSql: sql,
        lastRows: const [],
        lastMessage: 'Rolled back: $e',
      );
    } finally {
      if (snapshot != null && await snapshot.exists()) {
        await snapshot.delete();
      }
    }
  }

  bool _isWriteSql(String sql) {
    final normalized = sql.trimLeft().toUpperCase();
    if (normalized.isEmpty) return false;
    return normalized.startsWith('INSERT') ||
        normalized.startsWith('UPDATE') ||
        normalized.startsWith('DELETE') ||
        normalized.startsWith('CREATE') ||
        normalized.startsWith('ALTER') ||
        normalized.startsWith('DROP') ||
        normalized.startsWith('TRUNCATE') ||
        normalized.startsWith('REPLACE') ||
        normalized.startsWith('GRANT') ||
        normalized.startsWith('REVOKE') ||
        normalized.startsWith('BEGIN') ||
        normalized.startsWith('COMMIT') ||
        normalized.startsWith('ROLLBACK') ||
        normalized.startsWith('PRAGMA');
  }

  void setMessage(String message) {
    state = state.copyWith(lastMessage: message);
  }

  Future<List<TableSchema>> _reflectSchema(String path) async {
    final tablesOut = await Process.run('/usr/bin/sqlite3', <String>[
      path,
      'PRAGMA table_list;',
    ]);
    if (tablesOut.exitCode != 0) return const <TableSchema>[];

    final tableNames = <String>[];
    for (final line in (tablesOut.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('|');
      if (parts.length > 1) {
        final name = parts[1];
        if (!name.startsWith('sqlite_')) tableNames.add(name);
      }
    }

    final schemas = <TableSchema>[];
    for (final table in tableNames) {
      final columnsOut = await Process.run('/usr/bin/sqlite3', <String>[
        path,
        'PRAGMA table_info($table);',
      ]);
      final cols = <String>[];
      if (columnsOut.exitCode == 0) {
        final lines = (columnsOut.stdout as String)
            .split('\n')
            .where((line) => line.trim().isNotEmpty);
        for (final line in lines) {
          final parts = line.split('|');
          if (parts.length > 1) cols.add(parts[1]);
        }
      }
      schemas.add(TableSchema(name: table, columns: cols));
    }

    return schemas;
  }

  Future<File> _createSnapshot(String dbPath) async {
    final snapshot = File('$dbPath.snapshot');
    await File(dbPath).copy(snapshot.path);
    return snapshot;
  }

  Future<void> _restoreSnapshot(String dbPath, File snapshot) async {
    await snapshot.copy(dbPath);
  }

  Future<List<Map<String, String>>> _runQuery(String path, String sql) async {
    final result = await Process.run('/usr/bin/sqlite3', <String>[
      '-header',
      '-json',
      path,
      sql,
    ]);

    if (result.exitCode != 0) {
      throw Exception((result.stderr as String).trim());
    }

    final out = (result.stdout as String).trim();
    if (out.isEmpty) return const <Map<String, String>>[];

    final decoded = jsonDecode(out) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map((row) => row.map((key, value) => MapEntry(key, '${value ?? ''}')))
        .toList();
  }

  Future<String> _copyIntoSandbox({
    required String sourcePath,
    Uint8List? bytes,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'nodeql_db'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final targetPath = p.join(dbDir.path, p.basename(sourcePath));
    final target = File(targetPath);
    if (bytes != null && bytes.isNotEmpty) {
      await target.writeAsBytes(bytes, flush: true);
      return targetPath;
    }

    await File(sourcePath).copy(targetPath);
    return targetPath;
  }
}
