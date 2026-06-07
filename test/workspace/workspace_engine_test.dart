import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';

void main() {
  test('does not snap blocks above execute query starter', () {
    final controller = WorkspaceController()..resetWithRoot();

    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 70));

    final roots = controller.state.roots;
    expect(roots.first.type, BlockType.eventGreenFlag);
    expect(roots.first.next, isNull);
    expect(
      roots.where((node) => node.type == BlockType.sqlSelect),
      hasLength(1),
    );
  });

  test('does not snap execute query starter into another chain', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 190));

    final starter = controller.state.roots.first;
    controller.startDrag(starter.position + const Offset(10, 10));
    controller.updateDrag(const Offset(0, 90));
    controller.endDrag();

    expect(controller.state.roots.first.type, BlockType.eventGreenFlag);
    expect(controller.state.roots.first.next?.type, BlockType.sqlSelect);
    expect(controller.state.roots, hasLength(1));
  });

  test('deletes a selected non-root node and heals the chain', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 170));
    final selectNode = controller.state.roots.first.next!;

    controller.selectAt(selectNode.position + const Offset(10, 10));
    controller.deleteSelected();

    expect(controller.state.roots.first.type, BlockType.eventGreenFlag);
    expect(controller.state.roots.first.next, isNull);
  });

  test('deletes execute query root with its attached chain', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 170));

    controller.selectAt(
      controller.state.roots.first.position + const Offset(10, 10),
    );
    controller.deleteSelected();

    expect(controller.state.roots, isEmpty);
  });
}
