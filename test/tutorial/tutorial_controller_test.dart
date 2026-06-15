import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/tutorial_controller.dart';

void main() {
  test('persists and restores tutorial completion', () async {
    final temp = await Directory.systemTemp.createTemp('nodeql_tutorial_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/tutorial.json');

    final controller = TutorialController(storageFile: () async => file);
    await controller.initialize();

    expect(controller.state.loading, isFalse);
    expect(controller.state.completed, isFalse);

    await controller.complete();

    expect(controller.state.completed, isTrue);
    expect(await file.readAsString(), contains('"completed":true'));

    final restored = TutorialController(storageFile: () async => file);
    await restored.initialize();

    expect(restored.state.loading, isFalse);
    expect(restored.state.completed, isTrue);
  });

  test('storage failures never block tutorial startup', () async {
    final controller = TutorialController(
      storageFile: () async => throw const FileSystemException('unavailable'),
    );

    await controller.initialize();

    expect(controller.state.loading, isFalse);
    expect(controller.state.completed, isFalse);
  });
}
