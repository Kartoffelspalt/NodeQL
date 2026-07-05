import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_syntax.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';

void main() {
  test('classifies SQL blocks by visual syntax role', () {
    expect(
      blockVisualKindForType(BlockType.sqlSelect),
      BlockVisualKind.statement,
    );
    expect(blockVisualKindForType(BlockType.sqlLeftJoin), BlockVisualKind.join);
    expect(
      blockVisualKindForType(BlockType.sqlCount),
      BlockVisualKind.expression,
    );
    expect(
      blockVisualKindForType(BlockType.sqlUnion),
      BlockVisualKind.setOperator,
    );
    expect(
      blockVisualKindForType(BlockType.sqlRollback),
      BlockVisualKind.terminal,
    );
  });

  test('enforces the SQL query clause order', () {
    expect(
      canFollowInSqlChain(BlockType.eventGreenFlag, BlockType.sqlSelect),
      isTrue,
    );
    expect(canFollowInSqlChain(BlockType.sqlSelect, BlockType.sqlFrom), isTrue);
    expect(
      canFollowInSqlChain(BlockType.sqlFrom, BlockType.sqlLeftJoin),
      isTrue,
    );
    expect(
      canFollowInSqlChain(BlockType.sqlLeftJoin, BlockType.sqlWhere),
      isTrue,
    );
    expect(
      canFollowInSqlChain(BlockType.sqlWhere, BlockType.sqlGroupBy),
      isTrue,
    );
    expect(
      canFollowInSqlChain(BlockType.sqlGroupBy, BlockType.sqlHaving),
      isTrue,
    );
    expect(
      canFollowInSqlChain(BlockType.sqlHaving, BlockType.sqlOrderBy),
      isTrue,
    );

    expect(
      canFollowInSqlChain(BlockType.sqlSelect, BlockType.sqlHaving),
      isFalse,
    );
    expect(
      canFollowInSqlChain(BlockType.sqlOrderBy, BlockType.sqlWhere),
      isFalse,
    );
  });

  test('assigns distinct heights to joins and expressions', () {
    final join = OperatorBlock(
      id: 'join',
      position: Offset.zero,
      operatorType: BlockType.sqlInnerJoin,
    );
    final expression = OperatorBlock(
      id: 'count',
      position: Offset.zero,
      operatorType: BlockType.sqlCount,
    );

    expect(baseHeightForBlock(join), 76);
    expect(baseHeightForBlock(expression), 44);
  });

  test('CROSS and NATURAL joins do not expose an ON condition row', () {
    final genericCross = OperatorBlock(
      id: 'generic-cross',
      position: Offset.zero,
      operatorType: BlockType.sqlJoin,
      inputs: <String, dynamic>{'join_type': 'CROSS'},
    );
    final cross = OperatorBlock(
      id: 'cross',
      position: Offset.zero,
      operatorType: BlockType.sqlCrossJoin,
    );
    final natural = OperatorBlock(
      id: 'natural',
      position: Offset.zero,
      operatorType: BlockType.sqlNaturalJoin,
    );

    expect(joinUsesCondition(genericCross), isFalse);
    expect(joinUsesCondition(cross), isFalse);
    expect(joinUsesCondition(natural), isFalse);
    expect(baseHeightForBlock(genericCross), 56);
    expect(baseHeightForBlock(cross), 56);
    expect(baseHeightForBlock(natural), 56);
  });

  test('JOIN labels only include ON for condition-based join types', () {
    final crossLabel = sqlLabelFor(
      BlockType.sqlJoin,
      SqlAbstractionMode.advanced,
      const <String, dynamic>{'join_type': 'CROSS'},
      'en',
    );
    final naturalLabel = sqlLabelFor(
      BlockType.sqlNaturalJoin,
      SqlAbstractionMode.advanced,
      const <String, dynamic>{},
      'en',
    );
    final leftLabel = sqlLabelFor(
      BlockType.sqlJoin,
      SqlAbstractionMode.advanced,
      const <String, dynamic>{'join_type': 'LEFT'},
      'en',
    );

    expect(crossLabel, isNot(contains('ON')));
    expect(naturalLabel, isNot(contains('ON')));
    expect(leftLabel, contains('ON [left_column] [operator] [right_column]'));
  });

  test('simple SELECT uses beginner-friendly all-columns wording', () {
    expect(
      sqlLabelFor(
        BlockType.sqlSelect,
        SqlAbstractionMode.simple,
        const <String, dynamic>{},
        'de',
      ),
      'Zeige [Spalten] aus Tabelle [table_name]',
    );
    expect(simpleAllColumnsLabel('de-DE'), 'Alles');
    expect(simpleAllColumnsLabel('en'), 'Everything');
  });

  test('simple German labels use localized column placeholders', () {
    final labels =
        <BlockType>[
          BlockType.sqlSelect,
          BlockType.sqlColumn,
          BlockType.sqlWhere,
          BlockType.sqlOrderBy,
          BlockType.sqlGroupBy,
          BlockType.sqlHaving,
          BlockType.sqlInnerJoin,
          BlockType.sqlInsert,
          BlockType.sqlUpdate,
          BlockType.sqlDelete,
          BlockType.sqlCreateTable,
          BlockType.sqlAlterTable,
          BlockType.sqlSubqueryIn,
          BlockType.sqlCount,
          BlockType.sqlSum,
          BlockType.sqlAvg,
          BlockType.sqlMin,
          BlockType.sqlMax,
        ].map(
          (type) => sqlLabelFor(
            type,
            SqlAbstractionMode.simple,
            const <String, dynamic>{},
            'de',
          ),
        );

    for (final label in labels) {
      expect(label, isNot(contains('column')));
      expect(label, isNot(contains('columns')));
    }
  });

  test('simple labels split complex beginner nodes into readable rows', () {
    expect(
      sqlLabelFor(
        BlockType.sqlHaving,
        SqlAbstractionMode.simple,
        const <String, dynamic>{},
        'de',
      ),
      contains('\n'),
    );
    expect(
      sqlLabelFor(
        BlockType.sqlUpdate,
        SqlAbstractionMode.simple,
        const <String, dynamic>{},
        'de',
      ),
      contains('\n'),
    );
  });

  test('gives the execute query trigger a dedicated start cap height', () {
    final trigger = EventBlock(id: 'trigger', position: Offset.zero);

    expect(baseHeightForBlock(trigger), 50);
    expect(hasTopConnector(trigger), isFalse);
    expect(hasBottomConnector(trigger), isTrue);
  });
}
