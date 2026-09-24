import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/tutorial_models.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';

class TutorialPracticeSeed {
  const TutorialPracticeSeed(this.type, [this.defaults = const {}]);

  final BlockType type;
  final Map<String, dynamic> defaults;
}

enum TutorialPracticeCheck {
  selectConnected,
  selectConfigured,
  fromConnected,
  fromConfigured,
  selectBeforeFrom,
  whereConnected,
  whereConfigured,
  andConnected,
  andConfigured,
  whereBeforeAnd,
  joinConnected,
  joinConfigured,
  groupByConnected,
  groupByConfigured,
  havingConnected,
  havingConfigured,
  groupBeforeHaving,
  unionConnected,
  unionConfigured,
  unionBeforeOrder,
  orderByConnected,
  orderByConfigured,
  limitConnected,
  limitConfigured,
  orderBeforeLimit,
  selectColumnReporter,
  whereTextReporter,
  orConnected,
  orConfigured,
  whereBeforeOr,
  selectDistinct,
  selectAggregateReporter,
  selectAliasReporter,
  intersectConnected,
  intersectConfigured,
  exceptConnected,
  exceptConfigured,
  unionAllConfigured,
  selectLiteralReporter,
  insertConnected,
  insertConfigured,
  updateConnected,
  updateConfigured,
  deleteConnected,
  deleteConfigured,
  createTableConnected,
  createTableConfigured,
  createIndexConnected,
  createIndexConfigured,
  createViewConnected,
  createViewConfigured,
  beginTransactionConnected,
  savepointConnected,
  savepointConfigured,
  rollbackToSavepointConnected,
  releaseSavepointConnected,
  commitConnected,
  transactionOrderValid,
  queryExecuted,
}

class TutorialPracticeStep {
  const TutorialPracticeStep({
    required this.checks,
    this.resumeSeeds = const <TutorialPracticeSeed>[],
    this.starterSeeds,
    this.focusNodes = const <BlockType>[],
    this.estimatedMinutes = 2,
    this.startFresh = false,
  });

  final List<TutorialPracticeCheck> checks;
  final List<TutorialPracticeSeed> resumeSeeds;
  final List<TutorialPracticeSeed>? starterSeeds;
  final List<BlockType> focusNodes;
  final int estimatedMinutes;
  final bool startFresh;
}

class TutorialPracticeDefinition {
  const TutorialPracticeDefinition({
    required this.mode,
    required this.simpleStarter,
    required this.advancedStarter,
    required this.steps,
  });

  final TutorialKnowledgeMode mode;
  final List<TutorialPracticeSeed> simpleStarter;
  final List<TutorialPracticeSeed> advancedStarter;
  final List<TutorialPracticeStep> steps;

  String get key => 'tutorial.practice.${mode.name}';
  int get stepCount => steps.length;
  int get estimatedMinutes =>
      steps.fold<int>(0, (total, step) => total + step.estimatedMinutes);

  String stepKey(int index) => '$key.step.${index + 1}';

  int nextStep(Set<int> completedSteps) {
    for (var index = 0; index < steps.length; index++) {
      if (!completedSteps.contains(index)) return index;
    }
    return 0;
  }

  List<TutorialPracticeSeed> starterFor(
    SqlAbstractionMode abstractionMode,
    int stepIndex,
  ) {
    final step = steps[stepIndex.clamp(0, steps.length - 1)];
    final explicitStarter = step.starterSeeds;
    if (explicitStarter != null) return explicitStarter;
    return <TutorialPracticeSeed>[
      ...(abstractionMode == SqlAbstractionMode.simple
          ? simpleStarter
          : advancedStarter),
      for (var index = 0; index < stepIndex; index++)
        ...steps[index].resumeSeeds,
    ];
  }

  TutorialPracticeResult evaluate(
    List<BlockNode> roots,
    int stepIndex, {
    String? currentSql,
    String? executedSql,
    bool executionSucceeded = false,
  }) {
    final graph = TutorialPracticeGraph.fromRoots(roots);
    final step = steps[stepIndex.clamp(0, steps.length - 1)];
    return TutorialPracticeResult({
      for (final check in step.checks)
        check: check == TutorialPracticeCheck.queryExecuted
            ? executionSucceeded &&
                  currentSql != null &&
                  currentSql.trim().isNotEmpty &&
                  currentSql.trim() == executedSql?.trim()
            : _evaluate(check, graph),
    });
  }

