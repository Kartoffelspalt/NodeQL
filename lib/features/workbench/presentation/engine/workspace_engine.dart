import 'dart:math';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/engine/block/block_syntax.dart';

enum SnapZone { topOuter, bottomOuter, innerTop, innerBottom }

class WorkspaceState {
  const WorkspaceState({
    required this.roots,
    required this.scale,
    required this.pan,
    this.draggingId,
    this.selectedBlockId,
    this.selectedBlockIds = const <String>{},
    this.highlightTargetId,
    this.highlightZone,
    this.rejectedTargetId,
    this.rejectedZone,
    this.lastPointerGlobal,
    this.revision = 0,
  });

  final List<BlockNode> roots;
  final double scale;
  final Offset pan;
  final String? draggingId;
  final String? selectedBlockId;
  final Set<String> selectedBlockIds;
  final String? highlightTargetId;
  final SnapZone? highlightZone;
  final String? rejectedTargetId;
  final SnapZone? rejectedZone;
  final Offset? lastPointerGlobal;
  final int revision;

  WorkspaceState copyWith({
    List<BlockNode>? roots,
    double? scale,
    Offset? pan,
    String? draggingId,
    String? selectedBlockId,
    Set<String>? selectedBlockIds,
    String? highlightTargetId,
    SnapZone? highlightZone,
    String? rejectedTargetId,
    SnapZone? rejectedZone,
    Offset? lastPointerGlobal,
    bool clearDrag = false,
    bool clearSelected = false,
    bool clearHighlight = false,
    bool clearRejected = false,
    bool clearPointer = false,
    int? revision,
  }) {
    return WorkspaceState(
      roots: roots ?? this.roots,
      scale: scale ?? this.scale,
      pan: pan ?? this.pan,
      draggingId: clearDrag ? null : (draggingId ?? this.draggingId),
      selectedBlockId: clearSelected
          ? null
          : (selectedBlockId ?? this.selectedBlockId),
      selectedBlockIds: clearSelected
          ? <String>{}
          : (selectedBlockIds ?? this.selectedBlockIds),
      highlightTargetId: clearHighlight
          ? null
          : (highlightTargetId ?? this.highlightTargetId),
      highlightZone: clearHighlight
          ? null
          : (highlightZone ?? this.highlightZone),
      rejectedTargetId: clearRejected
          ? null
          : (rejectedTargetId ?? this.rejectedTargetId),
      rejectedZone: clearRejected ? null : (rejectedZone ?? this.rejectedZone),
      lastPointerGlobal: clearPointer
          ? null
          : (lastPointerGlobal ?? this.lastPointerGlobal),
      revision: revision ?? this.revision,
    );
  }
}

final workspaceProvider =
    StateNotifierProvider<WorkspaceController, WorkspaceState>(
      (ref) => WorkspaceController(),
    );

