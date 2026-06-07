import 'package:nodeql/engine/block/block_ast.dart';
import 'package:nodeql/features/workbench/presentation/workbench_state.dart';

class ScriptCompiler {
  const ScriptCompiler();

  List<BlockNode> compile(List<WorkspaceBlock> blocks) {
    if (blocks.isEmpty) return const <BlockNode>[];

    final sorted = [...blocks]
      ..sort((a, b) {
        final byX = a.position.dx.compareTo(b.position.dx);
        if (byX == 0) return a.position.dy.compareTo(b.position.dy);
        return byX;
      });

    final hats = sorted
        .where((block) => block.type == 'events.when_flag')
        .toList();
    final scripts = <BlockNode>[];

    for (final hat in hats) {
      final chain = _buildChain(sorted, hat, indent: hat.position.dx);
      scripts.add(EventBlockNode(id: hat.id, event: 'green_flag', next: chain));
    }

    return scripts;
  }

  BlockNode? _buildChain(
    List<WorkspaceBlock> all,
    WorkspaceBlock anchor, {
    required double indent,
  }) {
    final candidates =
        all
            .where(
              (block) =>
                  block.id != anchor.id &&
                  (block.position.dy - anchor.position.dy) > 10 &&
                  (block.position.dx - indent).abs() < 16,
            )
            .toList()
          ..sort((a, b) => a.position.dy.compareTo(b.position.dy));

    final next = candidates.isEmpty
        ? null
        : _chainFromList(all, candidates, indent: indent);
    return next;
  }

  BlockNode? _chainFromList(
    List<WorkspaceBlock> all,
    List<WorkspaceBlock> chain, {
    required double indent,
  }) {
    BlockNode? next;

    for (final block in chain.reversed) {
      if (block.type == 'motion.move') {
        next = MotionBlockNode(
          id: block.id,
          op: 'move',
          value: block.numberValue,
          next: next,
        );
      } else if (block.type == 'motion.turn') {
        next = MotionBlockNode(
          id: block.id,
          op: 'turn',
          value: block.numberValue,
          next: next,
        );
      } else if (block.type == 'control.repeat') {
        final body = _buildNested(all, block, indent: block.position.dx + 24);
        next = ControlBlockNode(
          id: block.id,
          op: 'repeat',
          times: block.numberValue.round().clamp(1, 999),
          body: body,
          next: next,
        );
      } else if (block.type == 'control.forever') {
        final body = _buildNested(all, block, indent: block.position.dx + 24);
        next = ControlBlockNode(
          id: block.id,
          op: 'forever',
          times: 0,
          body: body,
          next: next,
        );
      }
    }

    return next;
  }

  BlockNode? _buildNested(
    List<WorkspaceBlock> all,
    WorkspaceBlock parent, {
    required double indent,
  }) {
    final nested =
        all
            .where(
              (block) =>
                  block.id != parent.id &&
                  block.position.dy > parent.position.dy + 8 &&
                  block.position.dy < parent.position.dy + 180 &&
                  (block.position.dx - indent).abs() < 18,
            )
            .toList()
          ..sort((a, b) => a.position.dy.compareTo(b.position.dy));

    if (nested.isEmpty) return null;
    return _chainFromList(all, nested, indent: indent);
  }
}