  bool _evaluate(TutorialPracticeCheck check, TutorialPracticeGraph graph) {
    final nodes = graph.statements;
    final types = nodes.map((node) => node.type).toList(growable: false);
    return switch (check) {
      TutorialPracticeCheck.selectConnected => types.contains(
        BlockType.sqlSelect,
      ),
      TutorialPracticeCheck.selectConfigured => _configured(
        nodes,
        BlockType.sqlSelect,
        (node) =>
            graph.inputConfigured(node, 'columns', allowWildcard: true) &&
            (node.inputs['separate_from'] == true ||
                graph.inputConfigured(node, 'table') ||
                (node.next?.type == BlockType.sqlFrom &&
                    graph.inputConfigured(node.next!, 'table'))),
      ),
      TutorialPracticeCheck.fromConnected => types.contains(BlockType.sqlFrom),
      TutorialPracticeCheck.fromConfigured => _configured(
        nodes,
        BlockType.sqlFrom,
        (node) => graph.inputConfigured(node, 'table'),
      ),
      TutorialPracticeCheck.selectBeforeFrom => _appearsBefore(
        nodes,
        BlockType.sqlSelect,
        BlockType.sqlFrom,
      ),
      TutorialPracticeCheck.whereConnected => types.contains(
        BlockType.sqlWhere,
      ),
      TutorialPracticeCheck.whereConfigured => _configured(
        nodes,
        BlockType.sqlWhere,
        (node) => _filterConfigured(graph, node),
      ),
      TutorialPracticeCheck.andConnected => types.contains(BlockType.sqlAnd),
      TutorialPracticeCheck.andConfigured => _configured(
        nodes,
        BlockType.sqlAnd,
        (node) => _filterConfigured(graph, node),
      ),
      TutorialPracticeCheck.whereBeforeAnd => _appearsBefore(
        nodes,
        BlockType.sqlWhere,
        BlockType.sqlAnd,
      ),
      TutorialPracticeCheck.joinConnected => nodes.any(
        (node) => _joinTypes.contains(node.type),
      ),
      TutorialPracticeCheck.joinConfigured =>
        nodes
            .where((node) => _joinTypes.contains(node.type))
            .any(
              (node) =>
                  graph.inputConfigured(node, 'table') &&
                  (_semanticText(node.inputs['on']) ||
                      (graph.inputConfigured(node, 'left_column') &&
                          graph.inputConfigured(node, 'right_column') &&
                          _comparisonOperatorConfigured(
                            node.inputs['operator'],
                          ))),
            ),
      TutorialPracticeCheck.groupByConnected => types.contains(
        BlockType.sqlGroupBy,
      ),
      TutorialPracticeCheck.groupByConfigured => _configured(
        nodes,
        BlockType.sqlGroupBy,
        (node) =>
            graph.inputConfigured(node, 'column') ||
            graph.inputConfigured(node, 'expr'),
      ),
      TutorialPracticeCheck.havingConnected => types.contains(
        BlockType.sqlHaving,
      ),
      TutorialPracticeCheck.havingConfigured => _configured(
        nodes,
        BlockType.sqlHaving,
        (node) => _havingConfigured(graph, node),
      ),
      TutorialPracticeCheck.groupBeforeHaving => _appearsBefore(
        nodes,
        BlockType.sqlGroupBy,
        BlockType.sqlHaving,
      ),
      TutorialPracticeCheck.unionConnected => types.contains(
        BlockType.sqlUnion,
      ),
      TutorialPracticeCheck.unionConfigured => _configured(
        nodes,
        BlockType.sqlUnion,
        _setQueryConfigured,
      ),
      TutorialPracticeCheck.unionBeforeOrder => _appearsBefore(
        nodes,
        BlockType.sqlUnion,
        BlockType.sqlOrderBy,
      ),
      TutorialPracticeCheck.orderByConnected => types.contains(
        BlockType.sqlOrderBy,
      ),
      TutorialPracticeCheck.orderByConfigured => _configured(
        nodes,
        BlockType.sqlOrderBy,
        (node) =>
            (graph.inputConfigured(node, 'column') ||
                graph.inputConfigured(node, 'expr')) &&
            _validOrder(node.inputs['order']),
      ),
      TutorialPracticeCheck.limitConnected => types.contains(
        BlockType.sqlLimit,
      ),
      TutorialPracticeCheck.limitConfigured => _configured(
        nodes,
        BlockType.sqlLimit,
        (node) => _positiveInteger(node.inputs['count']),
      ),
      TutorialPracticeCheck.orderBeforeLimit => _appearsBefore(
        nodes,
        BlockType.sqlOrderBy,
        BlockType.sqlLimit,
      ),
      TutorialPracticeCheck.selectColumnReporter =>
        nodes
            .where((node) => node.type == BlockType.sqlSelect)
            .any(
              (node) =>
                  graph.reporterFor(node, 'columns')?.type ==
                      BlockType.sqlColumn &&
                  graph.inputConfigured(node, 'columns', allowWildcard: true),
            ),
      TutorialPracticeCheck.whereTextReporter =>
        nodes
            .where((node) => node.type == BlockType.sqlWhere)
            .any(
              (node) =>
                  graph.reporterFor(node, 'value')?.type == BlockType.sqlText &&
                  graph.inputConfigured(node, 'value'),
            ),
      TutorialPracticeCheck.orConnected => types.contains(BlockType.sqlOr),
      TutorialPracticeCheck.orConfigured => _configured(
        nodes,
        BlockType.sqlOr,
        (node) => _filterConfigured(graph, node),
      ),
      TutorialPracticeCheck.whereBeforeOr => _appearsBefore(
        nodes,
        BlockType.sqlWhere,
        BlockType.sqlOr,
      ),
      TutorialPracticeCheck.selectDistinct => _configured(
        nodes,
        BlockType.sqlSelect,
        (node) =>
            node.inputs['distinct'] == true ||
            '${node.inputs['select_mode'] ?? ''}'.trim().toUpperCase() ==
                'DISTINCT',
      ),
      TutorialPracticeCheck.selectAggregateReporter =>
        nodes.where((node) => node.type == BlockType.sqlSelect).any((node) {
          final reporter = graph.reporterFor(node, 'columns');
          return reporter != null &&
              _aggregateTypes.contains(reporter.type) &&
              graph.inputConfigured(node, 'columns');
        }),
      TutorialPracticeCheck.selectAliasReporter =>
        nodes.where((node) => node.type == BlockType.sqlSelect).any((node) {
          final reporter = graph.reporterFor(node, 'columns');
          return reporter?.type == BlockType.sqlAlias &&
              graph.inputConfigured(node, 'columns');
        }),
      TutorialPracticeCheck.intersectConnected => types.contains(
        BlockType.sqlIntersect,
      ),
      TutorialPracticeCheck.intersectConfigured => _configured(
        nodes,
        BlockType.sqlIntersect,
        _setQueryConfigured,
      ),
      TutorialPracticeCheck.exceptConnected => types.contains(
        BlockType.sqlExcept,
      ),
      TutorialPracticeCheck.exceptConfigured => _configured(
        nodes,
        BlockType.sqlExcept,
        _setQueryConfigured,
      ),
      TutorialPracticeCheck.unionAllConfigured => _configured(
        nodes,
        BlockType.sqlUnion,
        (node) =>
            _setQueryConfigured(node) &&
            (node.inputs['all'] == true ||
                '${node.inputs['set_mode'] ?? ''}'.trim().toUpperCase() ==
                    'ALL'),
      ),
      TutorialPracticeCheck.selectLiteralReporter =>
        nodes.where((node) => node.type == BlockType.sqlSelect).any((node) {
          final reporter = graph.reporterFor(node, 'columns');
          return reporter?.type == BlockType.sqlText &&
              graph.inputConfigured(node, 'columns');
        }),
      TutorialPracticeCheck.insertConnected => types.contains(
        BlockType.sqlInsert,
      ),
      TutorialPracticeCheck.insertConfigured => _configured(
        nodes,
        BlockType.sqlInsert,
        _insertConfigured,
      ),
      TutorialPracticeCheck.updateConnected => types.contains(
        BlockType.sqlUpdate,
      ),
      TutorialPracticeCheck.updateConfigured => _configured(
        nodes,
        BlockType.sqlUpdate,
        _updateConfigured,
      ),
      TutorialPracticeCheck.deleteConnected => types.contains(
        BlockType.sqlDelete,
      ),
      TutorialPracticeCheck.deleteConfigured => _configured(
        nodes,
        BlockType.sqlDelete,
        _deleteConfigured,
      ),
      TutorialPracticeCheck.createTableConnected => types.contains(
        BlockType.sqlCreateTable,
      ),
      TutorialPracticeCheck.createTableConfigured => _configured(
        nodes,
        BlockType.sqlCreateTable,
        _createTableConfigured,
      ),
      TutorialPracticeCheck.createIndexConnected => types.contains(
        BlockType.sqlCreateIndex,
      ),
      TutorialPracticeCheck.createIndexConfigured => _configured(
        nodes,
        BlockType.sqlCreateIndex,
        _createIndexConfigured,
      ),
      TutorialPracticeCheck.createViewConnected => types.contains(
        BlockType.sqlCreateView,
      ),
      TutorialPracticeCheck.createViewConfigured => _configured(
        nodes,
        BlockType.sqlCreateView,
        _createViewConfigured,
      ),
      TutorialPracticeCheck.beginTransactionConnected => types.contains(
        BlockType.sqlBeginTransaction,
      ),
      TutorialPracticeCheck.savepointConnected => types.contains(
        BlockType.sqlSavepoint,
      ),
      TutorialPracticeCheck.savepointConfigured => _configured(
        nodes,
        BlockType.sqlSavepoint,
        (node) => _semanticText(node.inputs['name']),
      ),
      TutorialPracticeCheck.rollbackToSavepointConnected => types.contains(
        BlockType.sqlRollbackToSavepoint,
      ),
      TutorialPracticeCheck.releaseSavepointConnected => types.contains(
        BlockType.sqlReleaseSavepoint,
      ),
      TutorialPracticeCheck.commitConnected => types.contains(
        BlockType.sqlCommit,
      ),
      TutorialPracticeCheck.transactionOrderValid =>
        _appearsBefore(
              nodes,
              BlockType.sqlBeginTransaction,
              BlockType.sqlSavepoint,
            ) &&
            _appearsBefore(
              nodes,
              BlockType.sqlSavepoint,
              BlockType.sqlRollbackToSavepoint,
            ) &&
            _appearsBefore(
              nodes,
              BlockType.sqlRollbackToSavepoint,
              BlockType.sqlReleaseSavepoint,
            ) &&
            _appearsBefore(
              nodes,
              BlockType.sqlReleaseSavepoint,
              BlockType.sqlCommit,
            ),
      TutorialPracticeCheck.queryExecuted => false,
    };
  }
}

