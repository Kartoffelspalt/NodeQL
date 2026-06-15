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
