import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/stage_engine.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';

final runtimeCoordinatorProvider = Provider<RuntimeCoordinator>((ref) {
  return RuntimeCoordinator(ref);
});

class RuntimeCoordinator {
  RuntimeCoordinator(this._ref);

  final Ref _ref;
  int _token = 0;

  bool get isRunning => _ref.read(stageRuntimeProvider).running;

  Future<void> runGreenFlag() async {
    stop();
    _token++;
    final token = _token;

    _ref.read(stageRuntimeProvider.notifier).setRunning(true);

    final roots = _ref.read(workspaceProvider).roots;
    final events = roots.whereType<EventBlock>().toList(growable: false);

    await Future.wait(events.map((event) => _runChain(event.next, token)));
  }

  void stop() {
    _token++;
    _ref.read(stageRuntimeProvider.notifier).setRunning(false);
  }

  Future<void> _runChain(BlockNode? node, int token) async {
    BlockNode? current = node;
    while (current != null && _canRun(token)) {
      await _exec(current, token);
      current = current.next;
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }

  Future<void> _exec(BlockNode node, int token) async {
    if (!_canRun(token)) return;

    final stage = _ref.read(stageRuntimeProvider.notifier);

    if (node is MotionBlock) {
      if (node.type == BlockType.motionMove) {
        stage.moveActive((node.inputs['steps'] ?? 10).toDouble());
      }
      if (node.type == BlockType.motionTurn) {
        stage.turnActive((node.inputs['degrees'] ?? 15).toDouble());
      }
      return;
    }

    if (node is ControlBlock) {
      if (node.type == BlockType.controlRepeat) {
        final times = (node.inputs['times'] ?? 10) as int;
        for (var i = 0; i < times && _canRun(token); i++) {
          for (final child in node.children) {
            await _runChain(child, token);
          }
        }
      }

      if (node.type == BlockType.controlForever) {
        while (_canRun(token)) {
          for (final child in node.children) {
            await _runChain(child, token);
          }
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }
    }
  }

  bool _canRun(int token) =>
      token == _token && _ref.read(stageRuntimeProvider).running;
}
