import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';

void main() {
  test('nested reporter survives workspace JSON serialization', () {
    final aggregate = OperatorBlock(
      id: 'avg',
      position: Offset.zero,
      operatorType: BlockType.sqlAvg,
      inputs: <String, dynamic>{'expr': 'amount'},
    );
    final column = OperatorBlock(
      id: 'column',
      position: Offset.zero,
      operatorType: BlockType.sqlColumn,
      inputs: <String, dynamic>{'column': 'price'},
    );
    setReporterForInput(aggregate, 'expr', column);

    final restored = BlockNode.fromJson(
      jsonDecode(jsonEncode(aggregate.toJson())) as Map<String, dynamic>,
    );
    final restoredColumn = reporterForInput(restored, 'expr');

    expect(restoredColumn?.type, BlockType.sqlColumn);
    expect(restoredColumn?.inputs['column'], 'price');
  });

  test('only expression-shaped blocks are accepted as reporters', () {
    expect(isReporterType(BlockType.sqlColumn), isTrue);
    expect(isReporterType(BlockType.sqlText), isTrue);
    expect(isReporterType(BlockType.sqlAvg), isTrue);
    expect(isReporterType(BlockType.sqlFrom), isFalse);
  });
}
