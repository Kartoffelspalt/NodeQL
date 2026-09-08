import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_backwards_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';

void main() {
  group('SQL source map', () {
    test('keeps the generated range for every node in a query chain', () {
      final root = EventBlock(id: 'run', position: Offset.zero);
      final select = OperatorBlock(
        id: 'select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{'columns': '*', 'table': 'kunden'},
      );
      final where = MotionBlock(
        id: 'where',
        position: Offset.zero,
        motionType: BlockType.sqlWhere,
        inputs: <String, dynamic>{'predicate': 'status = 1'},
      );
      root.next = select;
      select.next = where;

      final compilation = const SqlCompiler().compileWorkspace(<BlockNode>[
        root,
      ]);

      expect(compilation.sql, 'SELECT * FROM kunden WHERE status = 1;');
      expect(
        compilation.sourceMap
            .where((span) => span.nodeId == 'select')
            .map((span) => span.textIn(compilation.sql)),
        contains('SELECT * FROM kunden'),
      );
      expect(
        compilation.sourceMap
            .singleWhere((span) => span.nodeId == 'where')
            .textIn(compilation.sql),
        'WHERE status = 1',
      );
    });
  });

  group('SqlBackwardsCompiler', () {
    const backwards = SqlBackwardsCompiler();

    test('projects a missing table onto its source node', () {
      final compilation = _compileSingle(
        OperatorBlock(
          id: 'select-missing-table',
          position: Offset.zero,
          operatorType: BlockType.sqlSelect,
          inputs: <String, dynamic>{
            'columns': '*',
            'table': 'unbekannte_tabelle',
          },
        ),
      );

      final projection = backwards.project(
        compilation: compilation,
        sqliteError:
            'Rolled back: SqliteException(1): no such table: unbekannte_tabelle',
      );

      expect(projection?.nodeId, 'select-missing-table');
      expect(projection?.kind, SqlNodeErrorKind.missingTable);
      expect(
        projection?.sourceSpan?.textIn(compilation.sql),
        contains('unbekannte_tabelle'),
      );
    });

    test('projects a missing column onto the clause using it', () {
      final root = EventBlock(id: 'run-column', position: Offset.zero);
      final select = OperatorBlock(
        id: 'select-column',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{'columns': 'id', 'table': 'kunden'},
      );
      final where = MotionBlock(
        id: 'where-column',
        position: Offset.zero,
        motionType: BlockType.sqlWhere,
        inputs: <String, dynamic>{'predicate': 'unbekannt = 4'},
      );
      root.next = select;
      select.next = where;
      final compilation = const SqlCompiler().compileWorkspace(<BlockNode>[
        root,
      ]);

      final projection = backwards.project(
        compilation: compilation,
        sqliteError: 'SqliteException(1): no such column: unbekannt',
      );

      expect(projection?.nodeId, 'where-column');
      expect(projection?.kind, SqlNodeErrorKind.missingColumn);
    });

    test('uses the SQLite near-token to find malformed raw SQL', () {
      final root = EventBlock(id: 'run-syntax', position: Offset.zero);
      final select = OperatorBlock(
        id: 'select-syntax',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{'columns': '1', 'table': ''},
      );
      final union = OperatorBlock(
        id: 'union-syntax',
        position: Offset.zero,
        operatorType: BlockType.sqlUnion,
        inputs: <String, dynamic>{'sql': 'SELEC 2'},
      );
      root.next = select;
      select.next = union;
      final compilation = const SqlCompiler().compileWorkspace(<BlockNode>[
        root,
      ]);

      final projection = backwards.project(
        compilation: compilation,
        sqliteError: 'SqliteException(1): near "SELEC": syntax error',
      );

      expect(projection?.nodeId, 'union-syntax');
      expect(projection?.kind, SqlNodeErrorKind.syntax);
    });

    test('projects constraint failures onto the matching DML node', () {
      final kunden = EventBlock(id: 'run-kunden', position: Offset.zero)
        ..next = OperatorBlock(
          id: 'insert-kunden',
          position: Offset.zero,
          operatorType: BlockType.sqlInsert,
          inputs: <String, dynamic>{
            'table': 'kunden',
            'columns': 'email',
            'values': "'mail@example.de'",
          },
        );
      final bestellungen =
          EventBlock(id: 'run-bestellungen', position: Offset.zero)
            ..next = OperatorBlock(
              id: 'insert-bestellungen',
              position: Offset.zero,
              operatorType: BlockType.sqlInsert,
              inputs: <String, dynamic>{
                'table': 'bestellungen',
                'columns': 'gesamtbetrag',
                'values': '12.5',
              },
            );
      final compilation = const SqlCompiler().compileWorkspace(<BlockNode>[
        kunden,
        bestellungen,
      ]);

      final projection = backwards.project(
        compilation: compilation,
        sqliteError:
            'SqliteException(19): UNIQUE constraint failed: kunden.email',
      );

      expect(projection?.nodeId, 'insert-kunden');
      expect(projection?.kind, SqlNodeErrorKind.constraint);
    });

    test('does not blame a node for database connection failures', () {
      final compilation = _compileSingle(
        OperatorBlock(
          id: 'select',
          position: Offset.zero,
          operatorType: BlockType.sqlSelect,
          inputs: <String, dynamic>{'columns': '*', 'table': 'kunden'},
        ),
      );

      expect(
        backwards.project(
          compilation: compilation,
          sqliteError: 'No database connected.',
        ),
        isNull,
      );
    });

    test('projects missing indexes onto schema maintenance nodes', () {
      final compilation = _compileSingle(
        OperatorBlock(
          id: 'drop-index',
          position: Offset.zero,
          operatorType: BlockType.sqlDropIndex,
          inputs: <String, dynamic>{'name': 'idx_missing'},
        ),
      );

      final projection = backwards.project(
        compilation: compilation,
        sqliteError: 'SqliteException(1): no such index: idx_missing',
      );

      expect(projection?.nodeId, 'drop-index');
      expect(projection?.kind, SqlNodeErrorKind.missingSchemaObject);
    });
  });
}

SqlCompileResult _compileSingle(BlockNode node) {
  final root = EventBlock(id: 'run-${node.id}', position: Offset.zero)
    ..next = node;
  return const SqlCompiler().compileWorkspace(<BlockNode>[root]);
}
