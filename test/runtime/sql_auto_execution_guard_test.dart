import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_auto_execution_guard.dart';

void main() {
  BlockNode node(BlockType type, {BlockNode? next, List<BlockNode>? children}) {
    final result = OperatorBlock(
      id: 'node-${type.name}',
      position: Offset.zero,
      operatorType: type,
    );
    result.next = next;
    result.children = children ?? <BlockNode>[];
    return result;
  }

  test('allows automatic previews for read-only query nodes', () {
    expect(requiresManualSqlExecution([node(BlockType.sqlSelect)]), isFalse);
  });

  test('blocks automatic previews for Changes and Structure nodes', () {
    expect(requiresManualSqlExecution([node(BlockType.sqlInsert)]), isTrue);
    expect(
      requiresManualSqlExecution([node(BlockType.sqlCreateTable)]),
      isTrue,
    );
  });

  test('finds a protected node anywhere in a node chain', () {
    final select = node(BlockType.sqlSelect, next: node(BlockType.sqlDelete));

    expect(requiresManualSqlExecution([select]), isTrue);
  });

  test('requires explicit execution for every plugin block', () {
    final plugin = node(BlockType.sqlColumn);
    plugin.inputs[pluginBlockKeyInput] = 'com.example.plugin/custom_sql';

    expect(requiresManualSqlExecution([plugin]), isTrue);
  });

  test('requires explicit execution for plugin reporters', () {
    final select = node(BlockType.sqlSelect);
    select.inputs[reporterInputsKey] = <String, dynamic>{
      'columns': <String, dynamic>{
        'id': 'plugin-reporter',
        'type': BlockType.sqlColumn.name,
        'position': <String, double>{'dx': 0, 'dy': 0},
        'children': <dynamic>[],
        'inputs': <String, dynamic>{
          pluginBlockKeyInput: 'com.example.plugin/read_or_write',
        },
      },
    };

    expect(requiresManualSqlExecution([select]), isTrue);
  });
}
