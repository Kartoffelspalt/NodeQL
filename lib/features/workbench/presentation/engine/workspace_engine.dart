import 'dart:math';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scratchql_creater/engine/block/block_node.dart';

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
    Offset? lastPointerGlobal,
    bool clearDrag = false,
    bool clearSelected = false,
    bool clearHighlight = false,
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
              ..next = ControlBlock(
                id: 'forever_1',
                position: const Offset(120, 170),
                controlType: BlockType.controlForever,
                children: <BlockNode>[
                  MotionBlock(
                    id: 'move_1',
                    position: const Offset(135, 210),
                    motionType: BlockType.motionMove,
                    inputs: <String, dynamic>{'steps': 10},
                  ),
                ],
              ),
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

  void addTemplate(
    BlockType type,
    Offset worldPos, {
    Map<String, dynamic>? defaults,
  }) {
    _pushUndoSnapshot();
    final node = _createNode(type, worldPos);
    if (defaults != null && defaults.isNotEmpty) {
      node.inputs.addAll(defaults);
    }
    state = state.copyWith(roots: <BlockNode>[...state.roots, node]);

    final snap = _findBestSnap(node, excludedIds: <String>{node.id});
    if (snap != null) {
      _insertBySnap(node, snap.target, snap.zone);
    }

    _relayoutAll();
    _touch();
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

  void startDrag(Offset worldPos) {
    final hit = _hitTest(worldPos);
    if (hit != null) {
      _dragStartSnapshot = toJsonString();
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
    state = state.copyWith(
      highlightTargetId: snap?.target.id,
      highlightZone: snap?.zone,
    );
  }

  void endDrag({bool deleteDragged = false}) {
    final draggedId = state.draggingId;
    if (draggedId == null) {
      state = state.copyWith(
        clearDrag: true,
        clearHighlight: true,
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
      _pushDragUndoSnapshotIfNeeded();
      _deleteSingleNode(dragged);
    } else if (dragged != null && target != null && zone != null) {
      _pushDragUndoSnapshotIfNeeded();
      _insertBySnap(dragged, target, zone);
    } else {
      _dragStartSnapshot = null;
      _dragChanged = false;
    }

    _relayoutAll();
    state = state.copyWith(
      clearDrag: true,
      clearHighlight: true,
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
    _pushUndoSnapshot();
    final ids = state.selectedBlockIds.isNotEmpty
        ? state.selectedBlockIds.toList(growable: false)
        : (state.selectedBlockId == null
              ? const <String>[]
              : <String>[state.selectedBlockId!]);
    if (ids.isEmpty) return;
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

  List<BlockNode> allBlocks() =>
      state.roots.expand((root) => _walk(root)).toList(growable: false);

  double blockHeight(BlockNode node) {
    if (node is ControlBlock) {
      final innerHeight = max(cInnerMin, _childrenChainHeight(node));
      return cUpperBar + innerHeight + cLowerBar;
    }
    return blockBaseHeight;
  }

  double nodeWidth(BlockNode node) {
    final raw = node.inputs['__width'];
    final ownWidth = raw is num
        ? raw.toDouble().clamp(blockWidth, 900).toDouble()
        : blockWidth;
    if (node is! ControlBlock) return ownWidth;
    return max(ownWidth, _maxChildWidth(node) + childIndent + 20);
  }

  void setRenderWidth(BlockNode node, double width) {
    final clamped = width.clamp(blockWidth, 900).toDouble();
    final old = (node.inputs['__width'] as num?)?.toDouble();
    if (old != null && (old - clamped).abs() < 0.5) return;
    node.inputs['__width'] = clamped;
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

  Iterable<BlockNode> _walk(BlockNode node) sync* {
    yield node;

    for (final childHead in node.children) {
      yield* _walk(childHead);
    }

    if (node.next != null) {
      yield* _walk(node.next!);
    }
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
          });
      case BlockType.sqlColumn:
        return OperatorBlock(
          id: 'col_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['column'] = '*';
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
          inputs: <String, dynamic>{'predicate': '1 = 1'},
        );
      case BlockType.sqlJoin:
      case BlockType.sqlInnerJoin:
      case BlockType.sqlLeftJoin:
      case BlockType.sqlRightJoin:
      case BlockType.sqlFullJoin:
      case BlockType.sqlCrossJoin:
      case BlockType.sqlSelfJoin:
      case BlockType.sqlNaturalJoin:
        return OperatorBlock(
            id: 'join_$suffix',
            position: worldPos,
            operatorType: type,
          )
          ..inputs.addAll(<String, dynamic>{
            'table': 'table_name',
            'on': '1 = 1',
          });
      case BlockType.sqlGroupBy:
      case BlockType.sqlHaving:
        return OperatorBlock(
          id: 'group_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['expr'] = 'id';
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
          });
      case BlockType.sqlDelete:
        return OperatorBlock(
          id: 'delete_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['table'] = 'table_name';
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
          });
      case BlockType.sqlDropTable:
        return OperatorBlock(
          id: 'drop_$suffix',
          position: worldPos,
          operatorType: type,
        )..inputs['table'] = 'table_name';
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
      case BlockType.sqlCase:
      case BlockType.sqlIf:
      case BlockType.sqlAlterTable:
      case BlockType.sqlTruncate:
      case BlockType.sqlGrant:
      case BlockType.sqlRevoke:
      case BlockType.sqlCommit:
      case BlockType.sqlRollback:
      case BlockType.sqlSavepoint:
      case BlockType.sqlRollbackToSavepoint:
        return OperatorBlock(
          id: 'op_$suffix',
          position: worldPos,
          operatorType: type,
        );
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

  List<_SlotTarget> _buildSlotTargets({required Set<String> excludedIds}) {
    final slots = <_SlotTarget>[];
    for (final target in allBlocks()) {
      if (excludedIds.contains(target.id)) continue;
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
    _detachNode(dragged, preserveSubTree: true, healParent: false);

    if (zone == SnapZone.topOuter) {
      final oldNext = target.next;
      target.next = dragged;
      if (oldNext != null) {
        _chainTail(dragged).next = oldNext;
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
        _chainTail(dragged).next = existing;
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
      _chainTail(dragged).next = root;
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
    BlockNode dragged,
  ) {
    if (current.next?.id == target.id) {
      current.next = dragged;
      _chainTail(dragged).next = target;
      dragged.position = target.position;
      return true;
    }

    for (var i = 0; i < current.children.length; i++) {
      final head = current.children[i];
      if (head.id == target.id) {
        _chainTail(dragged).next = head;
        dragged.position = head.position;
        current.children[i] = dragged;
        return true;
      }
      if (_insertBeforeInNode(head, target, dragged)) return true;
    }

    if (current.next != null) {
      return _insertBeforeInNode(current.next!, target, dragged);
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
        if (healParent && root.next != null) roots.add(root.next!);
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
  }) {
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
        _shiftSequentialChain(successor, -blockBaseHeight);
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
          _shiftSequentialChain(successor, -blockBaseHeight);
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
    while (current.next != null) {
      current = current.next!;
    }
    return current;
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
    while (current != null) {
      total += blockHeight(current);
      current = current.next;
    }
    return total;
  }

  double _maxChildWidth(ControlBlock block) {
    double widest = blockWidth;
    for (final head in block.children) {
      BlockNode? current = head;
      while (current != null) {
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
    while (current != null) {
      if (current.type == BlockType.sqlSelect ||
          current.type == BlockType.sqlFrom ||
          current.type == BlockType.sqlWhere ||
          current.type == BlockType.sqlOrderBy ||
          current.type == BlockType.sqlGroupBy ||
          current.type == BlockType.sqlHaving ||
          current.type == BlockType.sqlJoin ||
          current.type == BlockType.sqlInnerJoin ||
          current.type == BlockType.sqlLeftJoin ||
          current.type == BlockType.sqlRightJoin ||
          current.type == BlockType.sqlFullJoin ||
          current.type == BlockType.sqlCrossJoin ||
          current.type == BlockType.sqlNaturalJoin) {
        current.inputs['table'] = table;
      }
      if (current.type == BlockType.eventGreenFlag) break;
      current = current.next;
    }
  }

  String? _contextTableInChain(
    BlockNode current,
    String targetId,
    String? lastTable,
  ) {
    String? activeTable = _tableFromNode(current) ?? lastTable;
    BlockNode? cursor = current;
    while (cursor != null) {
      activeTable = _tableFromNode(cursor) ?? activeTable;
      if (cursor.id == targetId) {
        if (activeTable != null) return activeTable;
        BlockNode? lookahead = cursor.next;
        while (lookahead != null) {
          final ahead = _tableFromNode(lookahead);
          if (ahead != null) return ahead;
          lookahead = lookahead.next;
        }
      }
      for (final child in cursor.children) {
        final childResult = _contextTableInChain(child, targetId, activeTable);
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

  void _layoutNodeSubTree(BlockNode root) {
    if (root is ControlBlock) {
      var y = root.position.dy + cUpperBar;
      for (final head in root.children) {
        BlockNode? current = head;
        var index = 0;
        while (current != null) {
          current.position = Offset(
            root.position.dx + childIndent,
            y + (index * blockBaseHeight),
          );
          _layoutNodeSubTree(current);
          current = current.next;
          index++;
        }
        y += _verticalChainHeight(head);
      }
    }

    if (root.next != null) {
      root.next!.position = Offset(
        root.position.dx,
        root.position.dy + blockHeight(root),
      );
      _layoutNodeSubTree(root.next!);
    }
  }

  void _shiftSequentialChain(BlockNode head, double deltaY) {
    BlockNode? current = head;
    while (current != null) {
      current.position = current.position.translate(0, deltaY);
      current = current.next;
    }
  }

  void _relayoutAll() {
    for (final root in state.roots) {
      _layoutNodeSubTree(root);
    }
  }

  void _touch() {
    state = state.copyWith(revision: state.revision + 1);
  }

  String toJsonString() {
    final payload = <String, dynamic>{
      'roots': state.roots.map((n) => n.toJson()).toList(growable: false),
      'scale': state.scale,
      'pan': <String, double>{'dx': state.pan.dx, 'dy': state.pan.dy},
    };
    return jsonEncode(payload);
  }

  void loadFromJsonString(String source) {
    _undoStack.clear();
    _redoStack.clear();
    _dragStartSnapshot = null;
    _dragChanged = false;
    _applySerializedWorkspace(source);
  }

  void resetWithRoot() {
    _pushUndoSnapshot();
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
