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

  test('the Workshop Admin is linked as a separate repository', () {
    final modules = File('.gitmodules').readAsStringSync();
    expect(modules, contains('path = tools/workshop_admin'));
    expect(
      modules,
      contains('https://github.com/Kartoffelspalt/NodeQL-Workshop-Admin.git'),
    );
  });
}
