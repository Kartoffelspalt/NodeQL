import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/tutorial_framework.dart';

void main() {
  test('the Workshop UI catalog is complete and can look up stable ids', () {
    expect(workshopTutorialCatalog.tutorials, hasLength(10));
    expect(workshopTutorialCatalog.missionCount, 27);
    expect(
      workshopTutorialCatalog.byId('selectAndSimpleFilters')?.mode,
      TutorialKnowledgeMode.selectAndSimpleFilters,
    );
    expect(
      workshopTutorialCatalog.byMode(TutorialKnowledgeMode.transactions)?.id,
      'transactions',
    );
  });

  test('a compact mission supports built-in and custom requirements', () {
    final definition = TutorialPracticeDefinition(
      id: 'custom-select',
      mode: TutorialKnowledgeMode.selectAndSimpleFilters,
      simpleStarter: [workshopNode(BlockType.sqlSelect)],
      advancedStarter: const [],
      steps: [
        workshopMission(
          id: 'run-select',
          checks: const [TutorialPracticeCheck.selectConnected],
          requirements: [
            TutorialPracticeRequirement.custom(
              id: 'runs-current-sql',
              labelKey: 'tutorial.practice.check.runsCurrentSql',
              validator: (_, context) => context.currentSqlWasExecuted,
            ),
          ],
          focusNodes: const [BlockType.sqlSelect],
        ),
      ],
    );
    final root = EventBlock(id: 'event', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'select',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: {'columns': 'name', 'table': 'customers'},
      );

    expect(definition.evaluate([root], 0).complete, isFalse);
    expect(
      definition
          .evaluate(
            [root],
            0,
            currentSql: 'SELECT name FROM customers;',
            executedSql: 'SELECT name FROM customers;',
            executionSucceeded: true,
          )
          .complete,
      isTrue,
    );
  });

  test('the catalog rejects duplicate tutorial and mission ids', () {
    final practice = TutorialPracticeDefinition(
      mode: TutorialKnowledgeMode.selectAndSimpleFilters,
      simpleStarter: const [],
      advancedStarter: const [],
      steps: [
        workshopMission(
          id: 'same',
          checks: const [TutorialPracticeCheck.selectConnected],
        ),
        workshopMission(
          id: 'same',
          checks: const [TutorialPracticeCheck.whereConnected],
        ),
      ],
    );

    expect(
      () => WorkshopTutorialCatalog([
        WorkshopTutorialDefinition(
          id: 'duplicate-missions',
          mode: TutorialKnowledgeMode.selectAndSimpleFilters,
          practice: practice,
        ),
      ]),
      throwsArgumentError,
    );
  });
}
