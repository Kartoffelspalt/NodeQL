import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scratchql_creater/engine/workspace/workspace_docking_service.dart';

void main() {
  test('snaps blocks when within magnetic distance', () {
    const service = WorkspaceDockingService(magneticDistance: 20);

    final near = service.evaluate(
      source: const Offset(100, 100),
      target: const Offset(110, 108),
    );

    final far = service.evaluate(
      source: const Offset(0, 0),
      target: const Offset(200, 200),
    );

    expect(near.shouldSnap, isTrue);
    expect(far.shouldSnap, isFalse);
  });
}
