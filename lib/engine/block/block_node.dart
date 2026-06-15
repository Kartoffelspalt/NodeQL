import 'dart:ui';

enum BlockType {
  eventGreenFlag,
  motionMove,
  motionTurn,
  controlRepeat,
  controlForever,
  operatorAdd,
  variableSet,
  sqlSelect,
  sqlColumn,
  sqlText,
  sqlFrom,
  sqlWhere,
  sqlJoin,
  sqlInnerJoin,
  sqlLeftJoin,
  sqlRightJoin,
  sqlFullJoin,
  sqlCrossJoin,
  sqlSelfJoin,
  sqlNaturalJoin,
  sqlGroupBy,
  sqlHaving,
  sqlOrderBy,
  sqlUnion,
  sqlIntersect,
  sqlExcept,
  sqlSubqueryIn,
  sqlSubqueryAny,
  sqlSubqueryAll,
  sqlCount,
  sqlSum,
  sqlAvg,
  sqlMin,
  sqlMax,
  sqlConcat,
  sqlSubstring,
  sqlLength,
  sqlUpper,
  sqlLower,
  sqlTrim,
  sqlLeft,
  sqlRight,
  sqlReplace,
  sqlCurrentDate,
  sqlCurrentTime,
  sqlCurrentTimestamp,
  sqlDatePart,
  sqlDateAdd,
  sqlDateSub,
  sqlExtract,
  sqlToChar,
  sqlTimestampDiff,
  sqlDateDiff,
  sqlCase,
  sqlIf,
  sqlCoalesce,
  sqlNullIf,
  sqlInsert,
  sqlUpdate,
  sqlDelete,
  sqlCreateTable,
  sqlAlterTable,
  sqlTruncate,
  sqlDropTable,
  sqlGrant,
  sqlRevoke,
  sqlCommit,
  sqlRollback,
  sqlSavepoint,
  sqlRollbackToSavepoint,
  sqlSetTransaction,
  sqlLoop,
}

abstract class BlockNode {
  BlockNode({
    required this.id,
    required this.type,
    required this.position,
    this.next,
    List<BlockNode>? children,
    Map<String, dynamic>? inputs,
  }) : children = children ?? <BlockNode>[],
       inputs = inputs ?? <String, dynamic>{};

