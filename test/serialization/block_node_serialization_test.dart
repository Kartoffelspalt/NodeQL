import 'package:flutter_test/flutter_test.dart';
import 'package:scratchql_creater/domain/models/block_models.dart';

void main() {
  test('block node encodes and decodes deterministically', () {
    const node = BlockNode(
      id: '1',
      type: 'motion.move_steps',
      arguments: <String, Object?>{'steps': 10},
    );

    final encoded = node.encode();
    final decoded = BlockNode.decode(encoded);

    expect(decoded.id, node.id);
    expect(decoded.type, node.type);
    expect(decoded.arguments['steps'], 10);
  });
}
