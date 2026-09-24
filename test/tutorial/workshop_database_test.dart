import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';
import 'package:nodeql/features/tutorial/workshop_database.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('workshop has related rows and is removed with its session', () {
    final sample = WorkshopDatabase.create();
    final database = sqlite3.open(sample.path);
    try {
      expect(sample.initialState.schemas, hasLength(3));
      expect(
        database.select('SELECT COUNT(*) AS n FROM customers').single['n'],
        8,
      );
      expect(
        database.select('SELECT COUNT(*) AS n FROM orders').single['n'],
        10,
      );
    } finally {
      database.close();
    }

    sample.dispose();
    expect(File(sample.path).existsSync(), isFalse);
  });

  test('isolated workshop runtime supports safe write exercises', () async {
    final sample = WorkshopDatabase.create();
    addTearDown(sample.dispose);
    final runtime = SqlRuntimeController(initialState: sample.initialState);
    addTearDown(runtime.dispose);

    final result = await runtime.executeWithSnapshot('''
      INSERT INTO archived_customers (id, name) VALUES (999, 'Workshop');
      UPDATE archived_customers SET name = 'NodeQL' WHERE id = 999;
      DELETE FROM archived_customers WHERE id = 999;
    ''');
    expect(result.success, isTrue);
    expect(result.changedDatabase, isTrue);

    final database = sqlite3.open(sample.path);
    try {
      expect(
        database.select('SELECT id FROM archived_customers WHERE id = 999'),
        isEmpty,
      );
    } finally {
      database.close();
    }
  });

  test('DML final project executes and passes graph checks', () async {
    final sample = WorkshopDatabase.create();
    addTearDown(sample.dispose);
    final runtime = SqlRuntimeController(initialState: sample.initialState);
    addTearDown(runtime.dispose);
    final root = _chain([
      _operator('insert', BlockType.sqlInsert, {
        'table': 'archived_customers',
        'columns': 'id, name',
        'values': "(999, 'Workshop')",
      }),
      _operator('update', BlockType.sqlUpdate, {
        'table': 'archived_customers',
        'column': 'name',
        'value': "'NodeQL Workshop'",
        'where_column': 'id',
        'operator': '=',
        'where_value': '999',
      }),
      _operator('delete', BlockType.sqlDelete, {
        'table': 'archived_customers',
        'where_column': 'id',
        'operator': '=',
        'where_value': '999',
      }),
    ]);
    await _expectFinalProject(
      runtime,
      TutorialKnowledgeMode.dataManipulation,
      root,
    );
  });

  test(
    'schema final project executes and refreshes reflected schema',
    () async {
      final sample = WorkshopDatabase.create();
      addTearDown(sample.dispose);
      final runtime = SqlRuntimeController(initialState: sample.initialState);
      addTearDown(runtime.dispose);
      final root = _chain([
        _operator('table', BlockType.sqlCreateTable, {
          'if_not_exists': 'IF NOT EXISTS',
          'table': 'workshop_notes',
          'definition': 'id INTEGER PRIMARY KEY, note TEXT NOT NULL',
        }),
        _operator('index', BlockType.sqlCreateIndex, {
          'if_not_exists': 'IF NOT EXISTS',
          'name': 'idx_workshop_notes_note',
          'table': 'workshop_notes',
          'columns': 'note',
        }),
        _operator('view', BlockType.sqlCreateView, {
          'if_not_exists': 'IF NOT EXISTS',
          'name': 'active_customers',
          'sql': 'SELECT id, name FROM customers WHERE active = 1',
        }),
      ]);
      await _expectFinalProject(
        runtime,
        TutorialKnowledgeMode.schemaObjects,
        root,
      );
      expect(
        runtime.state.schemas.map((schema) => schema.name),
        contains('workshop_notes'),
      );
    },
  );

  test(
    'transaction recovery-point project executes without keeping update',
    () async {
      final sample = WorkshopDatabase.create();
      addTearDown(sample.dispose);
      final runtime = SqlRuntimeController(initialState: sample.initialState);
      addTearDown(runtime.dispose);
      final root = _chain([
        _operator('begin', BlockType.sqlBeginTransaction, {
          'behavior': 'DEFERRED',
        }),
        _operator('savepoint', BlockType.sqlSavepoint, {
          'name': 'workshop_point',
        }),
        _operator('update', BlockType.sqlUpdate, {
          'table': 'customers',
          'column': 'city',
          'value': "'Temporary City'",
          'where_column': 'id',
          'operator': '=',
          'where_value': '1',
        }),
        _operator('rollback', BlockType.sqlRollbackToSavepoint, {
          'name': 'workshop_point',
        }),
        _operator('release', BlockType.sqlReleaseSavepoint, {
          'name': 'workshop_point',
        }),
        _operator('commit', BlockType.sqlCommit, const {}),
      ]);
      await _expectFinalProject(
        runtime,
        TutorialKnowledgeMode.transactions,
        root,
      );

      final database = sqlite3.open(sample.path);
      try {
        expect(
          database
              .select('SELECT city FROM customers WHERE id = 1')
              .single['city'],
          'Berlin',
        );
      } finally {
        database.close();
      }
    },
  );
}

Future<void> _expectFinalProject(
  SqlRuntimeController runtime,
  TutorialKnowledgeMode mode,
  EventBlock root,
) async {
  final definition = tutorialPracticeDefinitions[mode]!;
  final sql = const SqlCompiler().compileWorkspace([root]).sql;
  final execution = await runtime.executeWithSnapshot(sql);
  expect(
    execution.success,
    isTrue,
    reason: '$mode: $sql — ${execution.message}',
  );
  expect(
    definition
        .evaluate(
          [root],
          definition.stepCount - 1,
          currentSql: sql,
          executedSql: runtime.state.lastSql,
          executionSucceeded: execution.success,
        )
        .complete,
    isTrue,
    reason: '$mode: $sql',
  );
}

EventBlock _chain(List<BlockNode> nodes) {
  final event = EventBlock(
    id: 'event_${nodes.first.id}',
    position: Offset.zero,
  );
  event.next = nodes.first;
  for (var index = 0; index < nodes.length - 1; index++) {
    nodes[index].next = nodes[index + 1];
  }
  return event;
}

OperatorBlock _operator(
  String id,
  BlockType type,
  Map<String, dynamic> inputs,
) => OperatorBlock(
  id: id,
  position: Offset.zero,
  operatorType: type,
  inputs: inputs,
);
