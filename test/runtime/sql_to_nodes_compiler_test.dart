import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_to_nodes_compiler.dart';

void main() {
  group('SqlToNodesCompiler', () {
    test('imports a SELECT chain with clauses and joins', () {
      final result = SqlToNodesCompiler().compile('''
        SELECT DISTINCT c.id, c.name
        FROM customers AS c
        LEFT JOIN orders AS o ON o.customer_id = c.id
        WHERE c.active = 1
        GROUP BY c.id, c.name
        HAVING COUNT(o.id) > 0
        ORDER BY c.name DESC
        LIMIT 25 OFFSET 5;
      ''');

      expect(result.warnings, isEmpty);
      expect(result.roots, hasLength(1));
      final root = result.roots.single;
      expect(root.type, BlockType.eventGreenFlag);
      expect(root.next?.type, BlockType.sqlSelect);
      expect(root.next?.next?.type, BlockType.sqlFrom);
      expect(root.next?.next?.next?.type, BlockType.sqlJoin);
      expect(root.next?.inputs, containsPair('separate_from', isTrue));
      expect(root.next?.next?.inputs, containsPair('table', 'customers'));
      expect(root.next?.next?.inputs, containsPair('table_alias', 'c'));
      expect(root.next?.next?.next?.inputs, containsPair('table', 'orders'));
      expect(root.next?.next?.next?.inputs, containsPair('table_alias', 'o'));
      expect(
        root.next?.next?.next?.inputs,
        containsPair('left_column', 'o.customer_id'),
      );
      expect(
        root.next?.next?.next?.inputs,
        containsPair('right_column', 'c.id'),
      );
      final where = root.next?.next?.next?.next;
      expect(where?.inputs, containsPair('column', 'c.active'));
      expect(where?.inputs, containsPair('operator', '='));
      expect(where?.inputs, containsPair('value', '1'));
      final having = where?.next?.next;
      expect(having?.inputs, containsPair('aggregate', 'COUNT'));
      expect(having?.inputs, containsPair('column', 'o.id'));
      final order = having?.next;
      expect(order?.inputs, containsPair('column', 'c.name'));
      expect(order?.inputs, containsPair('order', 'DESC'));
      expect(
        const SqlCompiler().compileWorkspace(result.roots).sql,
        'SELECT DISTINCT c.id, c.name FROM customers AS c '
        'LEFT JOIN orders AS o ON o.customer_id = c.id '
        'WHERE c.active = 1 GROUP BY c.id, c.name '
        'HAVING COUNT(o.id) > 0 ORDER BY c.name DESC LIMIT 25 OFFSET 5;',
      );
    });

    test('imports common mutation and schema statements as separate chains', () {
      final result = SqlToNodesCompiler().compile('''
        INSERT INTO tasks (title, done) VALUES ('Ship it', 0);
        UPDATE tasks SET done = 1 WHERE id = 4;
        DELETE FROM tasks WHERE done = 1;
        CREATE TABLE IF NOT EXISTS archive (id INTEGER PRIMARY KEY, title TEXT);
        DROP TABLE IF EXISTS archive;
      ''');

      expect(result.warnings, isEmpty);
      expect(result.importedStatementCount, 5);
      expect(
        const SqlCompiler().compileWorkspace(result.roots).sql,
        "INSERT INTO tasks (title, done) VALUES ('Ship it', 0);\n"
        'UPDATE tasks SET done = 1 WHERE id = 4;\n'
        'DELETE FROM tasks WHERE done = 1;\n'
        'CREATE TABLE IF NOT EXISTS archive (id INTEGER PRIMARY KEY, title TEXT);\n'
        'DROP TABLE IF EXISTS archive;',
      );
    });

    test(
      'keeps unsupported SQL out of the visual workspace with a warning',
      () {
        final result = SqlToNodesCompiler().compile(
          'SELECT * FROM tasks; PRAGMA cache_size = 2000;',
        );

        expect(result.importedStatementCount, 1);
        expect(result.warnings, hasLength(1));
        expect(result.warnings.single, contains('PRAGMA'));
      },
    );

    test('does not split semicolons inside quoted literals', () {
      final result = SqlToNodesCompiler().compile(
        "INSERT INTO notes (body) VALUES ('one; two');",
      );

      expect(result.warnings, isEmpty);
      expect(
        const SqlCompiler().compileWorkspace(result.roots).sql,
        "INSERT INTO notes (body) VALUES ('one; two');",
      );
    });

    test('keeps complex imported conditions visibly editable as raw SQL', () {
      final result = SqlToNodesCompiler().compile('''
        UPDATE tasks SET done = 1
        WHERE (priority > 3 OR pinned = 1) AND archived_at IS NULL;
        SELECT * FROM tasks
        INNER JOIN users ON tasks.owner_id = users.id OR tasks.reviewer_id = users.id
        ORDER BY priority DESC, created_at ASC;
        ALTER TABLE tasks RENAME CONSTRAINT unsupported_extension;
      ''');

      expect(result.warnings, isEmpty);
      final update = result.roots[0].next!;
      expect(update.inputs, containsPair('imported_raw_where', isTrue));
      expect(
        update.inputs,
        containsPair(
          'predicate',
          '(priority > 3 OR pinned = 1) AND archived_at IS NULL',
        ),
      );

      final join = result.roots[1].next!.next!.next!;
      expect(join.inputs, containsPair('imported_raw_on', isTrue));
      final order = join.next!;
      expect(order.inputs, containsPair('imported_raw_order', isTrue));
      expect(
        order.inputs,
        containsPair('expr', 'priority DESC, created_at ASC'),
      );

      final alter = result.roots[2].next!;
      expect(alter.inputs, containsPair('imported_raw_alter', isTrue));
      expect(
        alter.inputs,
        containsPair('alter', 'RENAME CONSTRAINT unsupported_extension'),
      );
      expect(
        const SqlCompiler().compileWorkspace(result.roots).sql,
        'UPDATE tasks SET done = 1 WHERE (priority > 3 OR pinned = 1) '
        'AND archived_at IS NULL;\n'
        'SELECT * FROM tasks INNER JOIN users ON tasks.owner_id = users.id '
        'OR tasks.reviewer_id = users.id ORDER BY priority DESC, created_at ASC;\n'
        'ALTER TABLE tasks RENAME CONSTRAINT unsupported_extension;',
      );
    });
  });
}
