import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/learning/sql_exercise_evaluator.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class TableSchema {
  const TableSchema({required this.name, required this.columns});

  final String name;
  final List<String> columns;
}

class SqlExecutionResult {
  const SqlExecutionResult({
    required this.success,
    required this.message,
    this.rows = const <Map<String, String>>[],
    this.truncated = false,
    this.changedDatabase = false,
  });

  final bool success;
  final String message;
  final List<Map<String, String>> rows;
  final bool truncated;
  final bool changedDatabase;
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

  Future<String> createEmptyDatabase({
    String? preferredName,
    String? directoryPath,
  }) async {
    final dbDir = Directory(
      directoryPath ??
          p.join((await getApplicationSupportDirectory()).path, 'nodeql_db'),
    );
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final base = (preferredName == null || preferredName.trim().isEmpty)
        ? 'project_${DateTime.now().millisecondsSinceEpoch}'
        : preferredName.trim();
    final fileName = base.endsWith('.db') ? base : '$base.db';
    final targetPath = await _uniqueDatabasePath(dbDir.path, fileName);
    final database = sqlite3.open(targetPath);
    try {
      database.execute('PRAGMA user_version = 1;');
    } finally {
      database.close();
    }
    await attachDatabasePath(targetPath);
    return targetPath;
  }

  Future<SqlExecutionResult> executeWithSnapshot(String sql) async {
    final dbPath = state.dbPath;
    if (dbPath == null) {
      const message = 'No database connected.';
      state = state.copyWith(lastMessage: message);
      return const SqlExecutionResult(success: false, message: message);
    }
    File? snapshot;
    var changesDatabase = false;
    try {
      changesDatabase = await Isolate.run(
        () => _containsWriteStatements(dbPath, sql),
      );
      if (changesDatabase) {
        snapshot = await _createSnapshot(dbPath);
      }
      final result = await Isolate.run(
        () => _runQuery(dbPath, sql, _maxPreviewRows),
      );
      final rows = result.rows;
      final message = result.truncated
          ? 'OK (showing first $_maxPreviewRows rows)'
          : 'OK';
      state = state.copyWith(
        lastSql: sql,
        lastRows: rows,
        lastMessage: message,
        schemas: changesDatabase ? _reflectSchema(dbPath) : null,
      );
      return SqlExecutionResult(
        success: true,
        message: message,
        rows: rows,
        truncated: result.truncated,
        changedDatabase: changesDatabase,
      );
    } catch (e) {
      if (snapshot != null) {
        await _restoreSnapshot(dbPath, snapshot);
      }
      final message = 'Rolled back: $e';
      state = state.copyWith(
        lastSql: sql,
        lastRows: const [],
        lastMessage: message,
      );
      return SqlExecutionResult(
        success: false,
        message: message,
        changedDatabase: changesDatabase,
      );
    } finally {
      if (snapshot != null && await snapshot.exists()) {
        await snapshot.delete();
      }
    }
  }

  /// Runs a visual SQLite program. SQLite text is rendered only here, at the
  /// database adapter boundary, rather than being assembled by workspace UI.
  Future<void> executeProgram(SqliteProgram program) async {
    final rendered = const SqliteDialectRenderer().render(program);
    if (rendered.sql.trim().isEmpty) {
      state = state.copyWith(lastMessage: 'No executable SQLite operation.');
      return;
    }
    await executeWithSnapshot(rendered.sql);
  }