class TutorialPracticeResult {
  const TutorialPracticeResult(this.outcomes);

  final Map<TutorialPracticeCheck, bool> outcomes;

  int get completedCount => outcomes.values.where((value) => value).length;
  int get totalCount => outcomes.length;
  bool get complete => completedCount == totalCount;
}

class TutorialPracticeSession {
  const TutorialPracticeSession({
    required this.mode,
    this.stepIndex = 0,
    this.completedSteps = const <int>{},
    this.showHint = false,
    this.attempted = false,
    this.completed = false,
  });

  final TutorialKnowledgeMode mode;
  final int stepIndex;
  final Set<int> completedSteps;
  final bool showHint;
  final bool attempted;
  final bool completed;

  TutorialPracticeSession copyWith({
    int? stepIndex,
    Set<int>? completedSteps,
    bool? showHint,
    bool? attempted,
    bool? completed,
  }) => TutorialPracticeSession(
    mode: mode,
    stepIndex: stepIndex ?? this.stepIndex,
    completedSteps: completedSteps ?? this.completedSteps,
    showHint: showHint ?? this.showHint,
    attempted: attempted ?? this.attempted,
    completed: completed ?? this.completed,
  );
}

const tutorialPracticeDefinitions =
    <TutorialKnowledgeMode, TutorialPracticeDefinition>{
      TutorialKnowledgeMode.selectAndSimpleFilters: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.selectAndSimpleFilters,
        simpleStarter: [],
        advancedStarter: [],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.selectConnected,
              TutorialPracticeCheck.selectConfigured,
            ],
            starterSeeds: [],
            focusNodes: [BlockType.eventGreenFlag, BlockType.sqlSelect],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
            ],
            starterSeeds: [_beginnerSelectDirect],
            focusNodes: [BlockType.sqlWhere],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.selectConnected,
              TutorialPracticeCheck.selectConfigured,
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [BlockType.sqlSelect, BlockType.sqlWhere],
            estimatedMinutes: 4,
          ),
        ],
      ),
      TutorialKnowledgeMode.dataTypes: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.dataTypes,
        simpleStarter: [_beginnerSelectDirect],
        advancedStarter: [_beginnerSelectDirect],
        steps: [
          TutorialPracticeStep(
            checks: [TutorialPracticeCheck.selectLiteralReporter],
            focusNodes: [BlockType.sqlText],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
              TutorialPracticeCheck.whereTextReporter,
            ],
            starterSeeds: [_beginnerSelectDirect, _beginnerWhereDirect],
            focusNodes: [BlockType.sqlText, BlockType.sqlWhere],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.selectConnected,
              TutorialPracticeCheck.selectLiteralReporter,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [_literalSelect],
            startFresh: true,
            focusNodes: [BlockType.sqlText],
          ),
        ],
      ),
      TutorialKnowledgeMode.advancedFilters: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.advancedFilters,
        simpleStarter: [_beginnerSelectDirect, _beginnerWhereDirect],
        advancedStarter: [_beginnerSelectDirect, _beginnerWhereDirect],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.andConnected,
              TutorialPracticeCheck.andConfigured,
              TutorialPracticeCheck.whereBeforeAnd,
            ],
            focusNodes: [BlockType.sqlAnd],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.orConnected,
              TutorialPracticeCheck.orConfigured,
              TutorialPracticeCheck.whereBeforeOr,
            ],
            starterSeeds: [
              _beginnerSelectDirect,
              _beginnerWhereDirect,
              _beginnerAnd,
            ],
            focusNodes: [BlockType.sqlOr],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
              TutorialPracticeCheck.andConnected,
              TutorialPracticeCheck.andConfigured,
              TutorialPracticeCheck.orConnected,
              TutorialPracticeCheck.orConfigured,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [BlockType.sqlWhere, BlockType.sqlAnd, BlockType.sqlOr],
            estimatedMinutes: 5,
          ),
        ],
      ),
      TutorialKnowledgeMode.sortingAndWhere: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.sortingAndWhere,
        simpleStarter: [_beginnerSelectDirect, _beginnerWhereDirect],
        advancedStarter: [_beginnerSelectDirect, _beginnerWhereDirect],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.orderByConnected,
              TutorialPracticeCheck.orderByConfigured,
            ],
            focusNodes: [BlockType.sqlOrderBy],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.limitConnected,
              TutorialPracticeCheck.limitConfigured,
              TutorialPracticeCheck.orderBeforeLimit,
            ],
            starterSeeds: [
              _beginnerSelectDirect,
              _beginnerWhereDirect,
              _beginnerOrder,
            ],
            focusNodes: [BlockType.sqlLimit],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
              TutorialPracticeCheck.orderByConnected,
              TutorialPracticeCheck.orderByConfigured,
              TutorialPracticeCheck.limitConnected,
              TutorialPracticeCheck.limitConfigured,
              TutorialPracticeCheck.orderBeforeLimit,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [
              BlockType.sqlWhere,
              BlockType.sqlOrderBy,
              BlockType.sqlLimit,
            ],
            estimatedMinutes: 5,
          ),
        ],
      ),
      TutorialKnowledgeMode.complexQueries: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.complexQueries,
        simpleStarter: [_joinSelect, _customersFrom],
        advancedStarter: [_joinSelect, _customersFrom],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.joinConnected,
              TutorialPracticeCheck.joinConfigured,
            ],
            focusNodes: [BlockType.sqlJoin],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.groupByConnected,
              TutorialPracticeCheck.groupByConfigured,
              TutorialPracticeCheck.havingConnected,
              TutorialPracticeCheck.havingConfigured,
              TutorialPracticeCheck.groupBeforeHaving,
            ],
            starterSeeds: [_joinCountSelect, _customersFrom, _ordersJoin],
            focusNodes: [BlockType.sqlGroupBy, BlockType.sqlHaving],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.unionConnected,
              TutorialPracticeCheck.unionConfigured,
            ],
            starterSeeds: [_inlineSelect],
            startFresh: true,
            focusNodes: [BlockType.sqlUnion],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.selectAggregateReporter,
              TutorialPracticeCheck.joinConnected,
              TutorialPracticeCheck.joinConfigured,
              TutorialPracticeCheck.groupByConnected,
              TutorialPracticeCheck.groupByConfigured,
              TutorialPracticeCheck.havingConnected,
              TutorialPracticeCheck.havingConfigured,
              TutorialPracticeCheck.groupBeforeHaving,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [_joinSelect, _customersFrom],
            startFresh: true,
            focusNodes: [
              BlockType.sqlJoin,
              BlockType.sqlCount,
              BlockType.sqlGroupBy,
              BlockType.sqlHaving,
            ],
            estimatedMinutes: 6,
          ),
        ],
      ),
      TutorialKnowledgeMode.dataManipulation: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.dataManipulation,
        simpleStarter: [],
        advancedStarter: [],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.insertConnected,
              TutorialPracticeCheck.insertConfigured,
            ],
            starterSeeds: [],
            focusNodes: [BlockType.sqlInsert],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.updateConnected,
              TutorialPracticeCheck.updateConfigured,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [BlockType.sqlUpdate],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.deleteConnected,
              TutorialPracticeCheck.deleteConfigured,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [BlockType.sqlDelete],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.insertConfigured,
              TutorialPracticeCheck.updateConfigured,
              TutorialPracticeCheck.deleteConfigured,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [_workshopInsert, _workshopUpdate, _workshopDelete],
            startFresh: true,
            focusNodes: [
              BlockType.sqlInsert,
              BlockType.sqlUpdate,
              BlockType.sqlDelete,
            ],
            estimatedMinutes: 5,
          ),
        ],
      ),
      TutorialKnowledgeMode.schemaObjects: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.schemaObjects,
        simpleStarter: [],
        advancedStarter: [],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.createTableConnected,
              TutorialPracticeCheck.createTableConfigured,
            ],
            starterSeeds: [],
            focusNodes: [BlockType.sqlCreateTable],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.createIndexConnected,
              TutorialPracticeCheck.createIndexConfigured,
            ],
            starterSeeds: [_workshopCreateTable],
            startFresh: true,
            focusNodes: [BlockType.sqlCreateIndex],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.createViewConnected,
              TutorialPracticeCheck.createViewConfigured,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [BlockType.sqlCreateView],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.createTableConfigured,
              TutorialPracticeCheck.createIndexConfigured,
              TutorialPracticeCheck.createViewConfigured,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [
              _workshopCreateTable,
              _workshopCreateIndex,
              _workshopCreateView,
            ],
            startFresh: true,
            focusNodes: [
              BlockType.sqlCreateTable,
              BlockType.sqlCreateIndex,
              BlockType.sqlCreateView,
            ],
            estimatedMinutes: 5,
          ),
        ],
      ),
      TutorialKnowledgeMode.transactions: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.transactions,
        simpleStarter: [],
        advancedStarter: [],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.beginTransactionConnected,
              TutorialPracticeCheck.commitConnected,
            ],
            starterSeeds: [],
            focusNodes: [BlockType.sqlBeginTransaction, BlockType.sqlCommit],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.savepointConnected,
              TutorialPracticeCheck.savepointConfigured,
              TutorialPracticeCheck.rollbackToSavepointConnected,
              TutorialPracticeCheck.releaseSavepointConnected,
            ],
            starterSeeds: [],
            startFresh: true,
            focusNodes: [
              BlockType.sqlSavepoint,
              BlockType.sqlRollbackToSavepoint,
              BlockType.sqlReleaseSavepoint,
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.beginTransactionConnected,
              TutorialPracticeCheck.savepointConfigured,
              TutorialPracticeCheck.rollbackToSavepointConnected,
              TutorialPracticeCheck.releaseSavepointConnected,
              TutorialPracticeCheck.commitConnected,
              TutorialPracticeCheck.transactionOrderValid,
              TutorialPracticeCheck.queryExecuted,
            ],
            starterSeeds: [
              _workshopBegin,
              _workshopSavepoint,
              _workshopUpdateInTransaction,
              _workshopRollbackToSavepoint,
              _workshopReleaseSavepoint,
              _workshopCommit,
            ],
            startFresh: true,
            focusNodes: [
              BlockType.sqlBeginTransaction,
              BlockType.sqlSavepoint,
              BlockType.sqlRollbackToSavepoint,
              BlockType.sqlCommit,
            ],
            estimatedMinutes: 5,
          ),
        ],
      ),
    };

