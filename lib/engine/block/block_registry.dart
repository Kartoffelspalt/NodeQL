import 'package:nodeql/domain/models/block_models.dart';

class BlockRegistry {
  final Map<String, BlockMetadata> _entries = <String, BlockMetadata>{};

  void register(BlockMetadata metadata) {
    _entries[metadata.type] = metadata;
  }

  BlockMetadata? byType(String type) => _entries[type];

  bool validate(BlockNode node) {
    final metadata = byType(node.type);
    if (metadata == null) return false;
    if (metadata.arguments.length != node.arguments.keys.length) return false;
    return node.children.every(validate) &&
        (node.next == null || validate(node.next!));
  }
}