  /// Checks a visual query against a SQLite reference query without allowing
  /// either query to mutate the connected project database.
  Future<SqlExerciseEvaluation> evaluateProgram(
    SqliteProgram program, {
    required String solutionSql,
    bool orderSensitive = false,
    bool compareColumnNames = false,
  }) {
    final dbPath = state.dbPath;
    if (dbPath == null) {
      return Future<SqlExerciseEvaluation>.value(
        const SqlExerciseEvaluation(
          verdict: SqlExerciseVerdict.databaseUnavailable,
          message: 'No database connected.',
        ),
      );
    }
    final submission = const SqliteDialectRenderer().render(program).sql;
    return const SqlExerciseEvaluator().evaluate(
      databasePath: dbPath,
      submissionSql: submission,
      solutionSql: solutionSql,
      orderSensitive: orderSensitive,
      compareColumnNames: compareColumnNames,
    );
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

  static _QueryResult _runQuery(String path, String sql, int maxRows) {
    final database = sqlite3.open(path);
    var statements = <PreparedStatement>[];
    try {
      // SQLite foreign-key enforcement is connection-local and disabled by
      // default. Every NodeQL execution uses a fresh worker connection, so it
      // must be enabled before preparing or running user statements.
      database.execute('PRAGMA foreign_keys = ON;');
      try {
        statements = database.prepareMultiple(sql);
      } on Object {
        // sqlite3_exec compiles and executes each statement in sequence. This
        // supports scripts where a later statement uses a table created by an
        // earlier statement in the same editor run.
        database.execute(sql);
        for (final candidate in _splitSqlStatements(sql).reversed) {
          try {
            final statement = database.prepare(candidate);
            statements.add(statement);
            if (!statement.isReadOnly) {
              return const _QueryResult(rows: [], truncated: false);
            }
            return _readPreparedStatements(<PreparedStatement>[
              statement,
            ], maxRows);
          } on Object {
            // A trailing comment or an internal CREATE TRIGGER fragment is
            // not a standalone statement. Continue to the preceding chunk.
          }
        }
        return const _QueryResult(rows: [], truncated: false);
      }
      return _readPreparedStatements(statements, maxRows);
    } finally {
      for (final statement in statements) {
        statement.close();
      }
      database.close();
    }
  }

  static _QueryResult _readPreparedStatements(
    Iterable<PreparedStatement> statements,
    int maxRows,
  ) {
    var rows = const <Map<String, String>>[];
    var truncated = false;
    for (final statement in statements) {
      final cursor = statement.selectCursor();
      final statementRows = <Map<String, String>>[];
      List<String>? previewColumns;
      while (cursor.moveNext()) {
        if (cursor.columnNames.isEmpty) continue;
        if (statementRows.length >= maxRows) {
          truncated = true;
          break;
        }
        previewColumns ??= _previewColumnNames(
          cursor.columnNames,
          cursor.tableNames,
        );
        final row = cursor.current;
        statementRows.add(<String, String>{
          for (var index = 0; index < previewColumns.length; index++)
            previewColumns[index]: '${row.columnAt(index) ?? ''}',
        });
      }
      if (cursor.columnNames.isNotEmpty) {
        rows = statementRows;
      }
    }
    return _QueryResult(rows: rows, truncated: truncated);
  }

  static bool _containsWriteStatements(String path, String sql) {
    final database = sqlite3.open(path);
    var statements = <PreparedStatement>[];
    try {
      statements = database.prepareMultiple(sql);
      return statements.any((statement) => !statement.isReadOnly);
    } on Object {
      // Dependent multi-statement scripts may not be preparable before their
      // first schema change runs. Treat them as writes so rollback protection
      // is in place before attempting execution.
      return true;
    } finally {
      for (final statement in statements) {
        statement.close();
      }
      database.close();
    }
  }

  static List<String> _splitSqlStatements(String sql) {
    const normal = 0;
    const singleQuote = 1;
    const doubleQuote = 2;
    const backtickQuote = 3;
    const bracketQuote = 4;
    const lineComment = 5;
    const blockComment = 6;
    var state = normal;
    var start = 0;
    final statements = <String>[];

    for (var index = 0; index < sql.length; index++) {
      final char = sql[index];
      final next = index + 1 < sql.length ? sql[index + 1] : '';
      switch (state) {
        case normal:
          if (char == "'") {
            state = singleQuote;
          } else if (char == '"') {
            state = doubleQuote;
          } else if (char == '`') {
            state = backtickQuote;
          } else if (char == '[') {
            state = bracketQuote;
          } else if (char == '-' && next == '-') {
            state = lineComment;
            index++;
          } else if (char == '/' && next == '*') {
            state = blockComment;
            index++;
          } else if (char == ';') {
            final statement = sql.substring(start, index).trim();
            if (statement.isNotEmpty) statements.add(statement);
            start = index + 1;
          }
        case singleQuote:
          if (char == "'" && next == "'") {
            index++;
          } else if (char == "'") {
            state = normal;
          }
        case doubleQuote:
          if (char == '"' && next == '"') {
            index++;
          } else if (char == '"') {
            state = normal;
          }
        case backtickQuote:
          if (char == '`' && next == '`') {
            index++;
          } else if (char == '`') {
            state = normal;
          }
        case bracketQuote:
          if (char == ']') state = normal;
        case lineComment:
          if (char == '\n' || char == '\r') state = normal;
        case blockComment:
          if (char == '*' && next == '/') {
            state = normal;
            index++;
          }
      }
    }

    final trailing = sql.substring(start).trim();
    if (trailing.isNotEmpty) statements.add(trailing);
    return statements;
  }

  static List<String> _previewColumnNames(
    List<String> columnNames,
    List<String?>? tableNames,
  ) {
    final duplicateNames = <String>{};
    final nameCounts = <String, int>{};
    for (final name in columnNames) {
      final count = (nameCounts[name] ?? 0) + 1;
      nameCounts[name] = count;
      if (count > 1) duplicateNames.add(name);
    }

    final result = <String>[];
    final usedLabels = <String, int>{};
    for (var index = 0; index < columnNames.length; index++) {
      final name = columnNames[index];
      final table = tableNames != null && index < tableNames.length
          ? tableNames[index]
          : null;
      final baseLabel = duplicateNames.contains(name) && table != null
          ? '$table.$name'
          : name;
      final occurrence = (usedLabels[baseLabel] ?? 0) + 1;
      usedLabels[baseLabel] = occurrence;
      result.add(occurrence == 1 ? baseLabel : '$baseLabel ($occurrence)');
    }
    return result;
  }

  Future<String> _uniqueDatabasePath(String directory, String fileName) async {
    final extension = p.extension(fileName);
    final baseName = p.basenameWithoutExtension(fileName);
    var candidate = p.join(directory, fileName);
    var suffix = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '$baseName-$suffix$extension');
      suffix += 1;
    }
    return candidate;
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

class _QueryResult {
  const _QueryResult({required this.rows, required this.truncated});

  final List<Map<String, String>> rows;
  final bool truncated;
}
