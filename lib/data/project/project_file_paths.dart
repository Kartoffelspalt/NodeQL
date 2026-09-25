import 'package:path/path.dart' as p;

/// Paths stored inside a project file use `/` on every desktop platform.
class ProjectFilePaths {
  const ProjectFilePaths._();

  static String? relativeDatabasePath(
    String databasePath,
    String projectPath, {
    p.Context? context,
  }) {
    final paths = context ?? p.context;
    final projectDirectory = paths.dirname(projectPath);
    if (!paths.isWithin(projectDirectory, databasePath)) return null;
    return paths
        .relative(databasePath, from: projectDirectory)
        .replaceAll('\\', '/');
  }

  static String? resolveDatabasePath(
    String? databasePath,
    String? relativePath,
    String? projectPath, {
    p.Context? context,
  }) {
    if (projectPath == null || relativePath == null || relativePath.isEmpty) {
      return databasePath;
    }
    final paths = context ?? p.context;
    final segments = relativePath.replaceAll('\\', '/').split('/');
    return paths.normalize(
      paths.joinAll([paths.dirname(projectPath), ...segments]),
    );
  }
}
