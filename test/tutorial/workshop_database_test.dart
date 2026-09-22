import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';
import 'package:nodeql/features/tutorial/workshop_database.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('workshop has real related rows and is removed with its session', () {
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
      expect(
        database.select('''
              SELECT name FROM customers
              INTERSECT SELECT name FROM archived_customers
            ''').single['name'],
        'Ada',
      );
    } finally {
      database.close();
    }

    sample.dispose();
    expect(File(sample.path).existsSync(), isFalse);
  });

  test(
    'workshop runtime executes SELECT but protects the sample data',
    () async {
      final sample = WorkshopDatabase.create();
      addTearDown(sample.dispose);
      final runtime = SqlRuntimeController(
        initialState: sample.initialState,
        readOnly: true,
      );
      addTearDown(runtime.dispose);

      final result = await runtime.executeWithSnapshot('''
      SELECT customers.name, COUNT(*) AS orders_count
      FROM customers
      INNER JOIN orders ON customers.id = orders.customer_id
      GROUP BY customers.name
      ORDER BY customers.name
    ''');
      expect(result.success, isTrue);
      expect(result.rows, isNotEmpty);
      expect(result.rows.first['name'], 'Ada');

      final denied = await runtime.executeWithSnapshot(
        "DELETE FROM customers WHERE name = 'Ada';",
      );
      expect(denied.success, isFalse);
      expect(denied.message, contains('read-only'));
      final database = sqlite3.open(sample.path);
      try {
        expect(
          database.select("SELECT id FROM customers WHERE name = 'Ada'"),
          hasLength(1),
        );
      } finally {
        database.close();
      }
    },
  );

  test('final projects compile, execute and pass their graph checks', () async {
    final sample = WorkshopDatabase.create();
    addTearDown(sample.dispose);
    final runtime = SqlRuntimeController(
      initialState: sample.initialState,
      readOnly: true,
    );
    addTearDown(runtime.dispose);

    final syntax = _chain([
      _operator('syntax_select', BlockType.sqlSelect, {
        'columns': 'name',
        'table': 'customers',
        'separate_from': true,
      }),
      _operator('syntax_from', BlockType.sqlFrom, {'table': 'customers'}),
      _motion('syntax_where', BlockType.sqlWhere, {
        'column': 'active',
        'operator': '=',
        'value': '1',
      }),
      _motion('syntax_order', BlockType.sqlOrderBy, {
        'column': 'name',
        'order': 'ASC',
      }),
      _operator('syntax_limit', BlockType.sqlLimit, {'count': '5'}),
    ]);

    final countSelect = _operator('report_select', BlockType.sqlSelect, {
      'columns': '',
      'table': 'customers',
      'separate_from': true,
    });
    setReporterForInput(
      countSelect,
      'columns',
      _operator('report_count', BlockType.sqlCount, {'column': '*'}),
    );
    final report = _chain([
      countSelect,
      _operator('report_from', BlockType.sqlFrom, {'table': 'customers'}),
      _operator('report_join', BlockType.sqlInnerJoin, {
        'table': 'orders',
        'on': 'customers.id = orders.customer_id',
      }),
      _operator('report_group', BlockType.sqlGroupBy, {
        'column': 'customers.name',
      }),
      _operator('report_having', BlockType.sqlHaving, {
        'predicate': 'COUNT(*) > 0',
      }),
      _motion('report_order', BlockType.sqlOrderBy, {
        'column': 'customers.name',
        'order': 'ASC',
      }),
      _operator('report_limit', BlockType.sqlLimit, {'count': '5'}),
    ]);

    final sets = _chain([
      _operator('sets_select', BlockType.sqlSelect, {
        'columns': 'id, name',
        'table': 'customers',
      }),
      _operator('sets_union', BlockType.sqlUnion, {
        'sql': 'SELECT id, name FROM archived_customers',
      }),
      _motion('sets_order', BlockType.sqlOrderBy, {
        'column': 'name',
        'order': 'ASC',
      }),
      _operator('sets_limit', BlockType.sqlLimit, {'count': '10'}),
    ]);

    for (final (mode, root) in <(TutorialKnowledgeMode, EventBlock)>[
      (TutorialKnowledgeMode.beginnerSyntax, syntax),
      (TutorialKnowledgeMode.intermediate, report),
      (TutorialKnowledgeMode.expert, sets),
    ]) {
      final definition = tutorialPracticeDefinitions[mode]!;
      final sql = const SqlCompiler().compileWorkspace([root]).sql;
      final result = await runtime.executeWithSnapshot(sql);
      expect(result.success, isTrue, reason: '$mode: $sql — ${result.message}');
      expect(result.rows, isNotEmpty, reason: '$mode: $sql');
      expect(
        definition
            .evaluate(
              [root],
              definition.stepCount - 1,
              currentSql: sql,
              executedSql: runtime.state.lastSql,
              executionSucceeded:
                  runtime.state.lastMessage?.startsWith('OK') == true,
            )
            .complete,
        isTrue,
        reason: '$mode: $sql',
      );
    }
  });

  test('advanced set and reporter examples return the expected rows', () async {
    final sample = WorkshopDatabase.create();
    addTearDown(sample.dispose);
    final runtime = SqlRuntimeController(
      initialState: sample.initialState,
      readOnly: true,
    );
    addTearDown(runtime.dispose);
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.expert]!;

    EventBlock setQuery(
      String suffix,
      BlockType type,
      Map<String, dynamic> inputs,
    ) => _chain([
      _operator('select_$suffix', BlockType.sqlSelect, {
        'columns': 'id, name',
        'table': 'customers',
      }),
      _operator('set_$suffix', type, inputs),
    ]);

    final intersect = setQuery('intersect', BlockType.sqlIntersect, {
      'sql': 'SELECT id, name FROM archived_customers',
    });
    final except = setQuery('except', BlockType.sqlExcept, {
      'sql': 'SELECT id, name FROM archived_customers',
    });
    final unionAll = setQuery('all', BlockType.sqlUnion, {
      'sql': 'SELECT id, name FROM archived_customers',
      'all': true,
    });
    final distinct = _chain([
      _operator('select_distinct', BlockType.sqlSelect, {
        'columns': 'country',
        'table': 'customers',
        'select_mode': 'DISTINCT',
      }),
    ]);
    final aliasSelect = _operator('select_alias', BlockType.sqlSelect, {
      'columns': '',
      'table': 'customers',
      'select_mode': 'DISTINCT',
    });
    final alias = _operator('alias', BlockType.sqlAlias, {
      'value': '',
      'alias': 'region',
    });
    setReporterForInput(
      alias,
      'value',
      _operator('country_column', BlockType.sqlColumn, {'column': 'country'}),
    );
    setReporterForInput(aliasSelect, 'columns', alias);
    final aliased = _chain([aliasSelect]);

    for (final (root, step, rows) in <(EventBlock, int, int)>[
      (intersect, 3, 1),
      (except, 4, 7),
      (unionAll, 5, 12),
      (distinct, 6, 3),
      (aliased, 7, 3),
    ]) {
      final sql = const SqlCompiler().compileWorkspace([root]).sql;
      final result = await runtime.executeWithSnapshot(sql);
      expect(result.success, isTrue, reason: sql);
      expect(result.rows, hasLength(rows), reason: sql);
      expect(definition.evaluate([root], step).complete, isTrue, reason: sql);
    }
  });
}

EventBlock _chain(List<BlockNode> nodes) {
  final event = EventBlock(
    id: 'event_${nodes.first.id}',
    position: Offset.zero,
  );
  BlockNode previous = event;
  for (final node in nodes) {
    previous.next = node;
    previous = node;
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

MotionBlock _motion(String id, BlockType type, Map<String, dynamic> inputs) =>
    MotionBlock(
      id: id,
      position: Offset.zero,
      motionType: type,
      inputs: inputs,
    );