const _beginnerSelectDirect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'name',
  'table': 'customers',
  'separate_from': false,
});

const _beginnerWhereDirect = TutorialPracticeSeed(BlockType.sqlWhere, {
  'column': 'city',
  'operator': '=',
  'value': 'Berlin',
  'predicate': '',
});

const _beginnerAnd = TutorialPracticeSeed(BlockType.sqlAnd, {
  'column': 'active',
  'operator': '=',
  'value': '1',
  'predicate': '',
});

const _beginnerOrder = TutorialPracticeSeed(BlockType.sqlOrderBy, {
  'column': 'name',
  'order': 'ASC',
  'expr': 'name ASC',
});

const _joinSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'customers.name, orders.total',
  'table': 'customers',
  'separate_from': true,
});
const _joinCountSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': '',
  'table': 'customers',
  'separate_from': true,
  reporterInputsKey: {
    'columns': {
      'kind': 'OperatorBlock',
      'id': 'tutorial_order_count',
      'type': 'sqlCount',
      'position': {'dx': 0, 'dy': 0},
      'next': null,
      'children': <Object>[],
      'inputs': {'column': '*'},
    },
  },
});
const _customersFrom = TutorialPracticeSeed(BlockType.sqlFrom, {
  'table': 'customers',
});
const _ordersJoin = TutorialPracticeSeed(BlockType.sqlInnerJoin, {
  'table': 'orders',
  'left_column': 'customers.id',
  'operator': '=',
  'right_column': 'orders.customer_id',
  'on': 'customers.id = orders.customer_id',
});
const _inlineSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'id, name',
  'table': 'customers',
  'separate_from': false,
});
const _literalSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': '',
  'table': 'customers',
  'separate_from': false,
  reporterInputsKey: {
    'columns': {
      'kind': 'OperatorBlock',
      'id': 'tutorial_literal_text',
      'type': 'sqlText',
      'position': {'dx': 0, 'dy': 0},
      'next': null,
      'children': <Object>[],
      'inputs': {'literal_type': 'text', 'text': 'SQLite'},
    },
  },
});