  final String id;
  final BlockType type;
  Offset position;
  BlockNode? next;
  List<BlockNode> children;
  Map<String, dynamic> inputs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': runtimeType.toString(),
    'id': id,
    'type': type.name,
    'position': <String, dynamic>{'dx': position.dx, 'dy': position.dy},
    'next': next?.toJson(),
    'children': children.map((child) => child.toJson()).toList(),
    'inputs': inputs,
  };

  static BlockNode fromJson(Map<String, dynamic> json) {
    final type = BlockType.values.firstWhere(
      (value) => value.name == json['type'],
    );
    final pos = json['position'] as Map<String, dynamic>;
    final offset = Offset(
      (pos['dx'] as num).toDouble(),
      (pos['dy'] as num).toDouble(),
    );

    final nextJson = json['next'] as Map<String, dynamic>?;
    final childrenJson = (json['children'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final inputs =
        (json['inputs'] as Map<String, dynamic>? ?? <String, dynamic>{});

    BlockNode node;
    switch (type) {
      case BlockType.eventGreenFlag:
        node = EventBlock(id: json['id'] as String, position: offset);
      case BlockType.sqlSelect:
        node = OperatorBlock(
          id: json['id'] as String,
          position: offset,
          operatorType: type,
          inputs: inputs,
        );
      case BlockType.motionMove:
      case BlockType.motionTurn:
      case BlockType.sqlWhere:
      case BlockType.sqlOrderBy:
        node = MotionBlock(
          id: json['id'] as String,
          position: offset,
          motionType: type,
          inputs: inputs,
        );
      case BlockType.controlRepeat:
      case BlockType.controlForever:
      case BlockType.sqlLoop:
        node = ControlBlock(
          id: json['id'] as String,
          position: offset,
          controlType: type,
          inputs: inputs,
        );
      case BlockType.operatorAdd:
      case BlockType.sqlColumn:
      case BlockType.sqlText:
      case BlockType.sqlFrom:
      case BlockType.sqlJoin:
      case BlockType.sqlInnerJoin:
      case BlockType.sqlLeftJoin:
      case BlockType.sqlRightJoin:
      case BlockType.sqlFullJoin:
      case BlockType.sqlCrossJoin:
      case BlockType.sqlSelfJoin:
      case BlockType.sqlNaturalJoin:
      case BlockType.sqlGroupBy:
      case BlockType.sqlHaving:
      case BlockType.sqlUnion:
      case BlockType.sqlIntersect:
      case BlockType.sqlExcept:
      case BlockType.sqlSubqueryIn:
      case BlockType.sqlSubqueryAny:
      case BlockType.sqlSubqueryAll:
      case BlockType.sqlCount:
      case BlockType.sqlSum:
      case BlockType.sqlAvg:
      case BlockType.sqlMin:
      case BlockType.sqlMax:
      case BlockType.sqlConcat:
      case BlockType.sqlSubstring:
      case BlockType.sqlLength:
      case BlockType.sqlUpper:
      case BlockType.sqlLower:
      case BlockType.sqlTrim:
      case BlockType.sqlLeft:
      case BlockType.sqlRight:
      case BlockType.sqlReplace:
      case BlockType.sqlCurrentDate:
      case BlockType.sqlCurrentTime:
      case BlockType.sqlCurrentTimestamp:
      case BlockType.sqlDatePart:
      case BlockType.sqlDateAdd:
      case BlockType.sqlDateSub:
      case BlockType.sqlExtract:
      case BlockType.sqlToChar:
      case BlockType.sqlTimestampDiff:
      case BlockType.sqlDateDiff:
      case BlockType.sqlCase:
      case BlockType.sqlIf:
      case BlockType.sqlCoalesce:
      case BlockType.sqlNullIf:
      case BlockType.sqlInsert:
      case BlockType.sqlUpdate:
      case BlockType.sqlDelete:
      case BlockType.sqlCreateTable:
      case BlockType.sqlAlterTable:
      case BlockType.sqlTruncate:
      case BlockType.sqlDropTable:
      case BlockType.sqlGrant:
      case BlockType.sqlRevoke:
      case BlockType.sqlCommit:
      case BlockType.sqlRollback:
      case BlockType.sqlSavepoint:
      case BlockType.sqlRollbackToSavepoint:
      case BlockType.sqlSetTransaction:
        node = OperatorBlock(
          id: json['id'] as String,
          position: offset,
          operatorType: type,
          inputs: inputs,
        );
      case BlockType.variableSet:
        node = VariableBlock(
          id: json['id'] as String,
          position: offset,
          inputs: inputs,
        );
    }

    node.next = nextJson == null ? null : BlockNode.fromJson(nextJson);
    node.children = childrenJson.map(BlockNode.fromJson).toList();
    return node;
  }
}

class EventBlock extends BlockNode {
  EventBlock({required super.id, required super.position, super.next})
    : super(type: BlockType.eventGreenFlag);
}

class MotionBlock extends BlockNode {
  MotionBlock({
    required super.id,
    required super.position,
    required BlockType motionType,
    super.next,
    super.inputs,
  }) : super(type: motionType);
}

class ControlBlock extends BlockNode {
  ControlBlock({
    required super.id,
    required super.position,
    required BlockType controlType,
    super.next,
    super.children,
    super.inputs,
  }) : super(type: controlType);
}

class OperatorBlock extends BlockNode {
  OperatorBlock({
    required super.id,
    required super.position,
    required BlockType operatorType,
    super.inputs,
  }) : super(type: operatorType);
}

class VariableBlock extends BlockNode {
  VariableBlock({required super.id, required super.position, super.inputs})
    : super(type: BlockType.variableSet);
}
