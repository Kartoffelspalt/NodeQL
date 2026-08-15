import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/learning/sql_exercise_evaluator.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'executes a visual SQLite program instead of accepting node SQLite text',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nodeql_sql_program',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final trigger = EventBlock(id: 'run', position: Offset.zero);
      trigger.next = OperatorBlock(
        id: 'create-notes',
        position: Offset.zero,
        operatorType: BlockType.sqlCreateTable,
        inputs: <String, dynamic>{
          'table': 'notes',
          'definition': 'id INTEGER PRIMARY KEY, body TEXT',
        },
      );
      final program = const SqliteProgramCompiler().compileWorkspace(
        <BlockNode>[trigger],
      ).program;
      final controller = SqlRuntimeController();

      await controller.createEmptyDatabase(directoryPath: tempDir.path);
      await controller.executeProgram(program);

      expect(controller.state.lastMessage, 'OK');
      expect(controller.state.schemas.single.name, 'notes');
    },
  );

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

  test(
    'preserves duplicate JOIN columns and their positional values',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nodeql_duplicate_columns',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}${Platform.pathSeparator}joined.db';
      final database = sqlite3.open(path);
      database.execute('''
      CREATE TABLE Customers (
        id INTEGER PRIMARY KEY,
        company_name TEXT NOT NULL
      );
      CREATE TABLE Orders (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER NOT NULL
      );
      INSERT INTO Customers (id, company_name)
        VALUES (1, 'Vertex'), (2, 'Prime');
      INSERT INTO Orders (id, customer_id)
        VALUES (778, 1), (14010, 1), (1257, 2);
    ''');
      database.close();

      final controller = SqlRuntimeController();
      await controller.attachDatabasePath(path);
      await controller.executeWithSnapshot('''
      SELECT * FROM Customers
      INNER JOIN Orders ON Customers.id = Orders.customer_id
      ORDER BY Customers.id ASC;
    ''');

      final rows = controller.state.lastRows;
      expect(rows, hasLength(3));
      expect(rows.first.length, 4);
      expect(rows.first.values, <String>['1', 'Vertex', '778', '1']);
      expect(rows[1].values, <String>['1', 'Vertex', '14010', '1']);
      expect(rows[2].values, <String>['2', 'Prime', '1257', '2']);
      expect(rows.first.keys.elementAt(0), isNot(rows.first.keys.elementAt(2)));
    },
  );

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

  test('evaluates a visual program against a SQLite solution', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nodeql_sql_evaluation',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}exercise.db';
    final database = sqlite3.open(path);
    database.execute('''
      CREATE TABLE executions (county TEXT NOT NULL);
      INSERT INTO executions (county) VALUES ('Harris'), ('Bexar'), ('Harris');
    ''');
    database.close();

    final trigger = EventBlock(id: 'run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'query',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{
          'columns': 'county',
          'table': 'executions',
          'distinct': true,
        },
      );
    final program = const SqliteProgramCompiler().compileWorkspace(<BlockNode>[
      trigger,
    ]).program;
    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);

    final result = await controller.evaluateProgram(
      program,
      solutionSql: 'SELECT county FROM executions GROUP BY county',
    );

    expect(result.verdict, SqlExerciseVerdict.correct);
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

  test(
    'limits large SELECT previews while executing on a worker isolate',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nodeql_large_preview',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}${Platform.pathSeparator}large.db';
      final database = sqlite3.open(path);
      database.execute('''
      CREATE TABLE a (id INTEGER PRIMARY KEY);
      CREATE TABLE b (id INTEGER PRIMARY KEY);
      CREATE TABLE c (id INTEGER PRIMARY KEY);
      WITH RECURSIVE seq(x) AS (
        SELECT 1
        UNION ALL
        SELECT x + 1 FROM seq WHERE x < 12
      )
      INSERT INTO a (id) SELECT x FROM seq;
      INSERT INTO b (id) SELECT id FROM a;
      INSERT INTO c (id) SELECT id FROM a;
    ''');
      database.close();

      final controller = SqlRuntimeController();
      await controller.attachDatabasePath(path);
      await controller.executeWithSnapshot(
        'SELECT a.id AS a_id, b.id AS b_id, c.id AS c_id '
        'FROM a INNER JOIN b ON 1 = 1 INNER JOIN c ON 1 = 1;',
      );

      expect(controller.state.lastRows, hasLength(500));
      expect(controller.state.lastMessage, 'OK (showing first 500 rows)');
    },
  );
}
