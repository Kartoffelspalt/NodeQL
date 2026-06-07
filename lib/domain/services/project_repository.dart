import 'package:nodeql/domain/models/project_models.dart';

abstract class ProjectRepository {
  Future<ProjectModel> createEmptyProject();
  Future<ProjectModel> loadProject(String path);
  Future<void> saveProject(String path, ProjectModel project);
}
