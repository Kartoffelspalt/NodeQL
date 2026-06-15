import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_syntax.dart';

const reporterInputsKey = r'$nodeqlReporters';

BlockNode? reporterForInput(BlockNode node, String inputKey) {
  final rawReporters = node.inputs[reporterInputsKey];
  if (rawReporters is! Map) return null;
  final rawReporter = rawReporters[inputKey];
  if (rawReporter is! Map) return null;
  return BlockNode.fromJson(Map<String, dynamic>.from(rawReporter));
}

void setReporterForInput(BlockNode node, String inputKey, BlockNode? reporter) {
  final existing = node.inputs[reporterInputsKey];
  final reporters = existing is Map
      ? Map<String, dynamic>.from(existing)
      : <String, dynamic>{};
  if (reporter == null) {
    reporters.remove(inputKey);
  } else {
    reporters[inputKey] = reporter.toJson();
  }
  if (reporters.isEmpty) {
    node.inputs.remove(reporterInputsKey);
  } else {
    node.inputs[reporterInputsKey] = reporters;
  }
}

bool isReporterType(BlockType type) {
  return blockVisualKindForType(type) == BlockVisualKind.expression;
}

bool slotAcceptsReporter(String rawToken, String inputKey) {
  if (rawToken.startsWith('{') || rawToken.endsWith('}')) return true;
  return const <String>{
    'column',
    'columns',
    'column_name',
    'expr',
    'value',
    'default',
    'result',
    'a',
    'b',
    'lhs',
    'then',
    'else',
    'from',
    'to',
  }.contains(inputKey);
}

String? primaryReporterInputKey(BlockType type) {
  return switch (type) {
    BlockType.sqlCount ||
    BlockType.sqlSum ||
    BlockType.sqlAvg ||
    BlockType.sqlMin ||
    BlockType.sqlMax ||
    BlockType.sqlSubstring ||
    BlockType.sqlLength ||
    BlockType.sqlUpper ||
    BlockType.sqlLower ||
    BlockType.sqlTrim ||
    BlockType.sqlLeft ||
    BlockType.sqlRight ||
    BlockType.sqlReplace ||
    BlockType.sqlDateAdd ||
    BlockType.sqlDateSub ||
    BlockType.sqlToChar => 'expr',
    _ => null,
  };
}
