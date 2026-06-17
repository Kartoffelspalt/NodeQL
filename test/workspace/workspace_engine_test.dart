import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
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

  test('inserts JOIN between FROM and WHERE', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 178));
    controller.addTemplate(BlockType.sqlWhere, const Offset(120, 234));
    controller.addTemplate(BlockType.sqlFrom, const Offset(120, 234));
    controller.addTemplate(BlockType.sqlLeftJoin, const Offset(120, 284));

    final event = controller.state.roots.single;
    expect(event.next?.type, BlockType.sqlSelect);
    expect(event.next?.next?.type, BlockType.sqlFrom);
    expect(event.next?.next?.next?.type, BlockType.sqlLeftJoin);
    expect(event.next?.next?.next?.next?.type, BlockType.sqlWhere);
  });

  test('adds two INNER JOIN blocks in one query chain without cycling', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 178));
    controller.addTemplate(BlockType.sqlFrom, const Offset(120, 234));
    controller.addTemplate(BlockType.sqlInnerJoin, const Offset(120, 284));
    controller.addTemplate(BlockType.sqlInnerJoin, const Offset(120, 360));

    final event = controller.state.roots.single;
    expect(event.next?.type, BlockType.sqlSelect);
    expect(event.next?.next?.type, BlockType.sqlFrom);
    expect(event.next?.next?.next?.type, BlockType.sqlInnerJoin);
    expect(event.next?.next?.next?.next?.type, BlockType.sqlInnerJoin);
    expect(event.next?.next?.next?.next?.next, isNull);
    expect(controller.allBlocks(), hasLength(5));
  });

  test('inserts two INNER JOIN blocks into the starter query chain', () {
    final controller = WorkspaceController();
    controller.addTemplate(BlockType.sqlInnerJoin, const Offset(120, 352));
    controller.addTemplate(BlockType.sqlInnerJoin, const Offset(120, 428));

    final event = controller.state.roots.single;
    expect(event.next?.type, BlockType.sqlSelect);
    expect(event.next?.next?.type, BlockType.sqlFrom);
    expect(event.next?.next?.next?.type, BlockType.sqlLeftJoin);
    expect(event.next?.next?.next?.next?.type, BlockType.sqlInnerJoin);
    expect(event.next?.next?.next?.next?.next?.type, BlockType.sqlInnerJoin);
    expect(event.next?.next?.next?.next?.next?.next?.type, BlockType.sqlWhere);
    expect(
      event.next?.next?.next?.next?.next?.next?.next?.type,
      BlockType.sqlOrderBy,
    );
    expect(controller.allBlocks(), hasLength(8));
  });

  test('traverses a corrupted two-JOIN cycle without hanging', () {
    final controller = WorkspaceController()..resetWithRoot();
    final root = controller.state.roots.single;
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
    );
    final from = OperatorBlock(
      id: 'from',
      position: Offset.zero,
      operatorType: BlockType.sqlFrom,
    );
    final joinOne = OperatorBlock(
      id: 'join-one',
      position: Offset.zero,
      operatorType: BlockType.sqlLeftJoin,
    );
    final joinTwo = OperatorBlock(
      id: 'join-two',
      position: Offset.zero,
      operatorType: BlockType.sqlInnerJoin,
    );

    root.next = select;
    select.next = from;
    from.next = joinOne;
    joinOne.next = joinTwo;
    joinTwo.next = joinOne;

    expect(controller.allBlocks().map((node) => node.id), <String>[
      'event_root',
      'select',
      'from',
      'join-one',
      'join-two',
    ]);
    expect(controller.toJsonString(), contains('join-two'));

    controller.updateInput(joinTwo, 'table', 'payments');

    expect(joinTwo.next, isNull);
    expect(controller.allBlocks(), hasLength(5));
  });

  test('does not attach HAVING without GROUP BY', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 178));
    controller.addTemplate(BlockType.sqlHaving, const Offset(120, 234));

    expect(controller.state.roots.first.next?.type, BlockType.sqlSelect);
    expect(controller.state.roots.first.next?.next, isNull);
    expect(
      controller.state.roots.where((node) => node.type == BlockType.sqlHaving),
      hasLength(1),
    );
  });

  test('snaps HAVING after GROUP BY', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 178));
    controller.addTemplate(BlockType.sqlFrom, const Offset(120, 234));
    controller.addTemplate(BlockType.sqlGroupBy, const Offset(120, 284));
    controller.addTemplate(BlockType.sqlHaving, const Offset(120, 334));

    final event = controller.state.roots.single;
    expect(event.next?.type, BlockType.sqlSelect);
    expect(event.next?.next?.type, BlockType.sqlFrom);
    expect(event.next?.next?.next?.type, BlockType.sqlGroupBy);
    expect(event.next?.next?.next?.next?.type, BlockType.sqlHaving);
  });

  test('suggests a valid palette-click position for HAVING after GROUP BY', () {
    final controller = WorkspaceController()..resetWithRoot();
    controller.addTemplate(BlockType.sqlSelect, const Offset(120, 178));
    controller.addTemplate(BlockType.sqlFrom, const Offset(120, 234));
    controller.addTemplate(BlockType.sqlGroupBy, const Offset(120, 284));

    controller.addTemplate(
      BlockType.sqlHaving,
      controller.suggestedTemplatePosition(BlockType.sqlHaving),
    );

    final event = controller.state.roots.single;
    expect(event.next?.next?.next?.type, BlockType.sqlGroupBy);
    expect(event.next?.next?.next?.next?.type, BlockType.sqlHaving);
  });

  test('stores nested Scratch-style reporters inside an input slot', () {
    final controller = WorkspaceController();
    final select = controller.state.roots.first.next!;

    controller.setReporterInput(select, 'columns', BlockType.sqlAvg);
    final average = reporterForInput(select, 'columns');
    expect(average?.type, BlockType.sqlAvg);

    controller.setNestedReporterInput(
      select,
      'columns',
      average!,
      'expr',
      BlockType.sqlColumn,
      defaults: <String, dynamic>{'column': 'total'},
    );

    final restoredAverage = reporterForInput(select, 'columns');
    final column = reporterForInput(restoredAverage!, 'expr');
    expect(column?.type, BlockType.sqlColumn);
    expect(column?.inputs['column'], 'total');
  });

  test('new SELECT blocks include their own FROM input by default', () {
    final controller = WorkspaceController();

    controller.addTemplate(BlockType.sqlSelect, const Offset(600, 300));

    final select = controller.state.roots.last;
    expect(select.type, BlockType.sqlSelect);
    expect(select.inputs['separate_from'], isFalse);
    expect(select.inputs['table'], 'table_name');
  });
}
