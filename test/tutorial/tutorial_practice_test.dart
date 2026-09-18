import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';

void main() {
  test('beginner mission only accepts a configured connected SELECT', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginner]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': '*', 'table': 'customers'},
    );

    expect(definition.evaluate([event, select], 0).complete, isFalse);
    event.next = select;
    expect(definition.evaluate([event], 0).complete, isTrue);
  });

  test('syntax path checks WHERE before a configured AND', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginnerSyntax]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final where = MotionBlock(
      id: 'where',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: {'column': 'country', 'operator': '=', 'value': 'DE'},
    );
    final and = MotionBlock(
      id: 'and',
      position: Offset.zero,
      motionType: BlockType.sqlAnd,
      inputs: {'column': 'city', 'operator': '=', 'value': 'Berlin'},
    );

    event.next = and..next = where;
    expect(definition.evaluate([event], 2).complete, isFalse);

    event.next = where..next = and;
    and.next = null;
    expect(definition.evaluate([event], 2).complete, isTrue);
  });

  test('intermediate path requires GROUP BY before configured HAVING', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.intermediate]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final group = OperatorBlock(
      id: 'group',
      position: Offset.zero,
      operatorType: BlockType.sqlGroupBy,
      inputs: {'column': 'customers.name'},
    );
    final having = OperatorBlock(
      id: 'having',
      position: Offset.zero,
      operatorType: BlockType.sqlHaving,
      inputs: {'predicate': 'COUNT(*) > 0'},
    );

    event.next = group..next = having;
    expect(definition.evaluate([event], 2).complete, isTrue);
  });

  test('expert path validates UNION, ORDER BY and LIMIT missions', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.expert]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final union = OperatorBlock(
      id: 'union',
      position: Offset.zero,
      operatorType: BlockType.sqlUnion,
      inputs: {'sql': 'SELECT id, name FROM archived_customers'},
    );
    final order = MotionBlock(
      id: 'order',
      position: Offset.zero,
      motionType: BlockType.sqlOrderBy,
      inputs: {'column': 'name'},
    );
    final limit = OperatorBlock(
      id: 'limit',
      position: Offset.zero,
      operatorType: BlockType.sqlLimit,
      inputs: {'count': '10'},
    );
    event.next = union;
    union.next = order;
    order.next = limit;

    expect(definition.evaluate([event], 0).complete, isTrue);
    expect(definition.evaluate([event], 1).complete, isTrue);
    expect(definition.evaluate([event], 2).complete, isTrue);
  });

  test('resuming seeds all previously completed missions', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginnerSyntax]!;

    expect(definition.nextStep({0}), 1);
    expect(
      definition
          .starterFor(SqlAbstractionMode.simple, 2)
          .map((seed) => seed.type),
      [BlockType.sqlSelect, BlockType.sqlFrom, BlockType.sqlWhere],
    );
  });

  test('recognizes a column reporter as configured SELECT content', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginner]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': '', 'table': 'customers'},
    );
    setReporterForInput(
      select,
      'columns',
      OperatorBlock(
        id: 'column',
        position: Offset.zero,
        operatorType: BlockType.sqlColumn,
        inputs: {'column': 'name'},
      ),
    );
    event.next = select;

    final graph = TutorialPracticeGraph.fromRoots([event]);
    expect(graph.reporters, hasLength(1));
    expect(definition.evaluate([event], 0).complete, isTrue);
  });

  test('beginner course lasts about 15 minutes and teaches reporters', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginner]!;
    expect(definition.stepCount, 7);
    expect(definition.estimatedMinutes, 15);

    final event = EventBlock(id: 'event', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': 'name', 'table': 'customers'},
    );
    event.next = select;
    expect(definition.evaluate([event], 1).complete, isFalse);
    setReporterForInput(
      select,
      'columns',
      OperatorBlock(
        id: 'column',
        position: Offset.zero,
        operatorType: BlockType.sqlColumn,
        inputs: {'column': 'name'},
      ),
    );
    expect(definition.evaluate([event], 1).complete, isTrue);

    final starter = definition.starterFor(SqlAbstractionMode.simple, 6);
    expect(starter.map((seed) => seed.type), [
      BlockType.sqlSelect,
      BlockType.sqlWhere,
      BlockType.sqlAnd,
      BlockType.sqlOrderBy,
    ]);

    final reporterStarter = definition
        .starterFor(SqlAbstractionMode.simple, 2)
        .single;
    final resumedSelect = OperatorBlock(
      id: 'resumed_select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: Map<String, dynamic>.from(reporterStarter.defaults),
    );
    final resumedEvent = EventBlock(id: 'resumed_event', position: Offset.zero)
      ..next = resumedSelect;
    expect(definition.evaluate([resumedEvent], 1).complete, isTrue);
  });

  test('recognizes a text reporter in a complete WHERE condition', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginnerSyntax]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final where = MotionBlock(
      id: 'where',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: {'column': 'city', 'operator': '=', 'value': '', 'predicate': ''},
    );
    setReporterForInput(
      where,
      'value',
      OperatorBlock(
        id: 'text',
        position: Offset.zero,
        operatorType: BlockType.sqlText,
        inputs: {'text': 'Berlin'},
      ),
    );
    event.next = where;

    expect(definition.evaluate([event], 1).complete, isTrue);
  });

  test('validates every entry in a structured WHERE condition group', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginnerSyntax]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final where = MotionBlock(
      id: 'where',
      position: Offset.zero,
      motionType: BlockType.sqlWhere,
      inputs: {
        'predicate': '',
        'conditions': [
          {'column': 'country', 'operator': '=', 'value': 'DE'},
          {'column': 'active', 'operator': '=', 'value': '1'},
        ],
      },
    );
    event.next = where;
    expect(definition.evaluate([event], 1).complete, isTrue);

    (where.inputs['conditions'] as List).add({
      'column': 'city',
      'operator': 'NOT AN OPERATOR',
      'value': 'Berlin',
    });
    expect(definition.evaluate([event], 1).complete, isFalse);
  });

  test('recognizes nested aggregate reporters in HAVING', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.intermediate]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final group = OperatorBlock(
      id: 'group',
      position: Offset.zero,
      operatorType: BlockType.sqlGroupBy,
      inputs: {'column': 'customers.name'},
    );
    final having = OperatorBlock(
      id: 'having',
      position: Offset.zero,
      operatorType: BlockType.sqlHaving,
      inputs: {'aggregate': '', 'operator': '>', 'value': '1', 'predicate': ''},
    );
    final count = OperatorBlock(
      id: 'count',
      position: Offset.zero,
      operatorType: BlockType.sqlCount,
      inputs: {'column': ''},
    );
    setReporterForInput(
      count,
      'column',
      OperatorBlock(
        id: 'column',
        position: Offset.zero,
        operatorType: BlockType.sqlColumn,
        inputs: {'column': 'orders.id'},
      ),
    );
    setReporterForInput(having, 'aggregate', count);
    event.next = group..next = having;

    final graph = TutorialPracticeGraph.fromRoots([event]);
    expect(graph.reporters, hasLength(2));
    expect(definition.evaluate([event], 2).complete, isTrue);
  });

  test('recognizes column reporters in GROUP BY and ORDER BY', () {
    final intermediate =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.intermediate]!;
    final expert = tutorialPracticeDefinitions[TutorialKnowledgeMode.expert]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final group = OperatorBlock(
      id: 'group',
      position: Offset.zero,
      operatorType: BlockType.sqlGroupBy,
      inputs: {'column': '', 'expr': ''},
    );
    setReporterForInput(
      group,
      'column',
      OperatorBlock(
        id: 'group_column',
        position: Offset.zero,
        operatorType: BlockType.sqlColumn,
        inputs: {'column': 'customers.name'},
      ),
    );
    event.next = group;
    expect(intermediate.evaluate([event], 1).complete, isTrue);

    final union = OperatorBlock(
      id: 'union',
      position: Offset.zero,
      operatorType: BlockType.sqlUnion,
      inputs: {'sql': 'SELECT id, name FROM archived_customers'},
    );
    final order = MotionBlock(
      id: 'order',
      position: Offset.zero,
      motionType: BlockType.sqlOrderBy,
      inputs: {'column': '', 'expr': '', 'order': 'DESC'},
    );
    setReporterForInput(
      order,
      'column',
      OperatorBlock(
        id: 'order_column',
        position: Offset.zero,
        operatorType: BlockType.sqlColumn,
        inputs: {'column': 'name'},
      ),
    );
    event.next = union..next = order;
    expect(expert.evaluate([event], 1).complete, isTrue);
  });

  test('rejects placeholders, invalid UNION SQL, and non-positive LIMIT', () {
    final beginner =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.beginner]!;
    final expert = tutorialPracticeDefinitions[TutorialKnowledgeMode.expert]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final select = OperatorBlock(
      id: 'select',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: {'columns': 'column_name', 'table': 'table_name'},
    );
    event.next = select;
    expect(beginner.evaluate([event], 0).complete, isFalse);

    final union = OperatorBlock(
      id: 'union',
      position: Offset.zero,
      operatorType: BlockType.sqlUnion,
      inputs: {'sql': 'DELETE FROM customers'},
    );
    event.next = union;
    expect(expert.evaluate([event], 0).complete, isFalse);

    final order = MotionBlock(
      id: 'order',
      position: Offset.zero,
      motionType: BlockType.sqlOrderBy,
      inputs: {'column': 'name', 'order': 'ASC'},
    );
    final limit = OperatorBlock(
      id: 'limit',
      position: Offset.zero,
      operatorType: BlockType.sqlLimit,
      inputs: {'count': '0'},
    );
    event.next = order..next = limit;
    expect(expert.evaluate([event], 2).complete, isFalse);
  });
}
