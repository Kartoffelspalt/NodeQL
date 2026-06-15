import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';

void main() {
  test('persists and restores the selected SQL mode', () async {
    final temp = await Directory.systemTemp.createTemp('nodeql_sql_mode_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/sql_mode.json');

    final controller = SqlModeController(storageFile: () async => file);
    await controller.initialize();

    expect(controller.state, SqlAbstractionMode.advanced);

    await controller.setMode(SqlAbstractionMode.simple);

    expect(controller.state, SqlAbstractionMode.simple);
    expect(await file.readAsString(), contains('"mode":"simple"'));

    final restored = SqlModeController(storageFile: () async => file);
    await restored.initialize();

    expect(restored.state, SqlAbstractionMode.simple);
  });

  test('invalid persisted modes keep the advanced fallback', () async {
    final temp = await Directory.systemTemp.createTemp('nodeql_sql_mode_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/sql_mode.json');
    await file.writeAsString('{"mode":"unknown"}');

    final controller = SqlModeController(storageFile: () async => file);
    await controller.initialize();

    expect(controller.state, SqlAbstractionMode.advanced);
  });

  test('an immediate mode change wins over the restored value', () async {
    final temp = await Directory.systemTemp.createTemp('nodeql_sql_mode_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/sql_mode.json');
    await file.writeAsString('{"mode":"simple"}');

    final controller = SqlModeController(storageFile: () async => file);
    await controller.setMode(SqlAbstractionMode.advanced);

    expect(controller.state, SqlAbstractionMode.advanced);
    expect(await file.readAsString(), contains('"mode":"advanced"'));
  });
}
