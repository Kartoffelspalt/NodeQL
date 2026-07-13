import 'dart:convert';

const int currentProjectFileVersion = 2;
const String currentProjectFileFormat = 'nodeql_project_v2';

enum ProjectFileUpgradeKind { current, upgradeAvailable, unsupported }

class ProjectFileInspection {
  const ProjectFileInspection({
    required this.kind,
    required this.sourceFormat,
    this.sourceVersion,
    this.message,
  });

  final ProjectFileUpgradeKind kind;
  final String sourceFormat;
  final int? sourceVersion;
  final String? message;

  bool get canUpgrade => kind == ProjectFileUpgradeKind.upgradeAvailable;
}

/// Converts supported historic NodeQL workspace files to the current envelope.
///
/// The service is intentionally pure: the caller decides whether and where a
/// backup is created before it writes the returned JSON back to disk.
class ProjectFileUpgradeService {
  const ProjectFileUpgradeService();

  ProjectFileInspection inspect(String source) {
    final decoded = _decode(source);
    if (decoded == null) {
      return const ProjectFileInspection(
        kind: ProjectFileUpgradeKind.unsupported,
        sourceFormat: 'unknown',
        message: 'The project file is not valid JSON.',
      );
    }

    final format = decoded['format'];
    if (format == currentProjectFileFormat &&
        decoded['version'] == currentProjectFileVersion) {
      return const ProjectFileInspection(
        kind: ProjectFileUpgradeKind.current,
        sourceFormat: currentProjectFileFormat,
        sourceVersion: currentProjectFileVersion,
      );
    }

    if (format == currentProjectFileFormat &&
        decoded['version'] is int &&
        (decoded['version'] as int) > currentProjectFileVersion) {
      return ProjectFileInspection(
        kind: ProjectFileUpgradeKind.unsupported,
        sourceFormat: currentProjectFileFormat,
        sourceVersion: decoded['version'] as int,
        message: 'The project was created with a newer version of NodeQL.',
      );
    }

    if (_isLegacyWorkspace(decoded)) {
      return const ProjectFileInspection(
        kind: ProjectFileUpgradeKind.upgradeAvailable,
        sourceFormat: 'workspace',
        sourceVersion: 1,
      );
    }

    if (_isSupportedLegacyEnvelope(decoded)) {
      return ProjectFileInspection(
        kind: ProjectFileUpgradeKind.upgradeAvailable,
        sourceFormat: '${decoded['format']}',
        sourceVersion: _int(decoded['version']) ?? 1,
      );
    }

    return ProjectFileInspection(
      kind: ProjectFileUpgradeKind.unsupported,
      sourceFormat: '${format ?? 'unknown'}',
      sourceVersion: _int(decoded['version']),
      message: 'This project format is not supported.',
    );
  }

  String upgrade(String source) {
    final decoded = _decode(source);
    if (decoded == null) {
      throw const FormatException('The project file is not valid JSON.');
    }
    final inspection = inspect(source);
    if (!inspection.canUpgrade) {
      throw FormatException(inspection.message ?? 'No upgrade is available.');
    }

    final workspace = _isLegacyWorkspace(decoded)
        ? decoded
        : _map(decoded['workspace']) ?? <String, dynamic>{};
    final runtime = _map(decoded['runtime']) ?? <String, dynamic>{};
    final ui = _map(decoded['ui']) ?? <String, dynamic>{};
    final settings = _map(decoded['settings']) ?? <String, dynamic>{};

    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': currentProjectFileFormat,
      'version': currentProjectFileVersion,
      'workspace': workspace,
      'runtime': runtime,
      'ui': ui,
      'settings': <String, dynamic>{
        'autosaveEnabled': settings['autosaveEnabled'] as bool? ?? true,
      },
    });
  }

  Map<String, dynamic>? _decode(String source) {
    try {
      final decoded = jsonDecode(source);
      return _map(decoded);
    } on FormatException {
      return null;
    }
  }

  bool _isLegacyWorkspace(Map<String, dynamic> json) =>
      json['format'] == null && json['roots'] is List;

  bool _isSupportedLegacyEnvelope(Map<String, dynamic> json) {
    final format = json['format'];
    if (format != 'scratchql_project_v2' &&
        format != 'nodeql_project_v1' &&
        format != 'scratchql_project_v1') {
      return false;
    }
    return _map(json['workspace']) != null;
  }

  Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry('$key', value));
  }

  int? _int(Object? value) => value is int ? value : null;
}
