import 'dart:ui';

import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_syntax.dart';

const nativeBlockTypes = <BlockType>[
  BlockType.eventGreenFlag,
  BlockType.motionMove,
  BlockType.motionTurn,
  BlockType.controlRepeat,
  BlockType.controlForever,
  BlockType.operatorAdd,
  BlockType.variableSet,
  BlockType.sqlSelect,
  BlockType.sqlColumn,
  BlockType.sqlText,
  BlockType.sqlFrom,
  BlockType.sqlWhere,
  BlockType.sqlJoin,
  BlockType.sqlInnerJoin,
  BlockType.sqlLeftJoin,
  BlockType.sqlRightJoin,
  BlockType.sqlFullJoin,
  BlockType.sqlCrossJoin,
  BlockType.sqlSelfJoin,
  BlockType.sqlNaturalJoin,
  BlockType.sqlGroupBy,
  BlockType.sqlHaving,
  BlockType.sqlOrderBy,
  BlockType.sqlUnion,
  BlockType.sqlIntersect,
  BlockType.sqlExcept,
  BlockType.sqlSubqueryIn,
  BlockType.sqlSubqueryAny,
  BlockType.sqlSubqueryAll,
  BlockType.sqlCount,
  BlockType.sqlSum,
  BlockType.sqlAvg,
  BlockType.sqlMin,
  BlockType.sqlMax,
  BlockType.sqlConcat,
  BlockType.sqlSubstring,
  BlockType.sqlLength,
  BlockType.sqlUpper,
  BlockType.sqlLower,
  BlockType.sqlTrim,
  BlockType.sqlLeft,
  BlockType.sqlRight,
  BlockType.sqlReplace,
  BlockType.sqlCurrentDate,
  BlockType.sqlCurrentTime,
  BlockType.sqlCurrentTimestamp,
  BlockType.sqlDatePart,
  BlockType.sqlDateAdd,
  BlockType.sqlDateSub,
  BlockType.sqlExtract,
  BlockType.sqlToChar,
  BlockType.sqlTimestampDiff,
  BlockType.sqlDateDiff,
  BlockType.sqlCase,
  BlockType.sqlIf,
  BlockType.sqlCoalesce,
  BlockType.sqlNullIf,
  BlockType.sqlInsert,
  BlockType.sqlUpdate,
  BlockType.sqlDelete,
  BlockType.sqlCreateTable,
  BlockType.sqlAlterTable,
  BlockType.sqlTruncate,
  BlockType.sqlDropTable,
  BlockType.sqlGrant,
  BlockType.sqlRevoke,
  BlockType.sqlCommit,
  BlockType.sqlRollback,
  BlockType.sqlSavepoint,
  BlockType.sqlRollbackToSavepoint,
  BlockType.sqlSetTransaction,
  BlockType.sqlLoop,
];

class BlockSnapDiagnosticCase {
  const BlockSnapDiagnosticCase({
    required this.previous,
    required this.next,
    required this.allowed,
  });

  final BlockType previous;
  final BlockType next;
  final bool allowed;
}

class BlockSnapDiagnosticReport {
  BlockSnapDiagnosticReport({required this.cases})
    : allowedCases = cases
          .where((entry) => entry.allowed)
          .toList(growable: false),
      allowed = cases.where((entry) => entry.allowed).length,
      total = cases.length;

  final List<BlockSnapDiagnosticCase> cases;
  final List<BlockSnapDiagnosticCase> allowedCases;
  final int allowed;
  final int total;

  int get blocked => total - allowed;
}

BlockSnapDiagnosticReport buildBlockSnapDiagnosticReport({
  List<BlockType> blockTypes = nativeBlockTypes,
}) {
  final cases = <BlockSnapDiagnosticCase>[];
  for (final previous in blockTypes) {
    for (final next in blockTypes) {
      cases.add(
        BlockSnapDiagnosticCase(
          previous: previous,
          next: next,
          allowed: canSnapSequentially(previous, next),
        ),
      );
    }
  }
  return BlockSnapDiagnosticReport(cases: cases);
}

bool canSnapSequentially(BlockType previous, BlockType next) {
  if (!hasBottomConnector(_diagnosticNode(previous)) ||
      !hasTopConnector(_diagnosticNode(next))) {
    return false;
  }
  if (previous == BlockType.eventGreenFlag) {
    return isStatementType(next) ||
        blockVisualKindForType(next) == BlockVisualKind.terminal;
  }
  if (isSqlChainType(previous) || isSqlChainType(next)) {
    return canFollowInSqlChain(previous, next);
  }
  return !isExpressionType(previous) && !isExpressionType(next);
}

BlockNode _diagnosticNode(BlockType type) {
  if (type == BlockType.eventGreenFlag) {
    return EventBlock(id: type.name, position: Offset.zero);
  }
  if (type == BlockType.controlRepeat ||
      type == BlockType.controlForever ||
      type == BlockType.sqlLoop) {
    return ControlBlock(
      id: type.name,
      position: Offset.zero,
      controlType: type,
    );
  }
  if (type == BlockType.motionMove ||
      type == BlockType.motionTurn ||
      type == BlockType.sqlWhere ||
      type == BlockType.sqlOrderBy) {
    return MotionBlock(id: type.name, position: Offset.zero, motionType: type);
  }
  if (type == BlockType.variableSet) {
    return VariableBlock(id: type.name, position: Offset.zero);
  }
  return OperatorBlock(
    id: type.name,
    position: Offset.zero,
    operatorType: type,
  );
}