const _workshopInsert = TutorialPracticeSeed(BlockType.sqlInsert, {
  'table': 'archived_customers',
  'columns': 'id, name',
  'values': "(999, 'Workshop')",
});
const _workshopUpdate = TutorialPracticeSeed(BlockType.sqlUpdate, {
  'table': 'archived_customers',
  'column': 'name',
  'value': "'NodeQL Workshop'",
  'where_column': 'id',
  'operator': '=',
  'where_value': '999',
});
const _workshopDelete = TutorialPracticeSeed(BlockType.sqlDelete, {
  'table': 'archived_customers',
  'where_column': 'id',
  'operator': '=',
  'where_value': '999',
});

const _workshopCreateTable = TutorialPracticeSeed(BlockType.sqlCreateTable, {
  'if_not_exists': 'IF NOT EXISTS',
  'table': 'workshop_notes',
  'definition': 'id INTEGER PRIMARY KEY, note TEXT NOT NULL',
});
const _workshopCreateIndex = TutorialPracticeSeed(BlockType.sqlCreateIndex, {
  'if_not_exists': 'IF NOT EXISTS',
  'name': 'idx_workshop_notes_note',
  'table': 'workshop_notes',
  'columns': 'note',
});
const _workshopCreateView = TutorialPracticeSeed(BlockType.sqlCreateView, {
  'if_not_exists': 'IF NOT EXISTS',
  'name': 'active_customers',
  'sql': 'SELECT id, name FROM customers WHERE active = 1',
});

