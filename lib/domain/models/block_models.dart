import 'dart:convert';

class BlockMetadata {
  const BlockMetadata({
    required this.type,
    required this.translationKey,
    this.arguments = const <String>[],
    this.isContainer = false,
  });

  final String type;
  final String translationKey;
  final List<String> arguments;
  final bool isContainer;
}

class BlockNode {
  const BlockNode({
    required this.id,
    required this.type,
    this.arguments = const <String, Object?>{},
    this.children = const <BlockNode>[],
    this.next,
  });

  final String id;
  final String type;
  final Map<String, Object?> arguments;
  final List<BlockNode> children;
  final BlockNode? next;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'arguments': arguments,
        'children': children.map((child) => child.toJson()).toList(),
        'next': next?.toJson(),
      };

  factory BlockNode.fromJson(Map<String, Object?> json) {
    final rawChildren = (json['children'] as List<Object?>? ?? <Object?>[])
        .cast<Map<String, Object?>>();
    return BlockNode(
      id: json['id']! as String,
      type: json['type']! as String,
      arguments:
          (json['arguments'] as Map<String, Object?>?) ?? <String, Object?>{},
      children: rawChildren.map(BlockNode.fromJson).toList(),
      next: json['next'] == null
          ? null
          : BlockNode.fromJson(json['next']! as Map<String, Object?>),
    );
  }

  String encode() => jsonEncode(toJson());

  static BlockNode decode(String source) =>
      BlockNode.fromJson(jsonDecode(source) as Map<String, Object?>);
}
