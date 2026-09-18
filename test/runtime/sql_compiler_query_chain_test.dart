import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';

void main() {
  test('compiles SELECT with separate FROM and JOIN clauses', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': 'c.id, o.total', 'table': 'legacy_table'},
    );
    final from = OperatorBlock(
      id: 'from',
      position: Offset.zero,
      operatorType: BlockType.sqlFrom,
      inputs: {'table': 'customers', 'table_alias': 'c'},
    );
    final join = OperatorBlock(
      id: 'join',
      position: Offset.zero,
      operatorType: BlockType.sqlLeftJoin,
      inputs: {
        'table': 'orders',
        'table_alias': 'o',
        'on': 'o.customer_id = c.id',
      },
    );
    final where = MotionBlock(
      id: 'where',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: {'predicate': 'o.total > 100'},
    );

    root.next = select;
    select.next = from;
    from.next = join;
    join.next = where;

    final result = const SqlCompiler().compileWorkspace([root]);

    expect(
      result.sql,
      'SELECT c.id, o.total FROM customers AS c '
      'LEFT JOIN orders AS o ON o.customer_id = c.id '
      'WHERE o.total > 100;',
    );
  });

  test('compiles an integrated SELECT table alias safely', () {
    final root = EventBlock(id: 'run-alias-source', position: Offset.zero);
    root.next = OperatorBlock(
      id: 'select-alias-source',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {
        'columns': '"customer records".id',
        'table': 'customers',
        'table_alias': 'customer records',
      },
    );

    expect(
      const SqlCompiler().compileWorkspace([root]).sql,
      'SELECT "customer records".id FROM customers AS "customer records";',
    );
  });

  test('keeps legacy SELECT table input when no FROM block follows', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    root.next = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': '*', 'table': 'customers'},
    );

    final result = const SqlCompiler().compileWorkspace([root]);

    expect(result.sql, 'SELECT * FROM customers;');
  });

  test('compiles all SQLite storage-class literal nodes', () {
    const cases = <(String, String, String)>[
      ('null', '', 'NULL'),
      ('integer', '42', '42'),
      ('real', '3.5', '3.5'),
      ('text', "O'Reilly", "'O''Reilly'"),
      ('blob', 'CA FE', "X'CAFE'"),
    ];

    for (final entry in cases) {
      final root = EventBlock(id: 'run_${entry.$1}', position: Offset.zero);
      final select = OperatorBlock(
        id: 'select_${entry.$1}',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: {'columns': '*', 'table': '', 'omit_from': true},
      );
      setReporterForInput(
        select,
        'columns',
        OperatorBlock(
          id: 'literal_${entry.$1}',
          position: Offset.zero,
          operatorType: BlockType.sqlText,
          inputs: {'literal_type': entry.$1, 'text': entry.$2},
        ),
      );
      root.next = select;

      final result = const SqlCompiler().compileWorkspace([root]);

      expect(result.sql, 'SELECT ${entry.$3};');
      expect(result.warnings, isEmpty);
    }
  });

  test('compiles SQLite expressions that do not read from a table', () {
    final root = EventBlock(id: 'run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{'columns': '50 / 2, 51 / 2.0', 'table': ''},
      );

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
      'SELECT 50 / 2, 51 / 2.0;',
    );
  });

  test('compiles DISTINCT and puts pagination after the complete query', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{
        'columns': 'county',
        'table': 'executions',
        'distinct': true,
        'limit': 10,
        'offset': 5,
      },
    );
    select.next = MotionBlock(
      id: 'order',
      position: Offset.zero,
      motionType: BlockType.sqlOrderBy,
      inputs: <String, dynamic>{'column': 'county', 'order': 'ASC'},
    );
    root.next = select;

    final result = const SqlCompiler().compileWorkspace(<BlockNode>[root]);

    expect(
      result.sql,
      'SELECT DISTINCT county FROM executions ORDER BY county ASC '
      'LIMIT 10 OFFSET 5;',
    );
    expect(result.warnings, isEmpty);
  });

  test('supports OFFSET without LIMIT and rejects invalid pagination', () {
    final offsetOnly = EventBlock(id: 'offset-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'offset-select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{
          'columns': '*',
          'table': 'executions',
          'offset': 3,
        },
      );
    final invalid = EventBlock(id: 'invalid-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'invalid-select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{
          'columns': '*',
          'table': 'executions',
          'limit': 'many',
        },
      );

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[offsetOnly]).sql,
      'SELECT * FROM executions LIMIT -1 OFFSET 3;',
    );
    final invalidResult = const SqlCompiler().compileWorkspace(<BlockNode>[
      invalid,
    ]);
    expect(invalidResult.sql, 'SELECT * FROM executions;');
    expect(invalidResult.warnings.single, contains('invalid LIMIT'));
  });

  test('restores FROM when a legacy separate flag has no FROM block', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': '*', 'table': 'customers', 'separate_from': true},
    );
    final join = OperatorBlock(
      id: 'join',
      position: Offset.zero,
      operatorType: BlockType.sqlJoin,
      inputs: {
        'join_type': 'LEFT',
        'table': 'orders',
        'on': 'orders.customer_id = customers.id',
      },
    );
    root.next = select;
    select.next = join;

    final result = const SqlCompiler().compileWorkspace([root]);

    expect(
      result.sql,
      'SELECT * FROM customers '
      'LEFT JOIN orders ON orders.customer_id = customers.id;',
    );
  });

  test('generic JOIN compiles types without an ON clause where required', () {
    String compile(String type) {
      final root = EventBlock(id: 'run-$type', position: Offset.zero);
      root.next = OperatorBlock(
        id: 'join-$type',
        position: Offset.zero,
        operatorType: BlockType.sqlJoin,
        inputs: {
          'join_type': type,
          'table': 'orders',
          'on': 'orders.customer_id = customers.id',
        },
      );
      return const SqlCompiler().compileWorkspace([root]).sql;
    }

    expect(compile('INNER'), contains('INNER JOIN orders ON'));
    expect(compile('CROSS'), 'CROSS JOIN orders;');
    expect(compile('NATURAL'), 'NATURAL JOIN orders;');
  });

  test('compiles beginner-friendly structured filters', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': '*', 'table': 'orders', 'separate_from': true},
    );
    final from = OperatorBlock(
      id: 'from',
      position: Offset.zero,
      operatorType: BlockType.sqlFrom,
      inputs: {'table': 'orders'},
    );
    final where = MotionBlock(
      id: 'where',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: {'column': 'status', 'operator': '=', 'value': "'open'"},
    );
    final group = OperatorBlock(
      id: 'group',
      position: Offset.zero,
      operatorType: BlockType.sqlGroupBy,
      inputs: {'column': 'customer_id'},
    );
    final having = OperatorBlock(
      id: 'having',
      position: Offset.zero,
      operatorType: BlockType.sqlHaving,
      inputs: {'column': 'total', 'operator': '>=', 'value': '100'},
    );
    final sum = OperatorBlock(
      id: 'sum',
      position: Offset.zero,
      operatorType: BlockType.sqlSum,
      inputs: {'column': 'ignored_by_having'},
    );
    setReporterForInput(having, 'aggregate', sum);

    root.next = select;
    select.next = from;
    from.next = where;
    where.next = group;
    group.next = having;

    final result = const SqlCompiler().compileWorkspace([root]);

    expect(
      result.sql,
      "SELECT * FROM orders WHERE status = 'open' "
      'GROUP BY customer_id HAVING SUM(total) >= 100;',
    );
  });

  test('compiles grouped filters including null, ranges and lists', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{'columns': '*', 'table': 'executions'},
    );
    select.next = MotionBlock(
      id: 'where',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: <String, dynamic>{
        'match': 'ALL',
        'conditions': <Map<String, dynamic>>[
          <String, dynamic>{
            'column': 'county',
            'operator': 'IN',
            'value': <String>["'Harris'", "'Bexar'"],
          },
          <String, dynamic>{
            'conditions': <Map<String, dynamic>>[
              <String, dynamic>{
                'column': 'ex_age',
                'operator': 'BETWEEN',
                'lower': 18,
                'upper': 25,
              },
              <String, dynamic>{
                'column': 'last_statement',
                'operator': 'IS NULL',
              },
            ],
            'match': 'ANY',
          },
        ],
      },
    );
    root.next = select;

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
      "SELECT * FROM executions WHERE county IN ('Harris', 'Bexar') "
      'AND (ex_age BETWEEN 18 AND 25 OR last_statement IS NULL);',
    );
  });

  test(
    'having aggregate reporter wins over legacy COUNT expression default',
    () {
      final root = EventBlock(id: 'run', position: Offset.zero);
      final having = OperatorBlock(
        id: 'having',
        position: Offset.zero,
        operatorType: BlockType.sqlHaving,
        inputs: {
          'aggregate': 'COUNT',
          'column': 'film_id',
          'expr': 'COUNT(*)',
          'operator': '=',
          'value': '350',
        },
      );
      final sum = OperatorBlock(
        id: 'sum',
        position: Offset.zero,
        operatorType: BlockType.sqlSum,
        inputs: {'column': 'ignored'},
      );
      setReporterForInput(having, 'aggregate', sum);
      root.next = having;

      expect(
        const SqlCompiler().compileWorkspace([root]).sql,
        'HAVING SUM(film_id) = 350;',
      );
    },
  );

  test('compiles structured UPDATE and DELETE conditions', () {
    final updateRoot = EventBlock(id: 'update-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'update',
        position: Offset.zero,
        operatorType: BlockType.sqlUpdate,
        inputs: {
          'table': 'students',
          'column': 'grade',
          'value': "'A'",
          'where_column': 'points',
          'operator': '>=',
          'where_value': '90',
        },
      );
    final deleteRoot = EventBlock(id: 'delete-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'delete',
        position: Offset.zero,
        operatorType: BlockType.sqlDelete,
        inputs: {
          'table': 'students',
          'where_column': 'active',
          'operator': '=',
          'where_value': '0',
        },
      );

    expect(
      const SqlCompiler().compileWorkspace([updateRoot]).sql,
      "UPDATE students SET grade = 'A' WHERE points >= 90;",
    );
    expect(
      const SqlCompiler().compileWorkspace([deleteRoot]).sql,
      'DELETE FROM students WHERE active = 0;',
    );
  });

  test('compiles structured JOIN and conditional expression blocks', () {
    final joinRoot = EventBlock(id: 'join-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'join',
        position: Offset.zero,
        operatorType: BlockType.sqlInnerJoin,
        inputs: {
          'table': 'orders',
          'left_column': 'orders.customer_id',
          'operator': '=',
          'right_column': 'customers.id',
        },
      );
    final caseRoot = EventBlock(id: 'case-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'case',
        position: Offset.zero,
        operatorType: BlockType.sqlCase,
        inputs: {
          'condition_column': 'points',
          'operator': '>=',
          'condition_value': '90',
          'result': "'bestanden'",
          'default': "'ueben'",
        },
      );
    final ifRoot = EventBlock(id: 'if-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'if',
        position: Offset.zero,
        operatorType: BlockType.sqlIf,
        inputs: {
          'condition_column': 'active',
          'operator': '=',
          'condition_value': '1',
          'value': "'ja'",
          'default': "'nein'",
        },
      );

    expect(
      const SqlCompiler().compileWorkspace([joinRoot]).sql,
      'INNER JOIN orders ON orders.customer_id = customers.id;',
    );
    expect(
      const SqlCompiler().compileWorkspace([caseRoot]).sql,
      "CASE WHEN points >= 90 THEN 'bestanden' ELSE 'ueben' END;",
    );
    expect(
      const SqlCompiler().compileWorkspace([ifRoot]).sql,
      "CASE WHEN active = 1 THEN 'ja' ELSE 'nein' END;",
    );
  });

  test('stops compiling when a chain cycle is detected', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': '*'},
    );
    final joinOne = OperatorBlock(
      id: 'join-one',
      position: Offset.zero,
      operatorType: BlockType.sqlLeftJoin,
      inputs: {'table': 'orders', 'on': 'orders.customer_id = customers.id'},
    );
    final joinTwo = OperatorBlock(
      id: 'join-two',
      position: Offset.zero,
      operatorType: BlockType.sqlInnerJoin,
      inputs: {'table': 'payments', 'on': 'payments.order_id = orders.id'},
    );

    root.next = select;
    select.next = joinOne;
    joinOne.next = joinTwo;
    joinTwo.next = joinOne;

    final result = const SqlCompiler().compileWorkspace([root]);

    expect(result.sql, contains('LEFT JOIN orders'));
    expect(result.sql, contains('INNER JOIN payments'));
    expect(result.warnings.single, contains('Cycle detected'));
  });

  test('compiles nested aggregate, column and text reporters', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{
        'columns': '*',
        'table': 'orders',
        'separate_from': true,
      },
    );
    final average = OperatorBlock(
      id: 'average',
      position: Offset.zero,
      operatorType: BlockType.sqlAvg,
      inputs: <String, dynamic>{'expr': 'amount'},
    );
    final column = OperatorBlock(
      id: 'column',
      position: Offset.zero,
      operatorType: BlockType.sqlColumn,
      inputs: <String, dynamic>{'column': 'total'},
    );
    setReporterForInput(average, 'expr', column);
    setReporterForInput(select, 'columns', average);
    select.next = OperatorBlock(
      id: 'from',
      position: Offset.zero,
      operatorType: BlockType.sqlFrom,
      inputs: <String, dynamic>{'table': 'orders'},
    );
    root.next = select;

    final result = const SqlCompiler().compileWorkspace(<BlockNode>[root]);

    expect(result.sql, 'SELECT AVG(total) FROM orders;');

    final text = OperatorBlock(
      id: 'text',
      position: Offset.zero,
      operatorType: BlockType.sqlText,
      inputs: <String, dynamic>{'text': "O'Reilly"},
    );
    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[
        EventBlock(id: 'run-text', position: Offset.zero)
          ..next =
              (OperatorBlock(
                  id: 'select-text',
                  position: Offset.zero,
                  operatorType: BlockType.sqlSelect,
                  inputs: <String, dynamic>{'columns': '*', 'table': 'books'},
                )
                ..inputs[reporterInputsKey] = <String, dynamic>{
                  'columns': text.toJson(),
                }),
      ]).sql,
      "SELECT 'O''Reilly' FROM books;",
    );
  });

  test('compiles SQLite COUNT DISTINCT and safe result aliases', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{'columns': '*', 'table': 'executions'},
    );
    final count = OperatorBlock(
      id: 'count',
      position: Offset.zero,
      operatorType: BlockType.sqlCount,
      inputs: <String, dynamic>{
        'column': 'county',
        'distinct': true,
        'alias': 'county count',
      },
    );
    setReporterForInput(select, 'columns', count);
    root.next = select;

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
      'SELECT COUNT(DISTINCT county) AS "county count" FROM executions;',
    );
  });

  test('aliases arbitrary reporter expressions and quotes unsafe names', () {
    final root = EventBlock(id: 'run-alias', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select-alias',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{'columns': '*', 'table': 'orders'},
    );
    final alias = OperatorBlock(
      id: 'alias',
      position: Offset.zero,
      operatorType: BlockType.sqlAlias,
      inputs: <String, dynamic>{'value': 'total', 'alias': 'average total'},
    );
    final average = OperatorBlock(
      id: 'average',
      position: Offset.zero,
      operatorType: BlockType.sqlAvg,
      inputs: <String, dynamic>{'column': 'total'},
    );
    setReporterForInput(alias, 'value', average);
    setReporterForInput(select, 'columns', alias);
    root.next = select;

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
      'SELECT AVG(total) AS "average total" FROM orders;',
    );
  });

  test('renders visual operations with SQLite syntax', () {
    final root = EventBlock(id: 'run', position: Offset.zero);
    root.next = OperatorBlock(
      id: 'clear',
      position: Offset.zero,
      operatorType: BlockType.sqlTruncate,
      inputs: <String, dynamic>{'table': 'logs'},
    );

    final cleared = const SqlCompiler().compileWorkspace(<BlockNode>[root]);
    expect(cleared.sql, 'DELETE FROM logs;');

    final concatRoot = EventBlock(id: 'concat-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'concat',
        position: Offset.zero,
        operatorType: BlockType.sqlConcat,
        inputs: <String, dynamic>{'a': "'A'", 'b': "'B'"},
      );
    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[concatRoot]).sql,
      "('A' || 'B');",
    );

    final grantRoot = EventBlock(id: 'grant-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'grant',
        position: Offset.zero,
        operatorType: BlockType.sqlGrant,
      );
    final unsupported = const SqlCompiler().compileWorkspace(<BlockNode>[
      grantRoot,
    ]);
    expect(unsupported.sql, isEmpty);
    expect(unsupported.warnings.single, contains('SQLite has no GRANT'));
  });

  test('compiles all requested filter operators and boolean connectors', () {
    final root = EventBlock(id: 'run-filters', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select-filters',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{
        'select_mode': 'DISTINCT',
        'columns': 'name',
        'table': 'people',
      },
    );
    final where = MotionBlock(
      id: 'where-like',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: <String, dynamic>{
        'column': 'name',
        'operator': 'LIKE',
        'value': "'A%'",
      },
    );
    final and = MotionBlock(
      id: 'and-in',
      position: Offset.zero,
      motionType: BlockType.sqlAnd,
      inputs: <String, dynamic>{
        'column': 'id',
        'operator': 'IN',
        'value': '1, 2, 3',
      },
    );
    final or = MotionBlock(
      id: 'or-between',
      position: Offset.zero,
      motionType: BlockType.sqlOr,
      inputs: <String, dynamic>{
        'negation': 'NOT',
        'column': 'age',
        'operator': 'BETWEEN',
        'value': '10 AND 20',
      },
    );
    final andNull = MotionBlock(
      id: 'and-null',
      position: Offset.zero,
      motionType: BlockType.sqlAnd,
      inputs: <String, dynamic>{
        'column': 'deleted_at',
        'operator': 'IS NULL',
        'value': '',
      },
    );
    final limit = OperatorBlock(
      id: 'limit',
      position: Offset.zero,
      operatorType: BlockType.sqlLimit,
      inputs: <String, dynamic>{'count': 5, 'offset': 10},
    );
    root.next = select;
    select.next = where;
    where.next = and;
    and.next = or;
    or.next = andNull;
    andNull.next = limit;

    final result = const SqlCompiler().compileWorkspace(<BlockNode>[root]);

    expect(
      result.sql,
      "SELECT DISTINCT name FROM people WHERE name LIKE 'A%' "
      'AND id IN (1, 2, 3) OR NOT (age BETWEEN 10 AND 20) '
      'AND deleted_at IS NULL LIMIT 5 OFFSET 10;',
    );
    expect(result.warnings, isEmpty);
  });

  test('compiles UNION variants, subqueries, CASE and aggregates', () {
    final unionRoot = EventBlock(id: 'union-run', position: Offset.zero);
    final select = OperatorBlock(
      id: 'union-select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{'columns': 'id', 'table': 'current_people'},
    );
    final union = OperatorBlock(
      id: 'union-all',
      position: Offset.zero,
      operatorType: BlockType.sqlUnion,
      inputs: <String, dynamic>{
        'set_mode': 'ALL',
        'sql': 'SELECT id FROM archived_people;',
      },
    );
    unionRoot.next = select;
    select.next = union;

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[unionRoot]).sql,
      'SELECT id FROM current_people UNION ALL '
      'SELECT id FROM archived_people;',
    );

    final expressionRoot = EventBlock(
      id: 'expression-run',
      position: Offset.zero,
    );
    final expressionSelect = OperatorBlock(
      id: 'expression-select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: <String, dynamic>{'columns': '*', 'table': 'orders'},
    );
    final count = OperatorBlock(
      id: 'count',
      position: Offset.zero,
      operatorType: BlockType.sqlCount,
      inputs: <String, dynamic>{'column': '*'},
    );
    setReporterForInput(expressionSelect, 'columns', count);
    expressionRoot.next = expressionSelect;
    final subqueryWhere = MotionBlock(
      id: 'subquery-filter',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: <String, dynamic>{
        'column': 'ignored',
        'operator': '=',
        'value': 'ignored',
      },
    );
    setReporterForInput(
      subqueryWhere,
      'value',
      OperatorBlock(
        id: 'subquery-in',
        position: Offset.zero,
        operatorType: BlockType.sqlSubqueryIn,
        inputs: <String, dynamic>{
          'column': 'customer_id',
          'sql': 'SELECT id FROM customers WHERE active = 1;',
        },
      ),
    );
    expressionSelect.next = subqueryWhere;

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[expressionRoot]).sql,
      'SELECT COUNT(*) FROM orders WHERE customer_id IN '
      '(SELECT id FROM customers WHERE active = 1);',
    );
  });

  test('compiles INSERT column lists and validates LIMIT values', () {
    final insertRoot = EventBlock(id: 'insert-run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'insert',
        position: Offset.zero,
        operatorType: BlockType.sqlInsert,
        inputs: <String, dynamic>{
          'table': 'people',
          'columns': 'name, age',
          'values': "('Ada', 36),\n('Grace', 37)",
        },
      );
    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[insertRoot]).sql,
      "INSERT INTO people (name, age) VALUES ('Ada', 36),\n"
      "('Grace', 37);",
    );

    final invalidLimit =
        EventBlock(id: 'invalid-limit-run', position: Offset.zero)
          ..next = OperatorBlock(
            id: 'invalid-limit',
            position: Offset.zero,
            operatorType: BlockType.sqlLimit,
            inputs: <String, dynamic>{'count': '-1'},
          );
    final invalidResult = const SqlCompiler().compileWorkspace(<BlockNode>[
      invalidLimit,
    ]);
    expect(invalidResult.sql, isEmpty);
    expect(invalidResult.warnings.single, contains('non-negative integer'));
  });

  test('compiles guarded tables, constraints, indexes and guarded drops', () {
    String compile(BlockNode statement) {
      final root = EventBlock(id: 'run-${statement.id}', position: Offset.zero)
        ..next = statement;
      return const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql;
    }

    final createCustomers = OperatorBlock(
      id: 'create-customers',
      position: Offset.zero,
      operatorType: BlockType.sqlCreateTable,
      inputs: <String, dynamic>{
        'if_not_exists': 'IF NOT EXISTS',
        'table': 'kunden',
        'definition': '''
kunden_id INTEGER PRIMARY KEY AUTOINCREMENT,
vorname TEXT NOT NULL,
status TEXT NOT NULL DEFAULT 'Aktiv',
registriert_seit DATE NOT NULL
''',
      },
    );
    expect(
      compile(createCustomers),
      'CREATE TABLE IF NOT EXISTS kunden ('
      'kunden_id INTEGER PRIMARY KEY AUTOINCREMENT,\n'
      'vorname TEXT NOT NULL,\n'
      "status TEXT NOT NULL DEFAULT 'Aktiv',\n"
      'registriert_seit DATE NOT NULL);',
    );

    final createOrders = OperatorBlock(
      id: 'create-orders',
      position: Offset.zero,
      operatorType: BlockType.sqlCreateTable,
      inputs: <String, dynamic>{
        'table': 'bestellungen',
        'definition': '''
bestell_id INTEGER PRIMARY KEY AUTOINCREMENT,
kunden_id INTEGER NOT NULL,
gesamtbetrag REAL NOT NULL CHECK (gesamtbetrag >= 0),
FOREIGN KEY (kunden_id) REFERENCES kunden(kunden_id) ON DELETE CASCADE
''',
      },
    );
    expect(
      compile(createOrders),
      contains(
        'FOREIGN KEY (kunden_id) REFERENCES kunden(kunden_id) '
        'ON DELETE CASCADE',
      ),
    );

    final createIndex = OperatorBlock(
      id: 'create-index',
      position: Offset.zero,
      operatorType: BlockType.sqlCreateIndex,
      inputs: <String, dynamic>{
        'unique': 'UNIQUE',
        'if_not_exists': 'IF NOT EXISTS',
        'name': 'idx_kunden_status_datum',
        'table': 'kunden',
        'columns': 'status, registriert_seit',
      },
    );
    expect(
      compile(createIndex),
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_kunden_status_datum '
      'ON kunden (status, registriert_seit);',
    );

    final dropTable = OperatorBlock(
      id: 'drop-orders',
      position: Offset.zero,
      operatorType: BlockType.sqlDropTable,
      inputs: <String, dynamic>{
        'if_exists': 'IF EXISTS',
        'table': 'bestellungen',
      },
    );
    expect(compile(dropTable), 'DROP TABLE IF EXISTS bestellungen;');
  });
}
