import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('attaches and queries a SQLite database without a system CLI', () async {
    final tempDir = await Directory.systemTemp.createTemp('nodeql_sql_runtime');
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}mounted.db';
    final database = sqlite3.open(path);
    database.execute('''
      CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
      INSERT INTO people (name) VALUES ('Ada');
    ''');
    database.close();

    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);

    expect(controller.state.dbPath, path);
    expect(controller.state.schemas, hasLength(1));
    expect(controller.state.schemas.single.name, 'people');
    expect(controller.state.schemas.single.columns, <String>['id', 'name']);

    await controller.executeWithSnapshot(
      "INSERT INTO people (name) VALUES ('Grace');",
    );
    expect(controller.state.lastMessage, 'OK');

    await controller.executeWithSnapshot(
      'SELECT id, name FROM people ORDER BY id;',
    );

    expect(controller.state.lastRows, <Map<String, String>>[
      <String, String>{'id': '1', 'name': 'Ada'},
      <String, String>{'id': '2', 'name': 'Grace'},
    ]);
    expect(controller.state.lastMessage, 'OK');
  });

  test('reports an invalid database without attaching it', () async {
    final tempDir = await Directory.systemTemp.createTemp('nodeql_sql_invalid');
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}invalid.db';
    await File(path).writeAsString('not a SQLite database');

    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);

    expect(controller.state.dbPath, isNull);
    expect(
      controller.state.lastMessage,
      startsWith('Failed to open database:'),
    );
  });

  test('creates a new database in the requested project directory', () async {
    final tempDir = await Directory.systemTemp.createTemp('nodeql_project_db');
    addTearDown(() => tempDir.delete(recursive: true));

    final controller = SqlRuntimeController();
    final path = await controller.createEmptyDatabase(
      preferredName: 'project_data',
      directoryPath: tempDir.path,
    );

    expect(path, '${tempDir.path}${Platform.pathSeparator}project_data.db');
    expect(await File(path).exists(), isTrue);
    expect(controller.state.dbPath, path);
  });

  test('refreshes schema after successful write statements', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nodeql_schema_write',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}runtime.db';
    final database = sqlite3.open(path);
    database.execute('PRAGMA user_version = 1;');
    database.close();

    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);
    expect(controller.state.schemas, isEmpty);

    await controller.executeWithSnapshot(
      'CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);',
    );

    expect(controller.state.lastMessage, 'OK');
    expect(controller.state.schemas, hasLength(1));
    expect(controller.state.schemas.single.name, 'notes');
    expect(controller.state.schemas.single.columns, <String>['id', 'body']);
  });
}
