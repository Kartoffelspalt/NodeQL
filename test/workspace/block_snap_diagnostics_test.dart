import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/block_snap_diagnostics.dart';

void main() {
  test('covers every native block pair in the snap matrix', () {
    final report = buildBlockSnapDiagnosticReport();

    expect(report.total, nativeBlockTypes.length * nativeBlockTypes.length);
    expect(report.allowed, greaterThan(0));
    expect(report.blocked, greaterThan(0));
  });

  test('marks SQL clause order combinations used by the UI', () {
    expect(
      canSnapSequentially(BlockType.sqlGroupBy, BlockType.sqlHaving),
      isTrue,
    );
    expect(
      canSnapSequentially(BlockType.sqlHaving, BlockType.sqlOrderBy),
      isTrue,
    );
    expect(
      canSnapSequentially(BlockType.sqlSelect, BlockType.sqlHaving),
      isFalse,
    );
    expect(
      canSnapSequentially(BlockType.sqlOrderBy, BlockType.sqlHaving),
      isFalse,
    );
  });
}
