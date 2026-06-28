import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_syntax.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/widgets/block_shape_painter.dart';

void main() {
  testWidgets(
    'execute query trigger renders its start marker without overflow',
    (tester) async {
      final trigger = EventBlock(id: 'trigger', position: Offset.zero);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Center(
            child: BlockShape(
              node: trigger,
              color: const Color(0xFFFFBF00),
              width: 210,
              height: 50,
              label: 'QUERY AUSFUEHREN',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('QUERY AUSFUEHREN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native SQL block labels render without widget overflow', (
    tester,
  ) async {
    final types = BlockType.values.where(
      (type) =>
          type == BlockType.eventGreenFlag ||
          type.name.startsWith('sql') ||
          type == BlockType.operatorAdd,
    );

    for (final mode in SqlAbstractionMode.values) {
      for (final type in types) {
        final node = _nodeForType(type);
        final label = sqlLabelFor(type, mode, node.inputs, 'de');
        final height =
            baseHeightForBlock(node) + (label.contains('\n') ? 40 : 0);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Center(
              child: BlockShape(
                node: node,
                color: const Color(0xFF2563EB),
                width: 620,
                height: height,
                label: label,
              ),
            ),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow while rendering ${type.name} in ${mode.name}',
        );
      }
    }
  });
}

BlockNode _nodeForType(BlockType type) {
  if (type == BlockType.eventGreenFlag) {
    return EventBlock(id: 'event', position: Offset.zero);
  }
  if (type == BlockType.sqlLoop) {
    return ControlBlock(
      id: 'node_${type.name}',
      position: Offset.zero,
      controlType: type,
    );
  }
  return OperatorBlock(
    id: 'node_${type.name}',
    position: Offset.zero,
    operatorType: type,
  );
}
