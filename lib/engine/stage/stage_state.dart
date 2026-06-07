import 'dart:math';

class StageSpriteState {
  const StageSpriteState({
    required this.id,
    required this.x,
    required this.y,
    this.direction = 90,
    this.visible = true,
  });

  final String id;
  final double x;
  final double y;
  final double direction;
  final bool visible;

  StageSpriteState copyWith({
    double? x,
    double? y,
    double? direction,
    bool? visible,
  }) {
    return StageSpriteState(
      id: id,
      x: x ?? this.x,
      y: y ?? this.y,
      direction: direction ?? this.direction,
      visible: visible ?? this.visible,
    );
  }

  StageSpriteState moved(double steps) {
    final angle = direction * pi / 180;
    return copyWith(x: x + cos(angle) * steps, y: y - sin(angle) * steps);
  }

  StageSpriteState turned(double degrees) =>
      copyWith(direction: (direction + degrees) % 360);
}