const _workshopBegin = TutorialPracticeSeed(BlockType.sqlBeginTransaction, {
  'behavior': 'DEFERRED',
});
const _workshopSavepoint = TutorialPracticeSeed(BlockType.sqlSavepoint, {
  'name': 'workshop_point',
});
const _workshopUpdateInTransaction = TutorialPracticeSeed(BlockType.sqlUpdate, {
  'table': 'customers',
  'column': 'city',
  'value': "'Temporary City'",
  'where_column': 'id',
  'operator': '=',
  'where_value': '1',
});
const _workshopRollbackToSavepoint = TutorialPracticeSeed(
  BlockType.sqlRollbackToSavepoint,
  {'name': 'workshop_point'},
);
const _workshopReleaseSavepoint = TutorialPracticeSeed(
  BlockType.sqlReleaseSavepoint,
  {'name': 'workshop_point'},
);
const _workshopCommit = TutorialPracticeSeed(BlockType.sqlCommit);

const _joinTypes = <BlockType>{
  BlockType.sqlJoin,
  BlockType.sqlInnerJoin,
  BlockType.sqlLeftJoin,
  BlockType.sqlRightJoin,
  BlockType.sqlFullJoin,
  BlockType.sqlCrossJoin,
  BlockType.sqlSelfJoin,
  BlockType.sqlNaturalJoin,
};

