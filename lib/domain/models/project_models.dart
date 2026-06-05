class ProjectModel {
  const ProjectModel({
    required this.version,
    required this.name,
    required this.stage,
    required this.sprites,
    required this.variables,
  });

  final String version;
  final String name;
  final StageModel stage;
  final List<SpriteModel> sprites;
  final Map<String, Object?> variables;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'name': name,
        'stage': stage.toJson(),
        'sprites': sprites.map((sprite) => sprite.toJson()).toList(),
        'variables': variables,
      };

  factory ProjectModel.fromJson(Map<String, Object?> json) {
    final rawSprites =
        (json['sprites'] as List<Object?>? ?? <Object?>[]).cast<Map<String, Object?>>();
    return ProjectModel(
      version: json['version'] as String? ?? '1.0.0',
      name: json['name'] as String? ?? 'Untitled',
      stage: StageModel.fromJson(json['stage'] as Map<String, Object?>? ?? <String, Object?>{}),
      sprites: rawSprites.map(SpriteModel.fromJson).toList(),
      variables: (json['variables'] as Map<String, Object?>?) ?? <String, Object?>{},
    );
  }
}

class StageModel {
  const StageModel({
    required this.width,
    required this.height,
    required this.backdrop,
  });

  final int width;
  final int height;
  final String backdrop;

  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'height': height,
        'backdrop': backdrop,
      };

  factory StageModel.fromJson(Map<String, Object?> json) => StageModel(
        width: json['width'] as int? ?? 480,
        height: json['height'] as int? ?? 360,
        backdrop: json['backdrop'] as String? ?? 'default',
      );
}

class SpriteModel {
  const SpriteModel({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.visible,
  });

  final String id;
  final String name;
  final double x;
  final double y;
  final bool visible;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'visible': visible,
      };

  factory SpriteModel.fromJson(Map<String, Object?> json) => SpriteModel(
        id: json['id'] as String,
        name: json['name'] as String,
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        visible: json['visible'] as bool? ?? true,
      );
}
