import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

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
      state = state.copyWith(lastMessage: 'Failed to open database: $e');
    }
  }

  Future<void> attachDatabasePath(String dbPath) async {
    if (!await File(dbPath).exists()) {
      state = state.copyWith(lastMessage: 'Database file not found: $dbPath');
      return;
    }
    try {
      final schemas = _reflectSchema(dbPath);
      state = state.copyWith(
        dbPath: dbPath,
        schemas: schemas,
        lastMessage: schemas.isEmpty
            ? 'DB loaded, but no user tables found.'
            : 'DB loaded: ${schemas.length} table(s)',
      );
    } catch (e) {
      state = state.copyWith(lastMessage: 'Failed to open database: $e');
    }
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
    final database = sqlite3.open(targetPath);
    try {
      database.execute('PRAGMA user_version = 1;');
    } finally {
      database.close();
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

  List<TableSchema> _reflectSchema(String path) {
    final database = sqlite3.open(path);
    try {
      final tables = database.select('''
        SELECT name
        FROM sqlite_schema
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        ''');
      return <TableSchema>[
        for (final row in tables)
          TableSchema(
            name: row['name'] as String,
            columns: database
                .select(
                  'PRAGMA table_info(${_quoteIdentifier(row['name'] as String)})',
                )
                .map((column) => column['name'] as String)
                .toList(growable: false),
          ),
      ];
    } finally {
      database.close();
    }
  }

  String _quoteIdentifier(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
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
    final database = sqlite3.open(path);
    final statements = database.prepareMultiple(sql);
    try {
      var rows = const <Map<String, String>>[];
      for (final statement in statements) {
        final result = statement.select();
        if (result.columnNames.isNotEmpty) {
          rows = <Map<String, String>>[
            for (final row in result)
              <String, String>{
                for (final column in result.columnNames)
                  column: '${row[column] ?? ''}',
              },
          ];
        }
      }
      return rows;
    } finally {
      for (final statement in statements) {
        statement.close();
      }
      database.close();
    }
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