const _aggregateTypes = <BlockType>{
  BlockType.sqlCount,
  BlockType.sqlSum,
  BlockType.sqlAvg,
  BlockType.sqlMin,
  BlockType.sqlMax,
};

bool _setQueryConfigured(BlockNode node) => RegExp(
  r'^\s*select\s+\S',
  caseSensitive: false,
).hasMatch('${node.inputs['sql'] ?? ''}');

bool _insertConfigured(BlockNode node) =>
    _semanticText(node.inputs['table']) &&
    _semanticText(node.inputs['columns']) &&
    _semanticText(node.inputs['values']);

bool _updateConfigured(BlockNode node) =>
    _semanticText(node.inputs['table']) &&
    _semanticText(node.inputs['column']) &&
    _semanticText(node.inputs['value']) &&
    _semanticText(node.inputs['where_column']) &&
    _comparisonOperatorConfigured(node.inputs['operator']) &&
    _semanticText(node.inputs['where_value']);

bool _deleteConfigured(BlockNode node) =>
    _semanticText(node.inputs['table']) &&
    _semanticText(node.inputs['where_column']) &&
    _comparisonOperatorConfigured(node.inputs['operator']) &&
    _semanticText(node.inputs['where_value']);

bool _createTableConfigured(BlockNode node) =>
    _semanticText(node.inputs['table']) &&
    _semanticText(node.inputs['definition']);

bool _createIndexConfigured(BlockNode node) =>
    _semanticText(node.inputs['name']) &&
    _semanticText(node.inputs['table']) &&
    _semanticText(node.inputs['columns']);

bool _createViewConfigured(BlockNode node) =>
    _semanticText(node.inputs['name']) && _setQueryConfigured(node);

const _placeholderValues = <String>{
  '',
  'table_name',
  'column_name',
  'column',
  'columns',
  'value',
  'alias',
  'enter value',
  '1 = 1',
  'new_table',
  'index_name',
  'view_name',
};

const _comparisonOperators = <String>{
  '=',
  '!=',
  '<>',
  '>',
  '>=',
  '<',
  '<=',
  'LIKE',
  'NOT LIKE',
  'IN',
  'NOT IN',
  'BETWEEN',
  'NOT BETWEEN',
  'IS',
  'IS NOT',
  'IS NULL',
  'IS NOT NULL',
};

bool _semanticText(Object? value, {bool allowWildcard = false}) {
  if (value == null) return false;
  final text = '$value'.trim();
  if (text.isEmpty) return false;
  if (allowWildcard && text == '*') return true;
  return !_placeholderValues.contains(text.toLowerCase());
}

bool _filterConfigured(TutorialPracticeGraph graph, BlockNode node) {
  final conditions = node.inputs['conditions'];
  if (conditions is List &&
      conditions.isNotEmpty &&
      conditions.every(_structuredConditionConfigured)) {
    return true;
  }
  if (_semanticText(node.inputs['predicate'])) return true;
  final operator = '${node.inputs['operator'] ?? ''}'.trim().toUpperCase();
  if (!graph.inputConfigured(node, 'column') ||
      !_comparisonOperatorConfigured(operator)) {
    return false;
  }
  if (operator == 'IS NULL' || operator == 'IS NOT NULL') return true;
  return graph.inputConfigured(node, 'value');
}

bool _structuredConditionConfigured(Object? raw) {
  if (raw is! Map) return false;
  final nested = raw['conditions'];
  if (nested is List && nested.isNotEmpty) {
    return nested.every(_structuredConditionConfigured);
  }
  final operator = '${raw['operator'] ?? ''}'.trim().toUpperCase();
  if (!_semanticText(raw['column']) ||
      !_comparisonOperatorConfigured(operator)) {
    return false;
  }
  return operator == 'IS NULL' ||
      operator == 'IS NOT NULL' ||
      _semanticText(raw['value']);
}

