import 'dart:math';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScratchCategory {
  motion,
  looks,
  sound,
  events,
  control,
  sensing,
  operators,
  variables,
  myBlocks,
}

class WorkspaceBlock {
  const WorkspaceBlock({
    required this.id,
    required this.type,
    required this.position,
    required this.color,
    required this.label,
    this.isHat = false,
    this.isControl = false,
    this.numberValue = 10,
  });

  final String id;
  final String type;
  final Offset position;
  final Color color;
  final String label;
  final bool isHat;
  final bool isControl;
  final double numberValue;

  WorkspaceBlock copyWith({Offset? position, double? numberValue}) {
    return WorkspaceBlock(
      id: id,
      type: type,
      position: position ?? this.position,
      color: color,
      label: label,
      isHat: isHat,
      isControl: isControl,
      numberValue: numberValue ?? this.numberValue,
    );
  }
}

class WorkbenchState {
  const WorkbenchState({
    required this.activeCategory,
    required this.blocks,
    required this.workspaceScale,
    required this.workspacePan,
    this.snapPreview,
  });

  final ScratchCategory activeCategory;
  final List<WorkspaceBlock> blocks;
  final double workspaceScale;
  final Offset workspacePan;
  final Offset? snapPreview;

  WorkbenchState copyWith({
    ScratchCategory? activeCategory,
    List<WorkspaceBlock>? blocks,
    double? workspaceScale,
    Offset? workspacePan,
    Offset? snapPreview,
    bool clearSnapPreview = false,
  }) {
    return WorkbenchState(
      activeCategory: activeCategory ?? this.activeCategory,
      blocks: blocks ?? this.blocks,
      workspaceScale: workspaceScale ?? this.workspaceScale,
      workspacePan: workspacePan ?? this.workspacePan,
      snapPreview: clearSnapPreview ? null : (snapPreview ?? this.snapPreview),
    );
  }
}

final workbenchStateProvider =
    StateNotifierProvider<WorkbenchController, WorkbenchState>(
      (ref) => WorkbenchController(),
    );

class WorkbenchController extends StateNotifier<WorkbenchState> {
  WorkbenchController()
    : super(
        const WorkbenchState(
          activeCategory: ScratchCategory.motion,
          blocks: <WorkspaceBlock>[],
          workspaceScale: 1,
          workspacePan: Offset.zero,
        ),
      );

  static const _snapThreshold = 24.0;
  static const _blockHeight = 42.0;

  void setActiveCategory(ScratchCategory category) {
    state = state.copyWith(activeCategory: category);
  }

  void setZoom(double next) {
    final clamped = next.clamp(0.6, 1.8);
    state = state.copyWith(workspaceScale: clamped);
  }

  void panBy(Offset delta) {
    state = state.copyWith(workspacePan: state.workspacePan + delta);
  }

  void clearSnapPreview() {
    state = state.copyWith(clearSnapPreview: true);
  }

  void addBlock(WorkspaceBlock block) {
    final snapped = _findSnapPosition(block.id, block.position);
    final next = block.copyWith(position: snapped ?? block.position);
    state = state.copyWith(
      blocks: <WorkspaceBlock>[...state.blocks, next],
      clearSnapPreview: true,
    );
  }

  void moveBlock(String id, Offset position, {bool previewOnly = false}) {
    final snapped = _findSnapPosition(id, position);
    if (previewOnly) {
      state = state.copyWith(snapPreview: snapped);
      return;
    }

    final updated = state.blocks
        .map(
          (block) => block.id == id
              ? block.copyWith(position: snapped ?? position)
              : block,
        )
        .toList();
    state = state.copyWith(blocks: updated, clearSnapPreview: true);
  }

  Offset? _findSnapPosition(String movingId, Offset proposed) {
    WorkspaceBlock? best;
    var bestDistance = double.infinity;
    for (final block in state.blocks) {
      if (block.id == movingId) continue;
      final expected = Offset(
        block.position.dx,
        block.position.dy + _blockHeight,
      );
      final distance = (expected - proposed).distance;
      if (distance < _snapThreshold && distance < bestDistance) {
        bestDistance = distance;
        best = block;
      }
    }

    if (best == null) return null;
    return Offset(best.position.dx, best.position.dy + _blockHeight);
  }

  String nextId() =>
      'b_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  void setBlockNumberValue(String id, double value) {
    state = state.copyWith(
      blocks: state.blocks
          .map(
            (block) =>
                block.id == id ? block.copyWith(numberValue: value) : block,
          )
          .toList(),
    );
  }
}
