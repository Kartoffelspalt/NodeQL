import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public application import graph does not reference the admin UI', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final workbenchSource = File(
      'lib/features/workbench/presentation/workbench_page.dart',
    ).readAsStringSync();

    expect(mainSource, isNot(contains('workshop_admin')));
    expect(mainSource, isNot(contains('learning_path_studio')));
    expect(workbenchSource, isNot(contains('learning_path_studio.dart')));
    expect(workbenchSource, isNot(contains('WorkshopAdminLauncher')));
  });

  test('release workflow only builds the public entry point', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();

    expect(RegExp(r'-t lib/main\.dart').allMatches(workflow), hasLength(3));
    expect(workflow, isNot(contains('tools/workshop_admin')));
    expect(workflow, isNot(contains('workshop_admin_launcher')));
  });

  test('admin is a separate unpublished desktop application', () {
    final pubspec = File(
      'tools/workshop_admin/pubspec.yaml',
    ).readAsStringSync();
    final macConfig = File(
      'tools/workshop_admin/macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();

    expect(pubspec, contains("publish_to: 'none'"));
    expect(pubspec, contains('path: ../..'));
    expect(macConfig, contains('org.nodeql.nodeqlWorkshopAdmin'));
  });
}
