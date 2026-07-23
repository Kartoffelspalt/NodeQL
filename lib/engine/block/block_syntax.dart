import 'package:nodeql/engine/block/block_node.dart';

enum BlockVisualKind {
  trigger,
  statement,
  clause,
  join,
  setOperator,
  expression,
  container,
  terminal,
  pluginStatement,
  pluginValue,
  pluginContainer,
}

BlockVisualKind blockVisualKind(BlockNode node, {String? pluginShape}) {
  final extensionShape =
      pluginShape ?? node.inputs[r'$nodeqlPluginShape'] as String?;
  if (extensionShape != null) {
    return switch (extensionShape) {
      'value' => BlockVisualKind.pluginValue,
      'container' => BlockVisualKind.pluginContainer,
      _ => BlockVisualKind.pluginStatement,
    };
  }
  if (node.inputs.containsKey(r'$nodeqlPluginBlock')) {
    if (node is ControlBlock) return BlockVisualKind.pluginContainer;
    if (node.type == BlockType.sqlColumn) return BlockVisualKind.pluginValue;
    return BlockVisualKind.pluginStatement;
  }
  if (node is ControlBlock) return BlockVisualKind.container;
  return blockVisualKindForType(node.type);
}

BlockVisualKind blockVisualKindForType(BlockType type) {
  return switch (type) {
    BlockType.eventGreenFlag => BlockVisualKind.trigger,
    BlockType.sqlSelect ||
    BlockType.sqlInsert ||
    BlockType.sqlUpdate ||
    BlockType.sqlDelete ||
    BlockType.sqlCreateTable ||
    BlockType.sqlAlterTable ||
    BlockType.sqlTruncate ||
    BlockType.sqlDropTable ||
    BlockType.sqlGrant ||
    BlockType.sqlRevoke ||
    BlockType.sqlSavepoint ||
    BlockType.sqlRollbackToSavepoint ||
    BlockType.sqlSetTransaction => BlockVisualKind.statement,
    BlockType.sqlJoin ||
    BlockType.sqlInnerJoin ||
    BlockType.sqlLeftJoin ||
    BlockType.sqlRightJoin ||
    BlockType.sqlFullJoin ||
    BlockType.sqlCrossJoin ||
    BlockType.sqlSelfJoin ||
    BlockType.sqlNaturalJoin => BlockVisualKind.join,
    BlockType.sqlUnion ||
    BlockType.sqlIntersect ||
    BlockType.sqlExcept => BlockVisualKind.setOperator,
    BlockType.sqlColumn ||
    BlockType.sqlText ||
    BlockType.sqlSubqueryIn ||
    BlockType.sqlSubqueryAny ||
    BlockType.sqlSubqueryAll ||
    BlockType.sqlCount ||
    BlockType.sqlSum ||
    BlockType.sqlAvg ||
    BlockType.sqlMin ||
    BlockType.sqlMax ||
    BlockType.sqlConcat ||
    BlockType.sqlSubstring ||
    BlockType.sqlLength ||
    BlockType.sqlUpper ||
    BlockType.sqlLower ||
    BlockType.sqlTrim ||
    BlockType.sqlLeft ||
    BlockType.sqlRight ||
    BlockType.sqlReplace ||
    BlockType.sqlCurrentDate ||
    BlockType.sqlCurrentTime ||
    BlockType.sqlCurrentTimestamp ||
    BlockType.sqlDatePart ||
    BlockType.sqlDateAdd ||
    BlockType.sqlDateSub ||
    BlockType.sqlExtract ||
    BlockType.sqlToChar ||
    BlockType.sqlTimestampDiff ||
    BlockType.sqlDateDiff ||
    BlockType.sqlCase ||
    BlockType.sqlIf ||
    BlockType.sqlCoalesce ||
    BlockType.sqlNullIf ||
    BlockType.operatorAdd => BlockVisualKind.expression,
    BlockType.sqlCommit || BlockType.sqlRollback => BlockVisualKind.terminal,
    BlockType.controlRepeat ||
    BlockType.controlForever ||
    BlockType.sqlLoop => BlockVisualKind.container,
    _ => BlockVisualKind.clause,
  };
}