bool _havingConfigured(TutorialPracticeGraph graph, BlockNode node) {
  final hasStructuredFields =
      node.inputs.containsKey('aggregate') ||
      node.inputs.containsKey('expr') ||
      node.inputs.containsKey('operator') ||
      node.inputs.containsKey('value');
  if (!hasStructuredFields) return _semanticText(node.inputs['predicate']);
  final expressionConfigured =
      graph.inputConfigured(node, 'aggregate', allowWildcard: true) ||
      graph.inputConfigured(node, 'expr', allowWildcard: true);
  final operator = '${node.inputs['operator'] ?? ''}'.trim();
  return expressionConfigured &&
      _comparisonOperatorConfigured(operator) &&
      graph.inputConfigured(node, 'value');
}

bool _comparisonOperatorConfigured(Object? value) =>
    _comparisonOperators.contains('${value ?? ''}'.trim().toUpperCase());

bool _validOrder(Object? value) {
  final order = '${value ?? 'ASC'}'.trim().toUpperCase();
  return order == 'ASC' || order == 'DESC';
}

bool _positiveInteger(Object? value) {
  final parsed = int.tryParse('${value ?? ''}'.trim());
  return parsed != null && parsed > 0;
}

bool _configured(
  List<BlockNode> nodes,
  BlockType type,
  bool Function(BlockNode node) validate,
) => nodes.where((node) => node.type == type).any(validate);

bool _appearsBefore(List<BlockNode> nodes, BlockType first, BlockType second) {
  var foundFirst = false;
  for (final node in nodes) {
    if (node.type == first) foundFirst = true;
    if (node.type == second) return foundFirst;
  }
  return false;
}

class TutorialPracticeGraph {
  TutorialPracticeGraph._({required this.statements, required this.reporters});

  factory TutorialPracticeGraph.fromRoots(List<BlockNode> roots) {
    final statements = <BlockNode>[];
    final reporters = <String, BlockNode>{};
    final visitedStatements = <String>{};
    final visitedReporters = <String>{};

    void collectReporters(BlockNode owner) {
      final raw = owner.inputs[reporterInputsKey];
      if (raw is! Map) return;
      for (final entry in raw.entries) {
        final encoded = entry.value;
        if (encoded is! Map) continue;
        final reporter = BlockNode.fromJson(Map<String, dynamic>.from(encoded));
        reporters[_reporterKey(owner, '${entry.key}')] = reporter;
        if (visitedReporters.add(reporter.id)) collectReporters(reporter);
      }
    }

    void walk(BlockNode? node) {
      var current = node;
      while (current != null && visitedStatements.add(current.id)) {
        statements.add(current);
        collectReporters(current);
        for (final child in current.children) {
          walk(child);
        }
        current = current.next;
      }
    }

    for (final root in roots.whereType<EventBlock>()) {
      walk(root.next);
    }
    return TutorialPracticeGraph._(
      statements: List.unmodifiable(statements),
      reporters: Map.unmodifiable(reporters),
    );
  }

  final List<BlockNode> statements;
  final Map<String, BlockNode> reporters;

  BlockNode? reporterFor(BlockNode owner, String inputKey) =>
      reporters[_reporterKey(owner, inputKey)];

  bool inputConfigured(
    BlockNode node,
    String inputKey, {
    bool allowWildcard = false,
  }) {
    final reporter = reporterFor(node, inputKey);
    if (reporter != null && _reporterConfigured(reporter, <String>{})) {
      return true;
    }
    return _semanticText(node.inputs[inputKey], allowWildcard: allowWildcard);
  }

  bool _reporterConfigured(BlockNode reporter, Set<String> visited) {
    if (!visited.add(reporter.id)) return false;
    final nestedKey = primaryReporterInputKey(reporter.type);
    final nested = nestedKey == null ? null : reporterFor(reporter, nestedKey);
    final nestedConfigured = nested != null
        ? _reporterConfigured(nested, visited)
        : nestedKey != null &&
              _semanticText(reporter.inputs[nestedKey], allowWildcard: true);
    return switch (reporter.type) {
      BlockType.sqlColumn => _semanticText(
        reporter.inputs['column'],
        allowWildcard: true,
      ),
      BlockType.sqlText => _semanticText(reporter.inputs['text']),
      BlockType.sqlAlias =>
        _semanticText(reporter.inputs['alias']) &&
            (nestedConfigured || _semanticText(reporter.inputs['value'])),
      BlockType.sqlCount ||
      BlockType.sqlSum ||
      BlockType.sqlAvg ||
      BlockType.sqlMin ||
      BlockType.sqlMax =>
        nestedConfigured ||
            _semanticText(
              reporter.inputs['column'] ?? reporter.inputs['expr'],
              allowWildcard: true,
            ),
      BlockType.sqlCurrentDate ||
      BlockType.sqlCurrentTime ||
      BlockType.sqlCurrentTimestamp => true,
      _ =>
        nestedConfigured ||
            reporter.inputs.entries.any(
              (entry) =>
                  entry.key != reporterInputsKey &&
                  !entry.key.startsWith('__') &&
                  _semanticText(entry.value, allowWildcard: true),
            ),
    };
  }

  static String _reporterKey(BlockNode owner, String inputKey) =>
      '${owner.id}:$inputKey';
}
