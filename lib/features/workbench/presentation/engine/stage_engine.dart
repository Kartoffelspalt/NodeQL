import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class Sprite {
  const Sprite({
    required this.id,
    required this.x,
    required this.y,
    required this.direction,
    required this.visibility,
    this.costumes = const <String>['default'],
  });

  final String id;
  final double x;
  final double y;
  final double direction;
  final bool visibility;
  final List<String> costumes;

  Sprite copyWith({
    double? x,
    double? y,
    double? direction,
    bool? visibility,
    List<String>? costumes,
  }) {
    return Sprite(
      id: id,
      x: x ?? this.x,
      y: y ?? this.y,
      direction: direction ?? this.direction,
      visibility: visibility ?? this.visibility,
      costumes: costumes ?? this.costumes,
    );
  }
}

class StageRuntimeState {
  const StageRuntimeState({
    required this.sprites,
    required this.activeSpriteId,
    this.running = false,
  });

  final List<Sprite> sprites;
  final String activeSpriteId;
  final bool running;

  StageRuntimeState copyWith({
    List<Sprite>? sprites,
    String? activeSpriteId,
    bool? running,
  }) {
    return StageRuntimeState(
      sprites: sprites ?? this.sprites,
      activeSpriteId: activeSpriteId ?? this.activeSpriteId,
      running: running ?? this.running,
    );
  }
}

final stageRuntimeProvider =
    StateNotifierProvider<StageRuntimeController, StageRuntimeState>(
      (ref) => StageRuntimeController(),
    );

class StageRuntimeController extends StateNotifier<StageRuntimeState> {
  StageRuntimeController()
    : super(
        const StageRuntimeState(
          sprites: <Sprite>[
            Sprite(
              id: 'sprite_1',
              x: 120,
              y: 90,
              direction: 90,
              visibility: true,
            ),
          ],
          activeSpriteId: 'sprite_1',
        ),
      );

  void setRunning(bool value) => state = state.copyWith(running: value);

  void selectSprite(String id) => state = state.copyWith(activeSpriteId: id);

  void moveActive(double steps) {
    final updated = state.sprites.map((sprite) {
      if (sprite.id != state.activeSpriteId) return sprite;
      final radians = sprite.direction * pi / 180;
      final newX = sprite.x + steps * cos(radians);
      final newY = sprite.y + steps * sin(radians);
      return sprite.copyWith(x: newX, y: newY);
    }).toList();

    state = state.copyWith(sprites: updated);
  }

  void turnActive(double degrees) {
    final updated = state.sprites.map((sprite) {
      if (sprite.id != state.activeSpriteId) return sprite;
      return sprite.copyWith(direction: (sprite.direction + degrees) % 360);
    }).toList();

    state = state.copyWith(sprites: updated);
  }
}
