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

Iterable<BlockNode> embeddedReporters(BlockNode node) sync* {
  final raw = node.inputs[reporterInputsKey];
  if (raw is! Map) return;
  for (final key in raw.keys.whereType<String>()) {
    final reporter = reporterForInput(node, key);
    if (reporter == null) continue;
    yield reporter;
    yield* embeddedReporters(reporter);
  }
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
  if (RegExp(r'^arg\d+$').hasMatch(inputKey)) return true;
  return const <String>{
    'aggregate',
    'column',
    'columns',
    'column_name',
    'where_column',
    'left_column',
    'right_column',
    'condition_column',
    'expr',
    'value',
    'where_value',
    'condition_value',
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

bool slotAcceptsReporterType(
  String rawToken,
  String inputKey,
  BlockType reporterType,
) {
  if (!slotAcceptsReporter(rawToken, inputKey)) return false;
  if (inputKey != 'aggregate') return isReporterType(reporterType);
  return switch (reporterType) {
    BlockType.sqlCount ||
    BlockType.sqlSum ||
    BlockType.sqlAvg ||
    BlockType.sqlMin ||
    BlockType.sqlMax => true,
    _ => false,
  };
}

String? primaryReporterInputKey(BlockType type) {
  return switch (type) {
    BlockType.sqlAlias => 'value',
    BlockType.sqlFunction => 'arg0',
    BlockType.sqlCount ||
    BlockType.sqlSum ||
    BlockType.sqlAvg ||
    BlockType.sqlMin ||
    BlockType.sqlMax => 'column',
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

bool requiresReporterInput(BlockType type, String inputKey) {
  return switch (type) {
    BlockType.sqlWhere ||
    BlockType.sqlAnd ||
    BlockType.sqlOr => inputKey == 'value',
    BlockType.sqlUpdate => inputKey == 'value' || inputKey == 'where_value',
    BlockType.sqlDelete => inputKey == 'where_value',
    BlockType.sqlCase || BlockType.sqlIf =>
      inputKey == 'condition_value' ||
          inputKey == 'value' ||
          inputKey == 'result' ||
          inputKey == 'default',
    _ => false,
  };
}