class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController()
    : super(
        WorkspaceState(
          roots: <BlockNode>[
            EventBlock(id: 'event_1', position: const Offset(120, 120))
              ..next =
                  (OperatorBlock(
                      id: 'select_1',
                      position: const Offset(120, 178),
                      operatorType: BlockType.sqlSelect,
                      inputs: <String, dynamic>{
                        'columns': 'customers.id, customers.name',
                        'table': 'customers',
                        'separate_from': true,
                      },
                    )
                    ..next =
                        (OperatorBlock(
                            id: 'from_1',
                            position: const Offset(120, 234),
                            operatorType: BlockType.sqlFrom,
                            inputs: <String, dynamic>{'table': 'customers'},
                          )
                          ..next =
                              (OperatorBlock(
                                  id: 'join_1',
                                  position: const Offset(120, 284),
                                  operatorType: BlockType.sqlLeftJoin,
                                  inputs: <String, dynamic>{
                                    'table': 'orders',
                                    'on': 'orders.customer_id = customers.id',
                                  },
                                )
                                ..next =
                                    (MotionBlock(
                                        id: 'where_1',
                                        position: const Offset(120, 360),
                                        motionType: BlockType.sqlWhere,
                                        inputs: <String, dynamic>{
                                          'predicate': 'customers.active = 1',
                                        },
                                      )
                                      ..next = MotionBlock(
                                        id: 'order_1',
                                        position: const Offset(120, 410),
                                        motionType: BlockType.sqlOrderBy,
                                        inputs: <String, dynamic>{
                                          'expr': 'customers.name ASC',
                                          'column': 'customers.name',
                                          'order': 'ASC',
                                        },
                                      ))))),
          ],
          scale: 1,
          pan: Offset.zero,
        ),
      ) {
    _relayoutAll();
  }

  static const double blockWidth = 180;
  static const double blockBaseHeight = 50;
  static const double snapDistance = 25;

  static const double cUpperBar = 40;
  static const double cLowerBar = 20;
  static const double cInnerMin = 40;
  static const double childIndent = 15;

  final Random _random = Random();
  static const int _historyLimit = 120;
  final List<String> _undoStack = <String>[];
  final List<String> _redoStack = <String>[];
  String? _dragStartSnapshot;
  bool _dragChanged = false;

  void setScale(double scale) {
    state = state.copyWith(scale: scale.clamp(0.5, 2.0));
  }

  void zoomAt(Offset focalPoint, double scale) {
    final oldScale = state.scale;
    final nextScale = scale.clamp(0.25, 3.0);
    if ((nextScale - oldScale).abs() < 0.001) return;

    final worldPoint = (focalPoint - state.pan) / oldScale;
    final nextPan = focalPoint - (worldPoint * nextScale);
    state = state.copyWith(scale: nextScale, pan: nextPan);
  }

  void panBy(Offset delta) {
    state = state.copyWith(pan: state.pan + delta);
  }

  BlockNode addTemplate(
    BlockType type,
    Offset worldPos, {
    Map<String, dynamic>? defaults,
    bool autoSnap = true,
    bool recordUndo = true,
  }) {
    if (recordUndo) _pushUndoSnapshot();
    final node = _createNode(type, worldPos);
    if (defaults != null && defaults.isNotEmpty) {
      node.inputs.addAll(defaults);
    }
    state = state.copyWith(roots: <BlockNode>[...state.roots, node]);

    if (autoSnap) {
      final snap = _findBestSnap(node, excludedIds: <String>{node.id});
      if (snap != null) {
        _insertBySnap(node, snap.target, snap.zone);
      }
    }

    _relayoutAll();
    _touch();
    return node;
  }

  Offset suggestedTemplatePosition(BlockType type) {
    final probe = _createNode(type, Offset.zero);
    final targets = allBlocks().toList(growable: false).reversed;
    for (final target in targets) {
      if (!hasBottomConnector(target) || !hasTopConnector(probe)) continue;
      if (!_canConnectSequentially(target, probe)) continue;
      final successor = target.next;
      if (successor != null &&
          !_canConnectSequentially(_chainTail(probe), successor)) {
        continue;
      }
      return Offset(
        target.position.dx,
        target.position.dy + blockHeight(target),
      );
    }

    final rootCount = state.roots.length;
    return Offset(120, 120 + (rootCount * 72));
  }

  void updateInput(BlockNode node, String key, dynamic value) {
    _pushUndoSnapshot();
    node.inputs[key] = value;
    if (node.type == BlockType.sqlOrderBy) {
      if (key == 'column' || key == 'order') {
        final col = '${node.inputs['column'] ?? 'id'}'.trim();
        final ord = '${node.inputs['order'] ?? 'ASC'}'.trim();
        node.inputs['expr'] = '$col $ord'.trim();
      } else if (key == 'expr' && value is String) {
        final expr = value.trim();
        final parts = expr.split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          node.inputs['column'] = parts.first;
        }
        if (parts.length > 1) {
          node.inputs['order'] = parts.last.toUpperCase();
        }
      }
    }
    if (key == 'table' && value is String && value.trim().isNotEmpty) {
      _propagateTableSelection(node, value.trim());
    }
    _relayoutAll();
    _touch();
  }

  void setReporterInput(
    BlockNode node,
    String key,
    BlockType reporterType, {
    Map<String, dynamic>? defaults,
  }) {
    if (!isReporterType(reporterType)) return;
    _pushUndoSnapshot();
    final reporter = _createNode(reporterType, Offset.zero);
    if (defaults != null) reporter.inputs.addAll(defaults);
    reporter.inputs.remove('__width');
    setReporterForInput(node, key, reporter);
    _relayoutAll();
    _touch();
  }

  void updateReporterInput(
    BlockNode node,
    String key,
    BlockNode reporter,
    String reporterKey,
    dynamic value,
  ) {
    _pushUndoSnapshot();
    reporter.inputs[reporterKey] = value;
    setReporterForInput(node, key, reporter);
    _relayoutAll();
    _touch();
  }

  void setNestedReporterInput(
    BlockNode node,
    String key,
    BlockNode reporter,
    String nestedKey,
    BlockType nestedType, {
    Map<String, dynamic>? defaults,
  }) {
    if (!isReporterType(nestedType)) return;
    _pushUndoSnapshot();
    final nested = _createNode(nestedType, Offset.zero);
    if (defaults != null) nested.inputs.addAll(defaults);
    nested.inputs.remove('__width');
    setReporterForInput(reporter, nestedKey, nested);
    setReporterForInput(node, key, reporter);
    _relayoutAll();
    _touch();
  }

  void updateNestedReporterInput(
    BlockNode node,
    String key,
    BlockNode reporter,
    String nestedKey,
    BlockNode nested,
    String nestedInputKey,
    dynamic value,
  ) {
    _pushUndoSnapshot();
    nested.inputs[nestedInputKey] = value;
    setReporterForInput(reporter, nestedKey, nested);
    setReporterForInput(node, key, reporter);
    _relayoutAll();
    _touch();
  }

  void removeNestedReporterInput(
    BlockNode node,
    String key,
    BlockNode reporter,
    String nestedKey,
  ) {
    _pushUndoSnapshot();
    setReporterForInput(reporter, nestedKey, null);
    setReporterForInput(node, key, reporter);
    _relayoutAll();
    _touch();
  }

  void removeReporterInput(BlockNode node, String key) {
    if (reporterForInput(node, key) == null) return;
    _pushUndoSnapshot();
    setReporterForInput(node, key, null);
    _relayoutAll();
    _touch();
  }

  void startDrag(Offset worldPos, {bool recordUndo = true}) {
    final hit = _hitTest(worldPos);
    if (hit != null && recordUndo) {
      _dragStartSnapshot = toJsonString();
      _dragChanged = false;
    } else if (!recordUndo) {
      _dragStartSnapshot = null;
      _dragChanged = false;
    }
    if (hit != null) {
      _detachToRootForDragging(hit, preserveSubTree: true);
      _relayoutAll();
    }

    state = state.copyWith(
      draggingId: hit?.id,
      selectedBlockId: hit?.id,
      clearHighlight: true,
      clearRejected: true,
      revision: state.revision + 1,
    );
  }

  void updateDrag(Offset worldDelta) {
    final id = state.draggingId;
    if (id == null) return;
    final dragged = findById(id);
    if (dragged == null) return;

    dragged.position = dragged.position + worldDelta;
    _dragChanged = true;
    _layoutNodeSubTree(dragged);

    final snap = _findBestSnap(dragged, excludedIds: _subTreeIds(dragged));
    final rejected = snap == null
        ? _findBestRejectedSnap(dragged, excludedIds: _subTreeIds(dragged))
        : null;
    state = state.copyWith(
      highlightTargetId: snap?.target.id,
      highlightZone: snap?.zone,
      clearHighlight: snap == null,
      rejectedTargetId: rejected?.target.id,
      rejectedZone: rejected?.zone,
      clearRejected: rejected == null,
    );
  }

  void endDrag({bool deleteDragged = false, bool recordUndo = true}) {
    final draggedId = state.draggingId;
    if (draggedId == null) {
      state = state.copyWith(
        clearDrag: true,
        clearHighlight: true,
        clearRejected: true,
        clearPointer: true,
      );
      return;
    }

    final dragged = findById(draggedId);
    final target = state.highlightTargetId == null
        ? null
        : findById(state.highlightTargetId!);
    final zone = state.highlightZone;

    if (dragged != null && deleteDragged) {
      if (recordUndo) _pushDragUndoSnapshotIfNeeded();
      _deleteSingleNode(dragged);
    } else if (dragged != null && target != null && zone != null) {
      if (recordUndo) _pushDragUndoSnapshotIfNeeded();
      _insertBySnap(dragged, target, zone);
    } else {
      _dragStartSnapshot = null;
      _dragChanged = false;
    }

    _relayoutAll();
    state = state.copyWith(
      clearDrag: true,
      clearHighlight: true,
      clearRejected: true,
      clearPointer: true,
      revision: state.revision + 1,
    );
  }

  void selectAt(Offset worldPos) {
    selectAtWithMode(worldPos);
  }

  void selectAtWithMode(Offset worldPos, {bool append = false}) {
    final hit = _hitTest(worldPos);
    if (hit == null) {
      if (!append) {
        state = state.copyWith(
          selectedBlockId: null,
          selectedBlockIds: <String>{},
          revision: state.revision + 1,
        );
      }
      return;
    }
    final nextSet = <String>{...state.selectedBlockIds};
    if (append) {
      if (nextSet.contains(hit.id)) {
        nextSet.remove(hit.id);
      } else {
        nextSet.add(hit.id);
      }
    } else {
      nextSet
        ..clear()
        ..add(hit.id);
    }
    state = state.copyWith(
      selectedBlockId: hit.id,
      selectedBlockIds: nextSet,
      revision: state.revision + 1,
    );
  }

  BlockNode? hitNodeAt(Offset worldPos) => _hitTest(worldPos);

  void selectInRect(Rect worldRect, {bool append = false}) {
    final hits = allBlocks()
        .where((n) => _nodeRect(n).overlaps(worldRect))
        .map((n) => n.id)
        .toSet();
    final next = append ? <String>{...state.selectedBlockIds, ...hits} : hits;
    state = state.copyWith(
      selectedBlockId: next.isEmpty ? null : next.first,
      selectedBlockIds: next,
      revision: state.revision + 1,
    );
  }

  void deleteSelected() {
    final ids = state.selectedBlockIds.isNotEmpty
        ? state.selectedBlockIds.toList(growable: false)
        : (state.selectedBlockId == null
              ? const <String>[]
              : <String>[state.selectedBlockId!]);
    if (ids.isEmpty) return;
    _pushUndoSnapshot();
    for (final id in ids) {
      purgeSelectedNode(id);
    }
    state = state.copyWith(clearSelected: true, revision: state.revision + 1);
  }

  void purgeSelectedNode(String targetId) {
    final target = findById(targetId);
    if (target == null) return;

    for (var i = 0; i < state.roots.length; i++) {
      final root = state.roots[i];
      if (root.id != targetId) continue;

      if (root.type == BlockType.eventGreenFlag) {
        final updated = [...state.roots]..removeAt(i);
        state = state.copyWith(roots: updated, clearSelected: true);
        _relayoutAll();
        _touch();
        return;
      }

      final successor = _successorAfterDeleting(target);
      if (successor != null) {
        successor.position = root.position;
        final updated = [...state.roots]..[i] = successor;
        state = state.copyWith(roots: updated, clearSelected: true);
      } else {
        final updated = [...state.roots]..removeAt(i);
        state = state.copyWith(roots: updated, clearSelected: true);
      }

      _relayoutAll();
      _touch();
      return;
    }

    if (_healDeleteInChain(state.roots, target)) {
      _relayoutAll();
      state = state.copyWith(clearSelected: true, revision: state.revision + 1);
    }
  }

  BlockNode? findById(String id) {
    for (final root in state.roots) {
      for (final node in _walk(root)) {
        if (node.id == id) return node;
      }
    }
    return null;
  }

  String? contextTableForNode(String nodeId) {
    for (final root in state.roots) {
      final table = _contextTableInChain(root, nodeId, null);
      if (table != null) return table;
    }
    return null;
  }

  String? contextTableBeforeNode(String nodeId) {
    for (final root in state.roots) {
      final table = _contextTableBeforeInChain(root, nodeId, null);
      if (table != null) return table;
    }
    return null;
  }

  List<BlockNode> allBlocks() =>
      state.roots.expand((root) => _walk(root)).toList(growable: false);

  double blockHeight(BlockNode node) {
    if (node is ControlBlock) {
      final innerHeight = max(cInnerMin, _childrenChainHeight(node));
      return cUpperBar + innerHeight + cLowerBar;
    }
    final raw = node.inputs['__height'];
    final renderedHeight = raw is num ? raw.toDouble() : null;
    return max(baseHeightForBlock(node), renderedHeight ?? 0);
  }

  double nodeWidth(BlockNode node) {
    final raw = node.inputs['__width'];
    final ownWidth = raw is num
        ? raw.toDouble().clamp(blockWidth, 1100).toDouble()
        : blockWidth;
    if (node is! ControlBlock) return ownWidth;
    return max(ownWidth, _maxChildWidth(node) + childIndent + 20);
  }

  void setRenderWidth(BlockNode node, double width) {
    final clamped = width.clamp(blockWidth, 1100).toDouble();
    final old = (node.inputs['__width'] as num?)?.toDouble();
    if (old != null && (old - clamped).abs() < 0.5) return;
    node.inputs['__width'] = clamped;
  }

  void setRenderMetrics(
    BlockNode node, {
    required double width,
    double? height,
  }) {
    final clampedWidth = width.clamp(blockWidth, 1100).toDouble();
    final oldWidth = (node.inputs['__width'] as num?)?.toDouble();
    if (oldWidth == null || (oldWidth - clampedWidth).abs() >= 0.5) {
      node.inputs['__width'] = clampedWidth;
    }
    if (height == null || node is ControlBlock) return;
    final clampedHeight = height
        .clamp(baseHeightForBlock(node), 140)
        .toDouble();
    final oldHeight = (node.inputs['__height'] as num?)?.toDouble();
    if (oldHeight == null || (oldHeight - clampedHeight).abs() >= 0.5) {
      node.inputs['__height'] = clampedHeight;
    }
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (_undoStack.isEmpty) return;
    final current = toJsonString();
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _applySerializedWorkspace(previous);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final current = toJsonString();
    final next = _redoStack.removeLast();
    _undoStack.add(current);
    _applySerializedWorkspace(next);
  }

  void _pushUndoSnapshot() {
    final snap = toJsonString();
    if (_undoStack.isNotEmpty && _undoStack.last == snap) return;
    _undoStack.add(snap);
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _pushDragUndoSnapshotIfNeeded() {
    final snap = _dragStartSnapshot;
    if (snap == null || !_dragChanged) {
      _dragStartSnapshot = null;
      _dragChanged = false;
      return;
    }
    if (_undoStack.isEmpty || _undoStack.last != snap) {
      _undoStack.add(snap);
      if (_undoStack.length > _historyLimit) {
        _undoStack.removeAt(0);
      }
    }
    _redoStack.clear();
    _dragStartSnapshot = null;
    _dragChanged = false;
  }

  void _applySerializedWorkspace(String source) {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final rootsRaw = (decoded['roots'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final roots = rootsRaw.map(BlockNode.fromJson).toList(growable: false);
    final panRaw =
        decoded['pan'] as Map<String, dynamic>? ?? <String, dynamic>{};
    state = state.copyWith(
      roots: roots,
      scale: (decoded['scale'] as num?)?.toDouble() ?? 1,
      pan: Offset(
        (panRaw['dx'] as num?)?.toDouble() ?? 0,
        (panRaw['dy'] as num?)?.toDouble() ?? 0,
      ),
      clearDrag: true,
      clearHighlight: true,
      clearSelected: true,
    );
    _relayoutAll();
    _touch();
  }

  Iterable<BlockNode> _walk(BlockNode node, [Set<String>? visited]) sync* {
    final seen = visited ?? <String>{};
    if (!seen.add(node.id)) return;
    yield node;

    for (final childHead in node.children) {
      yield* _walk(childHead, seen);
    }

    if (node.next != null) {
      yield* _walk(node.next!, seen);
    }
    seen.remove(node.id);
  }

  BlockNode _createNode(BlockType type, Offset worldPos) {
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(9000)}';
    switch (type) {
      case BlockType.sqlSelect:
        return OperatorBlock(
            id: 'select_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'columns': '*',
            'table': 'table_name',
            'separate_from': false,
          });
      case BlockType.sqlColumn:
        return OperatorBlock(
          id: 'col_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['column'] = '*';
      case BlockType.sqlText:
        return OperatorBlock(
          id: 'text_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['text'] = 'Text';
      case BlockType.sqlCount:
        return OperatorBlock(
          id: 'count_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs.addAll(<String, dynamic>{'expr': '*', 'column': '*'});
      case BlockType.sqlSum:
      case BlockType.sqlAvg:
      case BlockType.sqlMin:
      case BlockType.sqlMax:
        return OperatorBlock(
            id: 'aggregate_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'expr': 'amount',
            'column': 'amount',
          });
      case BlockType.sqlFrom:
        return OperatorBlock(
          id: 'from_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['table'] = 'table_name';
      case BlockType.sqlWhere:
        return MotionBlock(
          id: 'where_$suffix',
          position: worldPos,
          motionType: BlockType.sqlWhere,
          inputs: <String, dynamic>{
            'column': 'id',
            'operator': '=',
            'value': '1',
            'predicate': 'id = 1',
          },
        );
      case BlockType.sqlJoin:
      case BlockType.sqlInnerJoin:
      case BlockType.sqlLeftJoin:
      case BlockType.sqlRightJoin:
      case BlockType.sqlFullJoin:
      case BlockType.sqlCrossJoin:
      case BlockType.sqlSelfJoin:
      case BlockType.sqlNaturalJoin:
        final joinType = switch (type) {
          BlockType.sqlLeftJoin => 'LEFT',
          BlockType.sqlRightJoin => 'RIGHT',
          BlockType.sqlFullJoin => 'FULL',
          BlockType.sqlCrossJoin => 'CROSS',
          BlockType.sqlNaturalJoin => 'NATURAL',
          BlockType.sqlSelfJoin => 'SELF',
          _ => 'INNER',
        };
        return OperatorBlock(
            id: 'join_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'table': 'table_name',
            'on': '1 = 1',
            'left_column': 'id',
            'operator': '=',
            'right_column': 'id',
            'join_type': joinType,
          });
      case BlockType.sqlGroupBy:
        return OperatorBlock(
          id: 'group_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs.addAll(<String, dynamic>{'expr': 'id', 'column': 'id'});
      case BlockType.sqlHaving:
        return OperatorBlock(
            id: 'having_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'aggregate': 'COUNT',
            'column': '*',
            'operator': '>',
            'value': '0',
            'predicate': 'COUNT(*) > 0',
          });
      case BlockType.sqlOrderBy:
        return MotionBlock(
          id: 'order_$suffix',
          position: worldPos,
          motionType: BlockType.sqlOrderBy,
          inputs: <String, dynamic>{'expr': 'id DESC'},
        );
      case BlockType.sqlInsert:
        return OperatorBlock(
            id: 'insert_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'table': 'table_name',
            'values': '',
          });
      case BlockType.sqlUpdate:
        return OperatorBlock(
            id: 'update_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'table': 'table_name',
            'set': 'col = val',
            'column': 'column_name',
            'value': 'value',
            'where_column': 'id',
            'operator': '=',
            'where_value': '1',
          });
      case BlockType.sqlDelete:
        return OperatorBlock(
            id: 'delete_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'table': 'table_name',
            'where_column': 'id',
            'operator': '=',
            'where_value': '1',
          });
      case BlockType.sqlCreateTable:
      case BlockType.sqlAlterTable:
      case BlockType.sqlTruncate:
      case BlockType.sqlGrant:
      case BlockType.sqlRevoke:
      case BlockType.sqlUnion:
      case BlockType.sqlIntersect:
      case BlockType.sqlExcept:
      case BlockType.sqlSubqueryIn:
      case BlockType.sqlSubqueryAny:
      case BlockType.sqlSubqueryAll:
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
      case BlockType.sqlCommit:
      case BlockType.sqlRollback:
      case BlockType.sqlSavepoint:
      case BlockType.sqlRollbackToSavepoint:
      case BlockType.sqlSetTransaction:
        return OperatorBlock(
            id: 'create_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'table': 'new_table',
            'definition': 'id INTEGER PRIMARY KEY',
            'condition_column': 'id',
            'operator': '=',
            'condition_value': '1',
            'when': 'id = 1',
            'cond': 'id = 1',
            'result': "'yes'",
            'default': "'no'",
            'value': "'yes'",
          });
      case BlockType.sqlDropTable:
        return OperatorBlock(
          id: 'drop_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['table'] = 'table_name';
      case BlockType.sqlLoop:
        return ControlBlock(
          id: 'loop_$suffix',
          position: worldPos,
          controlType: BlockType.sqlLoop,
        );
      case BlockType.eventGreenFlag:
        return EventBlock(id: 'event_$suffix', position: worldPos);
      case BlockType.motionMove:
        return MotionBlock(
          id: 'move_$suffix',
          position: worldPos,
          motionType: type,
          inputs: <String, dynamic>{'steps': 10},
        );
      case BlockType.motionTurn:
        return MotionBlock(
          id: 'turn_$suffix',
          position: worldPos,
          motionType: type,
          inputs: <String, dynamic>{'degrees': 15},
        );
      case BlockType.controlRepeat:
        return ControlBlock(
          id: 'repeat_$suffix',
          position: worldPos,
          controlType: type,
          inputs: <String, dynamic>{'times': 10},
        );
      case BlockType.controlForever:
        return ControlBlock(
          id: 'forever_$suffix',
          position: worldPos,
          controlType: type,
        );
      case BlockType.operatorAdd:
        return OperatorBlock(
          id: 'op_$suffix',
          position: worldPos,
          operatorType: type,
        );
      case BlockType.variableSet:
        return VariableBlock(id: 'var_$suffix', position: worldPos);
    }
  }

  BlockNode? _hitTest(Offset worldPos) {
    final blocks = allBlocks().toList().reversed;
    for (final block in blocks) {
      final rect = _nodeRect(block);
      if (rect.contains(worldPos)) return block;
    }
    return null;
  }

  _SnapCandidate? _findBestSnap(
    BlockNode dragged, {
    required Set<String> excludedIds,
  }) {
    _SnapCandidate? best;
    final draggedTop = _topNotchPoint(dragged);
    final draggedBottom = _bottomTabPoint(dragged);

    for (final slot in _buildSlotTargets(excludedIds: excludedIds)) {
      if (!_canSnap(dragged, slot.target, slot.zone)) continue;
      final anchor = switch (slot.zone) {
        SnapZone.bottomOuter => draggedBottom,
        _ => draggedTop,
      };
      final inflated = slot.rect.inflate(snapDistance);
      if (!inflated.contains(anchor)) continue;
      final distance = (slot.anchor - anchor).distance;
      if (distance < snapDistance &&
          (best == null || distance < best.distance)) {
        best = _SnapCandidate(slot.target, slot.zone, distance);
      }
    }

    return best;
  }

  _SnapCandidate? _findBestRejectedSnap(
    BlockNode dragged, {
    required Set<String> excludedIds,
  }) {
    _SnapCandidate? best;
    final draggedTop = _topNotchPoint(dragged);
    final draggedBottom = _bottomTabPoint(dragged);

    for (final slot in _buildSlotTargets(excludedIds: excludedIds)) {
      if (_canSnap(dragged, slot.target, slot.zone)) continue;
      final anchor = switch (slot.zone) {
        SnapZone.bottomOuter => draggedBottom,
        _ => draggedTop,
      };
      final inflated = slot.rect.inflate(snapDistance);
      if (!inflated.contains(anchor)) continue;
      final distance = (slot.anchor - anchor).distance;
      if (distance < snapDistance &&
          (best == null || distance < best.distance)) {
        best = _SnapCandidate(slot.target, slot.zone, distance);
      }
    }

    return best;
  }

  bool _canSnap(BlockNode dragged, BlockNode target, SnapZone zone) {
    if (_subTreeIds(dragged).contains(target.id)) return false;
    if (dragged.type == BlockType.eventGreenFlag) {
      return false;
    }
    if (target.type == BlockType.eventGreenFlag &&
        zone == SnapZone.bottomOuter) {
      return false;
    }
    if (zone == SnapZone.topOuter) {
      if (!hasBottomConnector(target) || !hasTopConnector(dragged)) {
        return false;
      }
      if (!_canConnectSequentially(target, dragged)) return false;
      final successor = target.next;
      return successor == null ||
          _canConnectSequentially(_chainTail(dragged), successor);
    }
    if (zone == SnapZone.bottomOuter) {
      if (!hasBottomConnector(dragged) || !hasTopConnector(target)) {
        return false;
      }
      if (!_canConnectSequentially(_chainTail(dragged), target)) return false;
      final predecessor = _sequentialPredecessor(target);
      if (predecessor == null) {
        return !isSqlChainType(target.type);
      }
      return _canConnectSequentially(predecessor, dragged);
    }
    return target is ControlBlock;
  }

  bool _canConnectSequentially(BlockNode previous, BlockNode next) {
    if (previous.inputs.containsKey(r'$nodeqlPluginBlock') ||
        next.inputs.containsKey(r'$nodeqlPluginBlock')) {
      return true;
    }
    if (previous.type == BlockType.eventGreenFlag) {
      return isStatementType(next.type) ||
          blockVisualKindForType(next.type) == BlockVisualKind.terminal;
    }
    if (isSqlChainType(previous.type) || isSqlChainType(next.type)) {
      return canFollowInSqlChain(previous.type, next.type);
    }
    return true;
  }

  BlockNode? _sequentialPredecessor(BlockNode target) {
    for (final root in state.roots) {
      final predecessor = _predecessorInNode(root, target);
      if (predecessor != null) return predecessor;
    }
    return null;
  }

  BlockNode? _predecessorInNode(
    BlockNode current,
    BlockNode target, [
    Set<String>? visited,
  ]) {
    final seen = visited ?? <String>{};
    if (!seen.add(current.id)) return null;
    if (current.next?.id == target.id) return current;
    for (final child in current.children) {
      if (child.id == target.id) return current;
      final nested = _predecessorInNode(child, target, seen);
      if (nested != null) return nested;
    }
    return current.next == null
        ? null
        : _predecessorInNode(current.next!, target, seen);
  }

  List<_SlotTarget> _buildSlotTargets({required Set<String> excludedIds}) {
    final slots = <_SlotTarget>[];
    for (final target in allBlocks()) {
      if (excludedIds.contains(target.id)) continue;
      if (hasBottomConnector(target)) {
        slots.add(
          _SlotTarget(
            target: target,
            zone: SnapZone.topOuter,
            anchor: _bottomTabPoint(target),
            rect: Rect.fromCenter(
              center: _bottomTabPoint(target),
              width: 56,
              height: 28,
            ),
          ),
        );
      }
      if (hasTopConnector(target)) {
        slots.add(
          _SlotTarget(
            target: target,
            zone: SnapZone.bottomOuter,
            anchor: _topNotchPoint(target),
            rect: Rect.fromCenter(
              center: _topNotchPoint(target),
              width: 56,
              height: 28,
            ),
          ),
        );
      }

      if (target is! ControlBlock) continue;
      final innerTopAnchor = _innerMouthEntryPoint(target);
      slots.add(
        _SlotTarget(
          target: target,
          zone: SnapZone.innerTop,
          anchor: innerTopAnchor,
          rect: Rect.fromLTWH(
            target.position.dx + childIndent,
            target.position.dy + cUpperBar,
            max(150, nodeWidth(target) - childIndent - 12),
            max(30, _childrenChainHeight(target)),
          ),
        ),
      );

      final tail = _lastNestedTail(target);
      if (tail != null) {
        final innerBottomAnchor = _bottomTabPoint(tail);
        slots.add(
          _SlotTarget(
            target: target,
            zone: SnapZone.innerBottom,
            anchor: innerBottomAnchor,
            rect: Rect.fromCenter(
              center: innerBottomAnchor,
              width: 56,
              height: 28,
            ),
          ),
        );
      }
    }
    return slots;
  }

  void _insertBySnap(BlockNode dragged, BlockNode target, SnapZone zone) {
    if (_subTreeIds(dragged).contains(target.id)) return;
    _detachNode(dragged, preserveSubTree: true, healParent: false);

    if (zone == SnapZone.topOuter) {
      final oldNext = target.next;
      target.next = dragged;
      if (oldNext != null && !_subTreeIds(dragged).contains(oldNext.id)) {
        _attachAfterTail(dragged, oldNext);
      }
      dragged.position = Offset(
        target.position.dx,
        target.position.dy + blockHeight(target),
      );
      _layoutNodeSubTree(dragged);
      state = state.copyWith(
        roots: state.roots.where((r) => r.id != dragged.id).toList(),
      );
      return;
    }

    if (zone == SnapZone.bottomOuter) {
      _insertBefore(target, dragged);
      return;
    }

    if (target is ControlBlock && zone == SnapZone.innerTop) {
      if (target.children.isEmpty) {
        target.children = <BlockNode>[dragged];
      } else {
        final existing = target.children.first;
        if (!_subTreeIds(dragged).contains(existing.id)) {
          _attachAfterTail(dragged, existing);
        }
        target.children[0] = dragged;
      }
      dragged.position = _innerMouthEntryPoint(target);
      _layoutNodeSubTree(dragged);
      state = state.copyWith(
        roots: state.roots.where((r) => r.id != dragged.id).toList(),
      );
      return;
    }

    if (target is ControlBlock && zone == SnapZone.innerBottom) {
      if (target.children.isEmpty) {
        target.children = <BlockNode>[dragged];
      } else {
        final tail = _lastNestedTail(target);
        if (tail != null) {
          tail.next = dragged;
        }
      }
      _layoutNodeSubTree(target);
      state = state.copyWith(
        roots: state.roots.where((r) => r.id != dragged.id).toList(),
      );
    }
  }

  void _insertBefore(BlockNode target, BlockNode dragged) {
    for (var i = 0; i < state.roots.length; i++) {
      final root = state.roots[i];
      if (root.id != target.id) continue;
      if (_subTreeIds(dragged).contains(root.id)) return;
      _attachAfterTail(dragged, root);
      dragged.position = root.position;
      final updated = [...state.roots]..[i] = dragged;
      state = state.copyWith(
        roots: updated.where((r) => r.id != target.id || r == dragged).toList(),
      );
      _layoutNodeSubTree(dragged);
      return;
    }

    for (final root in state.roots) {
      if (_insertBeforeInNode(root, target, dragged)) {
        _layoutNodeSubTree(root);
        state = state.copyWith(
          roots: state.roots.where((r) => r.id != dragged.id).toList(),
        );
        return;
      }
    }
  }

  bool _insertBeforeInNode(
    BlockNode current,
    BlockNode target,
    BlockNode dragged, [
    Set<String>? visited,
  ]) {
    final seen = visited ?? <String>{};
    if (!seen.add(current.id)) return false;
    if (current.next?.id == target.id) {
      current.next = dragged;
      if (!_subTreeIds(dragged).contains(target.id)) {
        _attachAfterTail(dragged, target);
      }
      dragged.position = target.position;
      return true;
    }

    for (var i = 0; i < current.children.length; i++) {
      final head = current.children[i];
      if (head.id == target.id) {
        if (_subTreeIds(dragged).contains(head.id)) return false;
        _attachAfterTail(dragged, head);
        dragged.position = head.position;
        current.children[i] = dragged;
        return true;
      }
      if (_insertBeforeInNode(head, target, dragged, seen)) return true;
    }

    if (current.next != null) {
      return _insertBeforeInNode(current.next!, target, dragged, seen);
    }

    return false;
  }

  Offset _topNotchPoint(BlockNode node) =>
      Offset(node.position.dx + 48, node.position.dy);

  Offset _bottomTabPoint(BlockNode node) =>
      Offset(node.position.dx + 48, node.position.dy + blockHeight(node));

  Offset _innerMouthEntryPoint(ControlBlock node) =>
      Offset(node.position.dx + childIndent, node.position.dy + cUpperBar);

  Rect _nodeRect(BlockNode node) {
    return Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      nodeWidth(node),
      blockHeight(node),
    );
  }

  void _detachNode(
    BlockNode node, {
    required bool preserveSubTree,
    required bool healParent,
  }) {
    final roots = <BlockNode>[];

    for (final root in state.roots) {
      if (root.id == node.id) {
        if (healParent &&
            root.next != null &&
            root.type != BlockType.eventGreenFlag) {
          roots.add(root.next!);
        }
        continue;
      }

      _detachFromTree(
        root,
        node,
        preserveSubTree: preserveSubTree,
        healParent: healParent,
      );
      roots.add(root);
    }

    if (!preserveSubTree) node.next = null;
    state = state.copyWith(roots: roots);
  }

  void _detachToRootForDragging(
    BlockNode node, {
    required bool preserveSubTree,
  }) {
    final alreadyRoot = state.roots.any((root) => root.id == node.id);
    if (alreadyRoot) return;

    _detachNode(node, preserveSubTree: preserveSubTree, healParent: false);
    state = state.copyWith(roots: <BlockNode>[...state.roots, node]);
  }

  void _deleteSingleNode(BlockNode node) {
    _detachNode(node, preserveSubTree: false, healParent: true);
    state = state.copyWith(
      roots: state.roots.where((r) => r.id != node.id).toList(),
    );
  }

  bool _detachFromTree(
    BlockNode current,
    BlockNode target, {
    required bool preserveSubTree,
    required bool healParent,
    Set<String>? visited,
  }) {
    final seen = visited ?? <String>{};
    if (!seen.add(current.id)) return false;
    if (current.next?.id == target.id) {
      current.next = healParent ? target.next : null;
      if (!preserveSubTree) target.next = null;
      return true;
    }

    for (var i = 0; i < current.children.length; i++) {
      final head = current.children[i];
      if (head.id == target.id) {
        if (healParent) {
          current.children[i] = target.next ?? head;
          if (target.next == null) current.children.removeAt(i);
        } else {
          current.children.removeAt(i);
        }
        if (!preserveSubTree) target.next = null;
        return true;
      }

      if (_detachFromTree(
        head,
        target,
        preserveSubTree: preserveSubTree,
        healParent: healParent,
        visited: seen,
      )) {
        return true;
      }
    }

    if (current.next != null) {
      return _detachFromTree(
        current.next!,
        target,
        preserveSubTree: preserveSubTree,
        healParent: healParent,
        visited: seen,
      );
    }

    return false;
  }

  bool _healDeleteInChain(List<BlockNode> roots, BlockNode target) {
    for (final root in roots) {
      if (_healDeleteInNode(root, target)) return true;
    }
    return false;
  }

  bool _healDeleteInNode(BlockNode current, BlockNode target) {
    if (current.next?.id == target.id) {
      final successor = _successorAfterDeleting(target);
      if (successor != null) successor.position = target.position;
      current.next = successor;
      if (successor != null) {
        _shiftSequentialChain(successor, -blockHeight(target));
      }
      return true;
    }

    for (var i = 0; i < current.children.length; i++) {
      final head = current.children[i];
      if (head.id == target.id) {
        final successor = _successorAfterDeleting(target);
        if (successor != null) {
          successor.position = head.position;
          current.children[i] = successor;
          _shiftSequentialChain(successor, -blockHeight(target));
        } else {
          current.children.removeAt(i);
        }
        return true;
      }
      if (_healDeleteInNode(head, target)) return true;
    }

    if (current.next != null) {
      return _healDeleteInNode(current.next!, target);
    }

    return false;
  }

  BlockNode? _successorAfterDeleting(BlockNode target) {
    if (target is ControlBlock && target.children.isNotEmpty) {
      final innerHead = target.children.first;
      final innerTail = _chainTail(innerHead);
      innerTail.next = target.next;
      return innerHead;
    }
    return target.next;
  }

  BlockNode _chainTail(BlockNode head) {
    BlockNode current = head;
    final visited = <String>{current.id};
    while (current.next != null && visited.add(current.next!.id)) {
      current = current.next!;
    }
    return current;
  }

  void _attachAfterTail(BlockNode head, BlockNode next) {
    if (_subTreeIds(head).contains(next.id)) return;
    _chainTail(head).next = next;
  }

  BlockNode? _lastNestedTail(ControlBlock block) {
    if (block.children.isEmpty) return null;
    BlockNode? tail;
    for (final head in block.children) {
      tail = _chainTail(head);
    }
    return tail;
  }

  double _childrenChainHeight(ControlBlock block) {
    if (block.children.isEmpty) return 0;
    double total = 0;
    for (final head in block.children) {
      total += _verticalChainHeight(head);
    }
    return total;
  }

  double _verticalChainHeight(BlockNode head) {
    double total = 0;
    BlockNode? current = head;
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      total += blockHeight(current);
      current = current.next;
    }
    return total;
  }

  double _maxChildWidth(ControlBlock block) {
    double widest = blockWidth;
    for (final head in block.children) {
      BlockNode? current = head;
      final visited = <String>{};
      while (current != null && visited.add(current.id)) {
        widest = max(widest, nodeWidth(current));
        current = current.next;
      }
    }
    return widest;
  }

  Set<String> _subTreeIds(BlockNode root) {
    return _walk(root).map((n) => n.id).toSet();
  }

  void _propagateTableSelection(BlockNode node, String table) {
    BlockNode? current = node;
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      if (current.type == BlockType.sqlSelect ||
          current.type == BlockType.sqlFrom ||
          current.type == BlockType.sqlWhere ||
          current.type == BlockType.sqlOrderBy ||
          current.type == BlockType.sqlGroupBy ||
          current.type == BlockType.sqlHaving) {
        current.inputs['table'] = table;
      }
      if (current.type == BlockType.eventGreenFlag) break;
      current = current.next;
    }
  }

  String? _contextTableInChain(
    BlockNode current,
    String targetId,
    String? lastTable, [
    Set<String>? visited,
  ]) {
    final seen = visited ?? <String>{};
    String? activeTable = _tableFromNode(current) ?? lastTable;
    BlockNode? cursor = current;
    while (cursor != null && seen.add(cursor.id)) {
      activeTable = _tableFromNode(cursor) ?? activeTable;
      if (cursor.id == targetId) {
        if (activeTable != null) return activeTable;
        BlockNode? lookahead = cursor.next;
        final lookaheadSeen = <String>{...seen};
        while (lookahead != null && lookaheadSeen.add(lookahead.id)) {
          final ahead = _tableFromNode(lookahead);
          if (ahead != null) return ahead;
          lookahead = lookahead.next;
        }
      }
      for (final child in cursor.children) {
        final childResult = _contextTableInChain(
          child,
          targetId,
          activeTable,
          seen,
        );
        if (childResult != null) return childResult;
      }
      cursor = cursor.next;
    }
    return null;
  }

  String? _contextTableBeforeInChain(
    BlockNode current,
    String targetId,
    String? lastTable, [
    Set<String>? visited,
  ]) {
    final seen = visited ?? <String>{};
    String? activeTable = lastTable;
    BlockNode? cursor = current;
    while (cursor != null && seen.add(cursor.id)) {
      if (cursor.id == targetId) return activeTable;
      activeTable = _tableFromNode(cursor) ?? activeTable;
      for (final child in cursor.children) {
        final childResult = _contextTableBeforeInChain(
          child,
          targetId,
          activeTable,
          seen,
        );
        if (childResult != null) return childResult;
      }
      cursor = cursor.next;
    }
    return null;
  }

  String? _tableFromNode(BlockNode node) {
    final table = (node.inputs['table'] as String?)?.trim();
    if (table != null &&
        table.isNotEmpty &&
        table != 'table_name' &&
        table != 'new_table') {
      return table;
    }
    final tableName = (node.inputs['table_name'] as String?)?.trim();
    if (tableName != null &&
        tableName.isNotEmpty &&
        tableName != 'table_name' &&
        tableName != 'new_table') {
      return tableName;
    }
    return null;
  }

  void _layoutNodeSubTree(BlockNode root, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(root.id)) return;
    if (root is ControlBlock) {
      var y = root.position.dy + cUpperBar;
      for (final head in root.children) {
        BlockNode? current = head;
        while (current != null && !seen.contains(current.id)) {
          current.position = Offset(root.position.dx + childIndent, y);
          _layoutNodeSubTree(current, seen);
          y += blockHeight(current);
          current = current.next;
        }
      }
    }

    if (root.next != null) {
      root.next!.position = Offset(
        root.position.dx,
        root.position.dy + blockHeight(root),
      );
      _layoutNodeSubTree(root.next!, seen);
    }
  }

  void _shiftSequentialChain(BlockNode head, double deltaY) {
    BlockNode? current = head;
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      current.position = current.position.translate(0, deltaY);
      current = current.next;
    }
  }

  void _relayoutAll() {
    _breakSequentialCycles();
    for (final root in state.roots) {
      _layoutNodeSubTree(root, <String>{});
    }
  }

  void _breakSequentialCycles() {
    for (final root in state.roots) {
      _breakSequentialCyclesFrom(root, <String>{});
    }
  }

  void _breakSequentialCyclesFrom(BlockNode head, Set<String> ancestors) {
    final seen = <String>{...ancestors};
    BlockNode? current = head;
    while (current != null) {
      if (!seen.add(current.id)) return;
      for (final child in current.children) {
        _breakSequentialCyclesFrom(child, seen);
      }
      final next = current.next;
      if (next == null) return;
      if (seen.contains(next.id)) {
        current.next = null;
        return;
      }
      current = next;
    }
  }

  void _touch() {
    state = state.copyWith(revision: state.revision + 1);
  }

  String toJsonString() {
    final payload = <String, dynamic>{
      'roots': state.roots
          .map((n) => _nodeToJson(n, <String>{}))
          .toList(growable: false),
      'scale': state.scale,
      'pan': <String, double>{'dx': state.pan.dx, 'dy': state.pan.dy},
    };
    return jsonEncode(payload);
  }

  Map<String, dynamic> _nodeToJson(BlockNode node, Set<String> visited) {
    if (!visited.add(node.id)) {
      return <String, dynamic>{
        'kind': node.runtimeType.toString(),
        'id': node.id,
        'type': node.type.name,
        'position': <String, dynamic>{
          'dx': node.position.dx,
          'dy': node.position.dy,
        },
        'children': <dynamic>[],
        'inputs': node.inputs,
      };
    }
    return <String, dynamic>{
      'kind': node.runtimeType.toString(),
      'id': node.id,
      'type': node.type.name,
      'position': <String, dynamic>{
        'dx': node.position.dx,
        'dy': node.position.dy,
      },
      'next': node.next == null ? null : _nodeToJson(node.next!, visited),
      'children': node.children
          .map((child) => _nodeToJson(child, visited))
          .toList(),
      'inputs': node.inputs,
    };
  }

  void loadFromJsonString(String source) {
    _undoStack.clear();
    _redoStack.clear();
    _dragStartSnapshot = null;
    _dragChanged = false;
    _applySerializedWorkspace(source);
  }

  void restorePreviewSnapshot(String source) {
    _dragStartSnapshot = null;
    _dragChanged = false;
    _applySerializedWorkspace(source);
  }

  void resetWithRoot({bool recordUndo = true}) {
    if (recordUndo) _pushUndoSnapshot();
    state = WorkspaceState(
      roots: <BlockNode>[
        EventBlock(id: 'event_root', position: const Offset(120, 120))
          ..inputs['label'] = 'EXECUTE QUERY',
      ],
      scale: 1,
      pan: Offset.zero,
    );
    _touch();
  }
}

class _SnapCandidate {
  const _SnapCandidate(this.target, this.zone, this.distance);

  final BlockNode target;
  final SnapZone zone;
  final double distance;
}

class _SlotTarget {
  const _SlotTarget({
    required this.target,
    required this.zone,
    required this.anchor,
    required this.rect,
  });

  final BlockNode target;
  final SnapZone zone;
  final Offset anchor;
  final Rect rect;
}
