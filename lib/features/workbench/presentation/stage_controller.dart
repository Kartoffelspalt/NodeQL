import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scratchql_creater/engine/stage/stage_state.dart';

class StageState {
  const StageState({
    required this.sprites,
    required this.selectedSpriteId,
    this.isRunning = false,
  });

  final List<StageSpriteState> sprites;
  final String selectedSpriteId;
  final bool isRunning;

  StageSpriteState get selected =>
      sprites.firstWhere((sprite) => sprite.id == selectedSpriteId);

  StageState copyWith({
    List<StageSpriteState>? sprites,
    String? selectedSpriteId,
    bool? isRunning,
  }) {
    return StageState(
      sprites: sprites ?? this.sprites,
      selectedSpriteId: selectedSpriteId ?? this.selectedSpriteId,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

final stageControllerProvider =
    StateNotifierProvider<StageController, StageState>((ref) {
  return StageController();
});

class StageController extends StateNotifier<StageState> {
  StageController()
      : super(
          const StageState(
            sprites: <StageSpriteState>[
              StageSpriteState(id: 'sprite-1', x: 120, y: 120),
            ],
            selectedSpriteId: 'sprite-1',
          ),
        );

  void setRunning(bool value) {
    state = state.copyWith(isRunning: value);
  }

  void selectSprite(String id) {
    state = state.copyWith(selectedSpriteId: id);
  }

  void moveSelected(double steps) {
    final updated = state.sprites.map((sprite) {
      if (sprite.id != state.selectedSpriteId) return sprite;
      return sprite.moved(steps);
    }).toList();
    state = state.copyWith(sprites: _clampAll(updated));
  }

  void turnSelected(double degrees) {
    final updated = state.sprites.map((sprite) {
      if (sprite.id != state.selectedSpriteId) return sprite;
      return sprite.turned(degrees);
    }).toList();
    state = state.copyWith(sprites: updated);
  }

  List<StageSpriteState> _clampAll(List<StageSpriteState> sprites) {
    return sprites
        .map(
          (sprite) => sprite.copyWith(
            x: min(315, max(10, sprite.x)),
            y: min(235, max(10, sprite.y)),
          ),
        )
        .toList();
  }
}
