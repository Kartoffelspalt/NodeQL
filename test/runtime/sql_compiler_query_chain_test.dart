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
      inputs: {'table': 'customers c'},
    );
    final join = OperatorBlock(
      id: 'join',
      position: Offset.zero,
      operatorType: BlockType.sqlLeftJoin,
      inputs: {'table': 'orders o', 'on': 'o.customer_id = c.id'},
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
      'SELECT c.id, o.total FROM customers c '
      'LEFT JOIN orders o ON o.customer_id = c.id '
      'WHERE o.total > 100;',
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
      "IF(active = 1, 'ja', 'nein');",
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
}
