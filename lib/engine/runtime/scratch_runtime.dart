import 'dart:async';

import 'package:nodeql/engine/block/block_ast.dart';

class RuntimeBindings {
  const RuntimeBindings({
    required this.move,
    required this.turn,
    required this.isRunning,
  });

  final void Function(double steps) move;
  final void Function(double degrees) turn;
  final bool Function() isRunning;
}

class ScratchRuntime {
  ScratchRuntime(this.bindings);

  final RuntimeBindings bindings;
  final List<Future<void>> _tasks = <Future<void>>[];
  bool _running = false;

  bool get isRunning => _running;

  void start(List<BlockNode> scripts) {
    stop();
    _running = true;

    for (final script in scripts.whereType<EventBlockNode>()) {
      if (script.event != 'green_flag') continue;
      _tasks.add(_executeChain(script.next));
    }
  }

  void stop() {
    _running = false;
    _tasks.clear();
  }

  Future<void> _executeChain(BlockNode? node) async {
    BlockNode? current = node;
    while (_running && bindings.isRunning() && current != null) {
      await _executeNode(current);
      current = current.next;
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }

  Future<void> _executeNode(BlockNode node) async {
    if (!_running || !bindings.isRunning()) return;

    if (node is MotionBlockNode) {
      if (node.op == 'move') bindings.move(node.value);
      if (node.op == 'turn') bindings.turn(node.value);
      return;
    }

    if (node is ControlBlockNode) {
      if (node.op == 'repeat') {
        for (var i = 0; i < node.times; i++) {
          if (!_running || !bindings.isRunning()) return;
          await _executeChain(node.body);
        }
      }

      if (node.op == 'forever') {
        while (_running && bindings.isRunning()) {
          await _executeChain(node.body);
        }
      }
    }
  }
}
