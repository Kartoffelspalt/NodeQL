import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';

void main() {
  test('rejects block chains deeper than the import limit', () {
    final root = _block('root');
    var current = root;
    for (var index = 0; index < BlockNode.maxDecodedDepth; index++) {
      final next = _block('node_$index');
      current['next'] = next;
      current = next;
    }

    expect(() => BlockNode.fromJson(root), throwsA(isA<FormatException>()));
  });

  test('shares the node limit across every workspace root', () {
    final roots = List<Map<String, dynamic>>.generate(
      BlockNode.maxDecodedNodes + 1,
      (index) => _block('node_$index'),
    );

    expect(
      () => BlockNode.fromJsonList(roots),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects deeply nested input payloads before reporter parsing', () {
    final input = <String, dynamic>{};
    var current = input;
    for (var index = 0; index < BlockNode.maxInputCollectionDepth; index++) {
      final next = <String, dynamic>{};
      current['nested'] = next;
      current = next;
    }
    final root = _block('root')..['inputs'] = <String, dynamic>{'value': input};

    expect(() => BlockNode.fromJson(root), throwsA(isA<FormatException>()));
  });
}

Map<String, dynamic> _block(String id) => <String, dynamic>{
  'id': id,
  'type': 'sqlSelect',
  'position': <String, double>{'dx': 0, 'dy': 0},
  'children': <dynamic>[],
  'inputs': <String, dynamic>{},
};
