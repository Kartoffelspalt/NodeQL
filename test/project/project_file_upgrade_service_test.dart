import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/data/project/project_file_upgrade_service.dart';

void main() {
  const service = ProjectFileUpgradeService();

  test('recognizes the current project format', () {
    final inspection = service.inspect(
      jsonEncode(<String, dynamic>{
        'format': currentProjectFileFormat,
        'version': currentProjectFileVersion,
        'workspace': <String, dynamic>{'roots': <dynamic>[]},
      }),
    );

    expect(inspection.kind, ProjectFileUpgradeKind.current);
    expect(inspection.canUpgrade, isFalse);
  });

  test('upgrades a legacy workspace into the current project envelope', () {
    const legacy = '{"roots":[],"scale":1,"pan":{"dx":0,"dy":0}}';

    final inspection = service.inspect(legacy);
    final upgraded =
        jsonDecode(service.upgrade(legacy)) as Map<String, dynamic>;

    expect(inspection.canUpgrade, isTrue);
    expect(upgraded['format'], currentProjectFileFormat);
    expect(upgraded['version'], currentProjectFileVersion);
    expect(upgraded['workspace']['roots'], isEmpty);
    expect(upgraded['settings']['autosaveEnabled'], isTrue);
  });

  test('preserves legacy envelope workspace and autosave setting', () {
    final legacy = jsonEncode(<String, dynamic>{
      'format': 'scratchql_project_v2',
      'version': 2,
      'workspace': <String, dynamic>{
        'roots': <dynamic>['root'],
      },
      'settings': <String, dynamic>{'autosaveEnabled': false},
    });

    final upgraded =
        jsonDecode(service.upgrade(legacy)) as Map<String, dynamic>;

    expect(upgraded['workspace']['roots'], <dynamic>['root']);
    expect(upgraded['settings']['autosaveEnabled'], isFalse);
  });

  test('does not offer an upgrade for project files from a newer version', () {
    final inspection = service.inspect(
      jsonEncode(<String, dynamic>{
        'format': currentProjectFileFormat,
        'version': currentProjectFileVersion + 1,
      }),
    );

    expect(inspection.kind, ProjectFileUpgradeKind.unsupported);
    expect(inspection.canUpgrade, isFalse);
  });

  test('rejects malformed project version values without throwing', () {
    final inspection = service.inspect(
      jsonEncode(<String, dynamic>{
        'format': currentProjectFileFormat,
        'version': 'later',
      }),
    );

    expect(inspection.kind, ProjectFileUpgradeKind.unsupported);
  });
}
