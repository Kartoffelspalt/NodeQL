import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sqlite_function_catalog.dart';

void main() {
  test('catalog covers the requested SQLite function families safely', () {
    final names = sqliteFunctionCatalog.map((item) => item.name).toSet();

    expect(names.length, sqliteFunctionCatalog.length);

    expect(
      names,
      containsAll(<String>[
        'abs',
        'ifnull',
        'group_concat',
        'total',
        'date',
        'time',
        'datetime',
        'julianday',
        'unixepoch',
        'strftime',
        'timediff',
      ]),
    );
    expect(names, isNot(contains('load_extension')));
  });

  test(
    'compiles Unix timestamps through SQLite datetime unixepoch modifier',
    () {
      final root = EventBlock(id: 'run', position: Offset.zero)
        ..next = OperatorBlock(
          id: 'select',
          position: Offset.zero,
          operatorType: BlockType.sqlSelect,
          inputs: <String, dynamic>{'columns': '*', 'table': ''},
        );
      final datetime = OperatorBlock(
        id: 'datetime',
        position: Offset.zero,
        operatorType: BlockType.sqlFunction,
        inputs: <String, dynamic>{
          'function': 'datetime',
          'args': <String>['created_at', "'unixepoch'"],
        },
      );
      setReporterForInput(root.next!, 'columns', datetime);

      expect(
        const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
        "SELECT datetime(created_at, 'unixepoch');",
      );
    },
  );

  test('compiles variable function arguments and nested reporters', () {
    final root = EventBlock(id: 'run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{'columns': '*', 'table': ''},
      );
    final function = OperatorBlock(
      id: 'coalesce',
      position: Offset.zero,
      operatorType: BlockType.sqlFunction,
      inputs: <String, dynamic>{
        'function': 'coalesce',
        'args': <String>['raw_value', "'fallback'"],
      },
    );
    setReporterForInput(
      function,
      'arg0',
      OperatorBlock(
        id: 'upper',
        position: Offset.zero,
        operatorType: BlockType.sqlUpper,
        inputs: <String, dynamic>{'expr': 'name'},
      ),
    );
    setReporterForInput(root.next!, 'columns', function);

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
      "SELECT coalesce(UPPER(name), 'fallback');",
    );
  });

  test('uses text edited through an individual function argument slot', () {
    final function = OperatorBlock(
      id: 'upper',
      position: Offset.zero,
      operatorType: BlockType.sqlFunction,
      inputs: <String, dynamic>{
        'function': 'upper',
        'args': <String>['placeholder'],
        'arg0': 'display_name',
      },
    );
    final root = EventBlock(id: 'run', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: <String, dynamic>{'columns': '*', 'table': ''},
      );
    setReporterForInput(root.next!, 'columns', function);

    expect(
      const SqlCompiler().compileWorkspace(<BlockNode>[root]).sql,
      'SELECT upper(display_name);',
    );
  });
}
