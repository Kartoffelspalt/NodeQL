import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';

void main() {
  test('curriculum contains eight SQLite workshops and 27 missions', () {
    expect(
      TutorialKnowledgeMode.values.where(
        (mode) => mode.area == TutorialWorkshopArea.sqlite,
      ),
      hasLength(8),
    );
    expect(
      TutorialKnowledgeMode.values.where(
        (mode) => mode.area == TutorialWorkshopArea.nodeQl,
      ),
      hasLength(2),
    );
    expect(
      tutorialPracticeDefinitions.values.fold<int>(
        0,
        (total, definition) => total + definition.stepCount,
      ),
      27,
    );
    for (final mode in TutorialKnowledgeMode.values) {
      expect(
        tutorialPracticeDefinitions.containsKey(mode),
        mode.hasWorkspacePractice,
      );
    }
  });

  test('every mission restores one compilable connected graph', () {
    for (final definition in tutorialPracticeDefinitions.values) {
      for (final mode in SqlAbstractionMode.values) {
        for (var step = 0; step < definition.stepCount; step++) {
          final workspace = WorkspaceController()
            ..resetWithRoot(recordUndo: false, clearHistory: true);
          for (final seed in definition.starterFor(mode, step)) {
            workspace.addTemplate(
              seed.type,
              workspace.suggestedTemplatePosition(seed.type),
              defaults: seed.defaults,
              recordUndo: false,
            );
          }
          expect(workspace.state.roots, hasLength(1));
          expect(
            () => const SqlCompiler().compileWorkspace(workspace.state.roots),
            returnsNormally,
          );
        }
      }
    }
  });

  test('SELECT workshop requires a configured query and simple filter', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode
            .selectAndSimpleFilters]!;
    final event = EventBlock(id: 'event', position: Offset.zero);
    final select = _operator('select', BlockType.sqlSelect, {
      'columns': 'name',
      'table': 'customers',
    });
    final where = _motion('where', BlockType.sqlWhere);
    event.next = select;
    expect(definition.evaluate([event], 0).complete, isTrue);
    select.next = where;
    expect(definition.evaluate([event], 1).complete, isTrue);
  });

  test('data type workshop recognizes a literal reporter', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.dataTypes]!;
    final select = _operator('select', BlockType.sqlSelect, {
      'columns': '',
      'table': 'customers',
    });
    setReporterForInput(
      select,
      'columns',
      _operator('literal', BlockType.sqlText, {
        'literal_type': 'real',
        'text': '1.5',
      }),
    );
    expect(
      definition.evaluate([
        _chain([select]),
      ], 0).complete,
      isTrue,
    );
  });

  test('advanced filters enforce WHERE before AND and OR', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.advancedFilters]!;
    final root = _chain([
      _motion('where', BlockType.sqlWhere),
      _motion('and', BlockType.sqlAnd),
      _motion('or', BlockType.sqlOr),
    ]);
    expect(definition.evaluate([root], 0).complete, isTrue);
    expect(definition.evaluate([root], 1).complete, isTrue);

    final invalid = _chain([
      _motion('or2', BlockType.sqlOr),
      _motion('where2', BlockType.sqlWhere),
    ]);
    expect(definition.evaluate([invalid], 1).complete, isFalse);
  });

  test('DML workshop validates INSERT, UPDATE and DELETE fields', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.dataManipulation]!;
    final insert = _operator('insert', BlockType.sqlInsert, {
      'table': 'archived_customers',
      'columns': 'id, name',
      'values': "(999, 'Workshop')",
    });
    final update = _operator('update', BlockType.sqlUpdate, {
      'table': 'archived_customers',
      'column': 'name',
      'value': "'NodeQL'",
      'where_column': 'id',
      'operator': '=',
      'where_value': '999',
    });
    final delete = _operator('delete', BlockType.sqlDelete, {
      'table': 'archived_customers',
      'where_column': 'id',
      'operator': '=',
      'where_value': '999',
    });
    expect(
      definition.evaluate([
        _chain([insert]),
      ], 0).complete,
      isTrue,
    );
    expect(
      definition.evaluate([
        _chain([update]),
      ], 1).complete,
      isTrue,
    );
    expect(
      definition.evaluate([
        _chain([delete]),
      ], 2).complete,
      isTrue,
    );
  });

  test('schema workshop validates tables, indexes and views', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.schemaObjects]!;
    final table = _operator('table', BlockType.sqlCreateTable, {
      'table': 'notes',
      'definition': 'id INTEGER PRIMARY KEY, note TEXT',
    });
    final index = _operator('index', BlockType.sqlCreateIndex, {
      'name': 'idx_notes_note',
      'table': 'notes',
      'columns': 'note',
    });
    final view = _operator('view', BlockType.sqlCreateView, {
      'name': 'active_customers',
      'sql': 'SELECT id FROM customers WHERE active = 1',
    });
    expect(
      definition.evaluate([
        _chain([table]),
      ], 0).complete,
      isTrue,
    );
    expect(
      definition.evaluate([
        _chain([index]),
      ], 1).complete,
      isTrue,
    );
    expect(
      definition.evaluate([
        _chain([view]),
      ], 2).complete,
      isTrue,
    );
  });

  test('transaction workshop enforces recovery-point order', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode.transactions]!;
    final ordered = _chain([
      _operator('begin', BlockType.sqlBeginTransaction),
      _operator('savepoint', BlockType.sqlSavepoint, {
        'name': 'workshop_point',
      }),
      _operator('rollback', BlockType.sqlRollbackToSavepoint, {
        'name': 'workshop_point',
      }),
      _operator('release', BlockType.sqlReleaseSavepoint, {
        'name': 'workshop_point',
      }),
      _operator('commit', BlockType.sqlCommit),
    ]);
    const sql =
        'BEGIN; SAVEPOINT point; ROLLBACK TO point; RELEASE point; COMMIT;';
    expect(
      definition
          .evaluate(
            [ordered],
            2,
            currentSql: sql,
            executedSql: sql,
            executionSucceeded: true,
          )
          .complete,
      isTrue,
    );

    final invalid = _chain([
      _operator('savepoint2', BlockType.sqlSavepoint, {'name': 'point'}),
      _operator('begin2', BlockType.sqlBeginTransaction),
      _operator('rollback2', BlockType.sqlRollbackToSavepoint, {
        'name': 'point',
      }),
      _operator('release2', BlockType.sqlReleaseSavepoint, {'name': 'point'}),
      _operator('commit2', BlockType.sqlCommit),
    ]);
    expect(
      definition
          .evaluate(
            [invalid],
            2,
            currentSql: sql,
            executedSql: sql,
            executionSucceeded: true,
          )
          .complete,
      isFalse,
    );
  });

  test('execution check only accepts the current successful SQL', () {
    final definition =
        tutorialPracticeDefinitions[TutorialKnowledgeMode
            .selectAndSimpleFilters]!;
    final root = _chain([
      _operator('select', BlockType.sqlSelect, {
        'columns': 'name',
        'table': 'customers',
      }),
      _motion('where', BlockType.sqlWhere),
    ]);
    const sql = "SELECT name FROM customers WHERE city = 'Berlin';";
    expect(
      definition
          .evaluate(
            [root],
            2,
            currentSql: sql,
            executedSql: sql,
            executionSucceeded: true,
          )
          .complete,
      isTrue,
    );
    expect(
      definition
          .evaluate(
            [root],
            2,
            currentSql: sql,
            executedSql: 'SELECT 1;',
            executionSucceeded: true,
          )
          .complete,
      isFalse,
    );
  });
}

EventBlock _chain(List<BlockNode> nodes) {
  final event = EventBlock(
    id: 'event-${nodes.first.id}',
    position: Offset.zero,
  );
  event.next = nodes.first;
  for (var index = 0; index < nodes.length - 1; index++) {
    nodes[index].next = nodes[index + 1];
  }
  return event;
}

OperatorBlock _operator(
  String id,
  BlockType type, [
  Map<String, dynamic> inputs = const {},
]) => OperatorBlock(
  id: id,
  position: Offset.zero,
  operatorType: type,
  inputs: Map<String, dynamic>.from(inputs),
);

MotionBlock _motion(String id, BlockType type) => MotionBlock(
  id: id,
  position: Offset.zero,
  motionType: type,
  inputs: {'column': 'city', 'operator': '=', 'value': 'Berlin'},
);
