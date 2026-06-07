import 'package:nodeql/domain/models/project_models.dart';

ProjectModel buildDefaultProject() {
  return const ProjectModel(
    version: '1.0.0',
    name: 'NodeQL Project',
    stage: StageModel(width: 480, height: 360, backdrop: 'grid'),
    sprites: <SpriteModel>[
      SpriteModel(id: 'sprite-1', name: 'Actor 1', x: 0, y: 0, visible: true),
    ],
    variables: <String, Object?>{},
  );
}
