import 'dart:convert';
import 'dart:io';

import 'package:scratchql_creater/data/project/default_project_factory.dart';
import 'package:scratchql_creater/domain/models/project_models.dart';
import 'package:scratchql_creater/domain/services/project_repository.dart';

class JsonProjectRepository implements ProjectRepository {
  @override
  Future<ProjectModel> createEmptyProject() async => buildDefaultProject();

  @override
  Future<ProjectModel> loadProject(String path) async {
    final jsonContent = await File(path).readAsString();
    return ProjectModel.fromJson(
      jsonDecode(jsonContent) as Map<String, Object?>,
    );
  }

  @override
  Future<void> saveProject(String path, ProjectModel project) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(project.toJson());
    await File(path).writeAsString(encoded);
  }
}
