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
  sqlAlias,
  sqlFunction,
  sqlFrom,
  sqlWhere,
  sqlAnd,
  sqlOr,
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
  sqlLimit,
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
  sqlInsertOrReplace,
  sqlUpsert,
  sqlUpdate,
  sqlDelete,
  sqlCreateTable,
  sqlCreateIndex,
  sqlDropIndex,
  sqlCreateView,
  sqlDropView,
  sqlCreateTrigger,
  sqlDropTrigger,
  sqlCreateVirtualTable,
  sqlAlterTable,
  sqlTruncate,
  sqlDropTable,
  sqlGrant,
  sqlRevoke,
  sqlCommit,
  sqlBeginTransaction,
  sqlEndTransaction,
  sqlRollback,
  sqlSavepoint,
  sqlRollbackToSavepoint,
  sqlReleaseSavepoint,
  sqlSetTransaction,
  sqlPragma,
  sqlAttachDatabase,
  sqlDetachDatabase,
  sqlVacuum,
  sqlReindex,
  sqlAnalyze,
  sqlExplain,
  sqlWith,
  sqlValues,
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

  static const int maxDecodedNodes = 1000;
  static const int maxDecodedDepth = 64;
  static const int maxChildrenPerNode = 128;
  static const int maxInputEntries = 64;
  static const int maxInputCollectionEntries = 128;
  static const int maxInputCollectionDepth = 32;
  static const int maxInputStringLength = 16 * 1024;

  static BlockNode fromJson(Map<String, dynamic> json) =>
      _fromJson(json, _BlockNodeDecodeBudget(), 1);

  /// Decodes a workspace root collection with one budget shared by every
  /// root. Project JSON is untrusted at this boundary, so independent root
  /// trees must not bypass the node limit.
  static List<BlockNode> fromJsonList(Iterable<Map<String, dynamic>> json) {
    final budget = _BlockNodeDecodeBudget();
    return <BlockNode>[for (final node in json) _fromJson(node, budget, 1)];
  }

  static BlockNode _fromJson(
    Map<String, dynamic> json,
    _BlockNodeDecodeBudget budget,
    int depth,
  ) {
    if (depth > maxDecodedDepth) {
      throw const FormatException('Workspace block nesting exceeds the limit.');
    }
    if (++budget.nodeCount > maxDecodedNodes) {
      throw const FormatException('Workspace contains too many blocks.');
    }
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
    if (childrenJson.length > maxChildrenPerNode) {
      throw const FormatException('A workspace block has too many children.');
    }
    final inputs =
        (json['inputs'] as Map<String, dynamic>? ?? <String, dynamic>{});
    _validateInputs(inputs);

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
      case BlockType.sqlAnd:
      case BlockType.sqlOr:
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
      case BlockType.sqlAlias:
      case BlockType.sqlFunction:
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
      case BlockType.sqlLimit:
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
      case BlockType.sqlInsertOrReplace:
      case BlockType.sqlUpsert:
      case BlockType.sqlUpdate:
      case BlockType.sqlDelete:
      case BlockType.sqlCreateTable:
      case BlockType.sqlCreateIndex:
      case BlockType.sqlDropIndex:
      case BlockType.sqlCreateView:
      case BlockType.sqlDropView:
      case BlockType.sqlCreateTrigger:
      case BlockType.sqlDropTrigger:
      case BlockType.sqlCreateVirtualTable:
      case BlockType.sqlAlterTable:
      case BlockType.sqlTruncate:
      case BlockType.sqlDropTable:
      case BlockType.sqlGrant:
      case BlockType.sqlRevoke:
      case BlockType.sqlCommit:
      case BlockType.sqlBeginTransaction:
      case BlockType.sqlEndTransaction:
      case BlockType.sqlRollback:
      case BlockType.sqlSavepoint:
      case BlockType.sqlRollbackToSavepoint:
      case BlockType.sqlReleaseSavepoint:
      case BlockType.sqlSetTransaction:
      case BlockType.sqlPragma:
      case BlockType.sqlAttachDatabase:
      case BlockType.sqlDetachDatabase:
      case BlockType.sqlVacuum:
      case BlockType.sqlReindex:
      case BlockType.sqlAnalyze:
      case BlockType.sqlExplain:
      case BlockType.sqlWith:
      case BlockType.sqlValues:
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

    node.next = nextJson == null
        ? null
        : _fromJson(nextJson, budget, depth + 1);
    node.children = childrenJson
        .map((child) => _fromJson(child, budget, depth + 1))
        .toList();
    return node;
  }

  static void _validateInputs(Map<String, dynamic> inputs) {
    if (inputs.length > maxInputEntries) {
      throw const FormatException('A workspace block has too many inputs.');
    }
    for (final entry in inputs.entries) {
      if (entry.key.length > maxInputStringLength) {
        throw const FormatException('A workspace input name is too long.');
      }
      _validateInputValue(entry.value, 1);
    }
  }

  static void _validateInputValue(Object? value, int depth) {
    if (depth > maxInputCollectionDepth) {
      throw const FormatException('Workspace input nesting exceeds the limit.');
    }
    switch (value) {
      case String value:
        if (value.length > maxInputStringLength) {
          throw const FormatException('A workspace input is too long.');
        }
      case num _ || bool _ || null:
        return;
      case List values:
        if (values.length > maxInputCollectionEntries) {
          throw const FormatException('A workspace input list is too large.');
        }
        for (final item in values) {
          _validateInputValue(item, depth + 1);
        }
      case Map values:
        if (values.length > maxInputCollectionEntries) {
          throw const FormatException('A workspace input map is too large.');
        }
        for (final entry in values.entries) {
          if (entry.key is! String ||
              (entry.key as String).length > maxInputStringLength) {
            throw const FormatException('A workspace input name is invalid.');
          }
          _validateInputValue(entry.value, depth + 1);
        }
      default:
        throw const FormatException('A workspace input has an invalid value.');
    }
  }
}

class _BlockNodeDecodeBudget {
  int nodeCount = 0;
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