double baseHeightForBlock(BlockNode node) {
  return switch (blockVisualKind(node)) {
    BlockVisualKind.trigger => 50,
    BlockVisualKind.statement => 56,
    BlockVisualKind.join => joinUsesCondition(node) ? 86 : 66,
    BlockVisualKind.setOperator => 54,
    BlockVisualKind.expression => 44,
    BlockVisualKind.terminal => 48,
    BlockVisualKind.pluginStatement => 56,
    BlockVisualKind.pluginValue => 46,
    BlockVisualKind.pluginContainer => 50,
    _ => 50,
  };
}

bool isJoinType(BlockType type) =>
    blockVisualKindForType(type) == BlockVisualKind.join;

bool joinUsesCondition(BlockNode node) {
  if (node.type == BlockType.sqlCrossJoin ||
      node.type == BlockType.sqlNaturalJoin) {
    return false;
  }
  if (node.type != BlockType.sqlJoin) return true;
  final type = '${node.inputs['join_type'] ?? 'INNER'}'.trim().toUpperCase();
  return type != 'CROSS' && type != 'NATURAL';
}

bool isStatementType(BlockType type) =>
    blockVisualKindForType(type) == BlockVisualKind.statement;

bool isExpressionType(BlockType type) =>
    blockVisualKindForType(type) == BlockVisualKind.expression;

bool hasTopConnector(BlockNode node) {
  return switch (blockVisualKind(node)) {
    BlockVisualKind.trigger ||
    BlockVisualKind.expression ||
    BlockVisualKind.pluginValue => false,
    _ => true,
  };
}

bool isSqlChainType(BlockType type) {
  return isStatementType(type) ||
      isJoinType(type) ||
      type == BlockType.sqlFrom ||
      type == BlockType.sqlWhere ||
      type == BlockType.sqlGroupBy ||
      type == BlockType.sqlHaving ||
      type == BlockType.sqlOrderBy ||
      blockVisualKindForType(type) == BlockVisualKind.setOperator ||
      blockVisualKindForType(type) == BlockVisualKind.terminal;
}

bool hasBottomConnector(BlockNode node) {
  return switch (blockVisualKind(node)) {
    BlockVisualKind.expression ||
    BlockVisualKind.pluginValue ||
    BlockVisualKind.terminal => false,
    _ => true,
  };
}

bool canFollowInSqlChain(BlockType previous, BlockType next) {
  if (previous == BlockType.eventGreenFlag) {
    return isStatementType(next) ||
        blockVisualKindForType(next) == BlockVisualKind.terminal;
  }

  if (isExpressionType(previous) || isExpressionType(next)) return false;
  if (blockVisualKindForType(previous) == BlockVisualKind.terminal) {
    return false;
  }

  if (previous == BlockType.sqlSelect) {
    return next == BlockType.sqlFrom ||
        isJoinType(next) ||
        next == BlockType.sqlWhere ||
        next == BlockType.sqlGroupBy ||
        next == BlockType.sqlOrderBy ||
        blockVisualKindForType(next) == BlockVisualKind.setOperator;
  }
  if (previous == BlockType.sqlFrom || isJoinType(previous)) {
    return isJoinType(next) ||
        next == BlockType.sqlWhere ||
        next == BlockType.sqlGroupBy ||
        next == BlockType.sqlOrderBy ||
        blockVisualKindForType(next) == BlockVisualKind.setOperator;
  }
  if (previous == BlockType.sqlWhere) {
    return next == BlockType.sqlGroupBy ||
        next == BlockType.sqlOrderBy ||
        blockVisualKindForType(next) == BlockVisualKind.setOperator;
  }
  if (previous == BlockType.sqlGroupBy) {
    return next == BlockType.sqlHaving ||
        next == BlockType.sqlOrderBy ||
        blockVisualKindForType(next) == BlockVisualKind.setOperator;
  }
  if (previous == BlockType.sqlHaving) {
    return next == BlockType.sqlOrderBy ||
        blockVisualKindForType(next) == BlockVisualKind.setOperator;
  }
  if (previous == BlockType.sqlOrderBy) {
    return blockVisualKindForType(next) == BlockVisualKind.setOperator;
  }
  if (previous == BlockType.sqlUpdate || previous == BlockType.sqlDelete) {
    return next == BlockType.sqlWhere || next == BlockType.sqlOrderBy;
  }

  return false;
}