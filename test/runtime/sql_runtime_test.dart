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

    final result = await controller.executeWithSnapshot(
      'CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);',
    );

    expect(result.success, isTrue);
    expect(result.changedDatabase, isTrue);
    expect(controller.state.lastMessage, 'OK');
    expect(controller.state.schemas, hasLength(1));
    expect(controller.state.schemas.single.name, 'notes');
    expect(controller.state.schemas.single.columns, <String>['id', 'body']);
  });

  test(
    'detects writes from parsed SQLite instead of the first text token',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nodeql_parsed_write',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}${Platform.pathSeparator}runtime.db';
      sqlite3.open(path).close();

      final controller = SqlRuntimeController();
      await controller.attachDatabasePath(path);
      final result = await controller.executeWithSnapshot('''
      -- This leading comment used to hide the write from snapshot detection.
      CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
    ''');

      expect(result.success, isTrue);
      expect(result.changedDatabase, isTrue);
      expect(controller.state.schemas.single.name, 'tasks');
    },
  );

  test('executes dependent SQLite statements from one editor run', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nodeql_multi_statement',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}runtime.db';
    sqlite3.open(path).close();

    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);
    final result = await controller.executeWithSnapshot('''
      CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
      INSERT INTO tasks (title) VALUES ('First; task');
      SELECT id, title FROM tasks;
    ''');

    expect(result.success, isTrue);
    expect(result.rows, <Map<String, String>>[
      <String, String>{'id': '1', 'title': 'First; task'},
    ]);
    expect(controller.state.schemas.single.name, 'tasks');
  });

  test(
    'enforces foreign keys and ON DELETE CASCADE on every execution',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nodeql_foreign_keys',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}${Platform.pathSeparator}relations.db';
      sqlite3.open(path).close();

      final controller = SqlRuntimeController();
      await controller.attachDatabasePath(path);
      final setup = await controller.executeWithSnapshot('''
      CREATE TABLE kunden (
        kunden_id INTEGER PRIMARY KEY AUTOINCREMENT,
        vorname TEXT NOT NULL
      );
      CREATE TABLE bestellungen (
        bestell_id INTEGER PRIMARY KEY AUTOINCREMENT,
        kunden_id INTEGER NOT NULL,
        gesamtbetrag REAL NOT NULL CHECK (gesamtbetrag >= 0),
        FOREIGN KEY (kunden_id) REFERENCES kunden(kunden_id)
          ON DELETE CASCADE
      );
      CREATE INDEX idx_bestellungen_kunden
        ON bestellungen(kunden_id);
      INSERT INTO kunden (vorname) VALUES ('Max');
      INSERT INTO bestellungen (kunden_id, gesamtbetrag)
        VALUES (1, 600.00), (1, 500.00);
    ''');
      expect(setup.success, isTrue);

      final deletion = await controller.executeWithSnapshot(
        'DELETE FROM kunden WHERE kunden_id = 1;',
      );
      expect(deletion.success, isTrue);

      await controller.executeWithSnapshot(
        'SELECT COUNT(*) AS count FROM bestellungen;',
      );
      expect(controller.state.lastRows.single['count'], '0');
    },
  );

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

  test(
    'executes replace, upsert, trigger and view nodes as one visual program',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nodeql_extended_program',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}${Platform.pathSeparator}extended.db';
      sqlite3.open(path).close();

      OperatorBlock operation(
        String id,
        BlockType type,
        Map<String, dynamic> inputs,
      ) => OperatorBlock(
        id: id,
        position: Offset.zero,
        operatorType: type,
        inputs: inputs,
      );

      final createItems = operation('create-items', BlockType.sqlCreateTable, {
        'table': 'items',
        'definition': 'id INTEGER PRIMARY KEY, value TEXT NOT NULL',
      });
      final createAudit = operation('create-audit', BlockType.sqlCreateTable, {
        'table': 'audit',
        'definition': 'item_id INTEGER NOT NULL',
      });
      final trigger = operation('trigger', BlockType.sqlCreateTrigger, {
        'name': 'audit_item',
        'timing': 'AFTER',
        'event': 'INSERT',
        'table': 'items',
        'body': 'INSERT INTO audit (item_id) VALUES (NEW.id)',
      });
      final insert = operation('insert', BlockType.sqlInsert, {
        'table': 'items',
        'columns': 'id, value',
        'values': "(1, 'first')",
      });
      final replace = operation('replace', BlockType.sqlInsertOrReplace, {
        'table': 'items',
        'columns': 'id, value',
        'values': "(1, 'replaced')",
      });
      final upsert = operation('upsert', BlockType.sqlUpsert, {
        'table': 'items',
        'columns': 'id, value',
        'values': "(1, 'updated')",
        'conflict_columns': 'id',
        'assignments': 'value = excluded.value',
      });
      final view = operation('view', BlockType.sqlCreateView, {
        'name': 'item_view',
        'sql': 'SELECT id, value FROM items',
      });
      final select = operation('select', BlockType.sqlSelect, {
        'columns': 'id, value',
        'table': 'item_view',
      });
      createItems.next = createAudit;
      createAudit.next = trigger;
      trigger.next = insert;
      insert.next = replace;
      replace.next = upsert;
      upsert.next = view;
      view.next = select;
      final root = EventBlock(id: 'run-extended', position: Offset.zero)
        ..next = createItems;

      final controller = SqlRuntimeController();
      await controller.attachDatabasePath(path);
      await controller.executeProgram(
        const SqliteProgramCompiler().compileWorkspace(<BlockNode>[
          root,
        ]).program,
      );

      expect(controller.state.lastMessage, 'OK');
      expect(controller.state.lastRows, <Map<String, String>>[
        <String, String>{'id': '1', 'value': 'updated'},
      ]);
      await controller.executeWithSnapshot(
        'SELECT COUNT(*) AS count FROM audit;',
      );
      expect(controller.state.lastRows.single['count'], '2');
    },
  );

  test('snapshot TCL restores to a named point inside one chain', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nodeql_snapshot_tcl',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}snapshot.db';
    final database = sqlite3.open(path);
    database.execute(
      'CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL);',
    );
    database.close();

    OperatorBlock operation(
      String id,
      BlockType type, [
      Map<String, dynamic> inputs = const <String, dynamic>{},
    ]) => OperatorBlock(
      id: id,
      position: Offset.zero,
      operatorType: type,
      inputs: inputs,
    );

    final begin = operation('begin', BlockType.sqlBeginTransaction, {
      'behavior': 'IMMEDIATE',
    });
    final kept = operation('kept', BlockType.sqlInsert, {
      'table': 'notes',
      'columns': 'body',
      'values': "('kept')",
    });
    final savepoint = operation('savepoint', BlockType.sqlSavepoint, {
      'name': 'before_optional_change',
    });
    final discarded = operation('discarded', BlockType.sqlInsert, {
      'table': 'notes',
      'columns': 'body',
      'values': "('discarded')",
    });
    final restore = operation('restore', BlockType.sqlRollbackToSavepoint, {
      'name': 'before_optional_change',
    });
    final release = operation('release', BlockType.sqlReleaseSavepoint, {
      'name': 'before_optional_change',
    });
    final commit = operation('commit', BlockType.sqlCommit);
    final select = operation('select', BlockType.sqlSelect, {
      'columns': 'body',
      'table': 'notes',
    });
    begin.next = kept;
    kept.next = savepoint;
    savepoint.next = discarded;
    discarded.next = restore;
    restore.next = release;
    release.next = commit;

    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);
    await controller.executeProgram(
      const SqliteProgramCompiler().compileWorkspace(<BlockNode>[
        EventBlock(id: 'run-snapshot', position: Offset.zero)..next = begin,
      ]).program,
    );
    expect(controller.state.lastMessage, 'OK');

    await controller.executeProgram(
      const SqliteProgramCompiler().compileWorkspace(<BlockNode>[
        EventBlock(id: 'run-select', position: Offset.zero)..next = select,
      ]).program,
    );
    expect(controller.state.lastRows, <Map<String, String>>[
      <String, String>{'body': 'kept'},
    ]);
  });

  test('executes PRAGMA, WITH, VALUES, EXPLAIN, ATTACH and FTS5 nodes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nodeql_sqlite_tools',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final path = '${tempDir.path}${Platform.pathSeparator}main.db';
    final attachedPath = '${tempDir.path}${Platform.pathSeparator}archive.db';
    final database = sqlite3.open(path);
    database.execute(
      'CREATE TABLE items (id INTEGER PRIMARY KEY, value TEXT NOT NULL);',
    );
    database.close();
    final archive = sqlite3.open(attachedPath);
    archive.execute(
      "CREATE TABLE archived (id INTEGER PRIMARY KEY, value TEXT); "
      "INSERT INTO archived VALUES (7, 'stored');",
    );
    archive.close();

    OperatorBlock operation(
      String id,
      BlockType type, [
      Map<String, dynamic> inputs = const <String, dynamic>{},
    ]) => OperatorBlock(
      id: id,
      position: Offset.zero,
      operatorType: type,
      inputs: inputs,
    );
    SqliteProgram program(BlockNode first) =>
        const SqliteProgramCompiler().compileWorkspace(<BlockNode>[
          EventBlock(id: 'run-${first.id}', position: Offset.zero)
            ..next = first,
        ]).program;

    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(path);

    await controller.executeProgram(
      program(
        operation('pragma', BlockType.sqlPragma, {
          'pragma': 'table_info',
          'value': 'items',
        }),
      ),
    );
    expect(controller.state.lastRows.map((row) => row['name']), <String?>[
      'id',
      'value',
    ]);

    await controller.executeProgram(
      program(
        operation('values', BlockType.sqlValues, {
          'values': "(1, 'A'), (2, 'B')",
        }),
      ),
    );
    expect(controller.state.lastRows, hasLength(2));
    expect(controller.state.lastRows.first.values, <String>['1', 'A']);

    await controller.executeProgram(
      program(
        operation('with', BlockType.sqlWith, {
          'name': 'numbers',
          'columns': 'n',
          'sql': 'VALUES (1), (2)',
          'statement': 'SELECT SUM(n) AS total FROM numbers',
        }),
      ),
    );
    expect(controller.state.lastRows.single['total'], '3');

    final explain = operation('explain', BlockType.sqlExplain, {
      'mode': 'EXPLAIN QUERY PLAN',
    });
    explain.next = operation('select-items', BlockType.sqlSelect, {
      'columns': '*',
      'table': 'items',
    });
    await controller.executeProgram(program(explain));
    expect(controller.state.lastRows, isNotEmpty);
    expect(controller.state.lastRows.first, contains('detail'));

    final attach = operation('attach', BlockType.sqlAttachDatabase, {
      'path': attachedPath,
      'schema': 'archive',
    });
    final attachedSelect = operation('attached-select', BlockType.sqlSelect, {
      'columns': 'value',
      'table': 'archive.archived',
    });
    attach.next = attachedSelect;
    await controller.executeProgram(program(attach));
    expect(controller.state.lastRows.single['value'], 'stored');

    await controller.executeProgram(
      program(
        operation('fts', BlockType.sqlCreateVirtualTable, {
          'table': 'search_docs',
          'module': 'FTS5',
          'arguments': 'title, body',
        }),
      ),
    );
    expect(controller.state.lastMessage, 'OK');
    await controller.executeWithSnapshot(
      "INSERT INTO search_docs (title, body) VALUES ('SQLite', 'Node search');",
    );
    await controller.executeWithSnapshot(
      "SELECT title FROM search_docs WHERE search_docs MATCH 'sqlite';",
    );
    expect(controller.state.lastRows.single['title'], 'SQLite');
  });
}
