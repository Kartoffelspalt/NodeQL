import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/workbench/presentation/workbench_layout_controller.dart';

void main() {
  test('clamps independently resizable workbench panes', () async {
    final directory = await Directory.systemTemp.createTemp('nodeql_layout');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/layout.json');
    final controller = WorkbenchLayoutController(storageFile: () async => file);
    addTearDown(controller.dispose);

    controller.setPaletteWidth(99);
    controller.setRuntimeWidth(2000);
    controller.setCommandOutputFraction(.01);
    controller.setHighRefreshMode(false);
    controller.setReduceMotion(true);

    expect(controller.state.paletteWidth, 200);
    expect(controller.state.runtimeWidth, 720);
    expect(controller.state.commandOutputFraction, .18);
    expect(controller.state.highRefreshMode, isFalse);
    expect(controller.state.reduceMotion, isTrue);
  });

  test('restores the global desktop pane layout', () async {
    final directory = await Directory.systemTemp.createTemp('nodeql_layout');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/layout.json');
    await file.writeAsString(
      '{"paletteWidth":310,"runtimeWidth":500,"commandOutputFraction":0.6}',
    );
    final controller = WorkbenchLayoutController(storageFile: () async => file);
    addTearDown(controller.dispose);

    await controller.restored;
    expect(controller.state.paletteWidth, 310);
    expect(controller.state.runtimeWidth, 500);
    expect(controller.state.commandOutputFraction, .6);
    expect(controller.state.highRefreshMode, isTrue);
    expect(controller.state.reduceMotion, isFalse);
  });

  test('restores the persisted high refresh preference', () async {
    final directory = await Directory.systemTemp.createTemp('nodeql_layout');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/layout.json');
    await file.writeAsString('{"highRefreshMode":false}');
    final controller = WorkbenchLayoutController(storageFile: () async => file);
    addTearDown(controller.dispose);

    await controller.restored;
    expect(controller.state.highRefreshMode, isFalse);
  });

  test('restores the persisted reduce motion preference', () async {
    final directory = await Directory.systemTemp.createTemp('nodeql_layout');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/layout.json');
    await file.writeAsString('{"reduceMotion":true}');
    final controller = WorkbenchLayoutController(storageFile: () async => file);
    addTearDown(controller.dispose);

    await controller.restored;
    expect(controller.state.reduceMotion, isTrue);
  });
}
