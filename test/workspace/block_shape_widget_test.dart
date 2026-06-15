import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
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
}
