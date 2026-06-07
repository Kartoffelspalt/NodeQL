import 'dart:convert';
import 'dart:io';

import 'package:nodeql/data/project/default_project_factory.dart';
import 'package:nodeql/domain/models/project_models.dart';
import 'package:nodeql/domain/services/project_repository.dart';

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
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(project.toJson());
    await File(path).writeAsString(encoded);
  }
}
