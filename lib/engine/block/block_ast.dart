abstract class BlockNode {
  const BlockNode({required this.id, this.next});

  final String id;
  final BlockNode? next;
}

class EventBlockNode extends BlockNode {
  const EventBlockNode({required super.id, required this.event, super.next});

  final String event;
}

class MotionBlockNode extends BlockNode {
  const MotionBlockNode({
    required super.id,
    required this.op,
    required this.value,
    super.next,
  });

  final String op;
  final double value;
}

class ControlBlockNode extends BlockNode {
  const ControlBlockNode({
    required super.id,
    required this.op,
    required this.times,
    this.body,
    super.next,
  });

  final String op;
  final int times;
  final BlockNode? body;
}
