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

/// The information available while a workshop mission is checked.
///
/// Custom requirements receive this context, so a tutorial author can add a
/// focused check without coupling a lesson to the workshop UI.
class TutorialPracticeContext {
  const TutorialPracticeContext({
    this.currentSql,
    this.executedSql,
    this.executionSucceeded = false,
  });

  final String? currentSql;
  final String? executedSql;
  final bool executionSucceeded;

  /// Whether the SQL currently represented by the nodes was run successfully.
  bool get currentSqlWasExecuted =>
      executionSucceeded &&
      currentSql != null &&
      currentSql!.trim().isNotEmpty &&
      currentSql!.trim() == executedSql?.trim();
}

/// A predicate used by a custom tutorial requirement.
typedef TutorialPracticeValidator =
    bool Function(TutorialPracticeGraph graph, TutorialPracticeContext context);

/// One visible condition that must be met to complete a workshop mission.
///
/// Prefer [TutorialPracticeRequirement.check] for the built-in SQLite checks.
/// Use [TutorialPracticeRequirement.custom] when a new tutorial needs a very
/// specific rule. The [labelKey] is a normal translation key and is therefore
/// also suitable for custom requirements.
class TutorialPracticeRequirement {
  const TutorialPracticeRequirement.check(this.check)
    : id = null,
      labelKey = null,
      validator = null;

  const TutorialPracticeRequirement.custom({
    required this.id,
    required this.labelKey,
    required this.validator,
  }) : check = null;

  final String? id;
  final TutorialPracticeCheck? check;
  final String? labelKey;
  final TutorialPracticeValidator? validator;

  String get key => id ?? check!.name;

  String get resolvedLabelKey =>
      labelKey ?? 'tutorial.practice.check.${check!.name}';
}

class TutorialPracticeStep {
  const TutorialPracticeStep({
    this.id,
    this.checks = const <TutorialPracticeCheck>[],
    this.requirements = const <TutorialPracticeRequirement>[],
    this.resumeSeeds = const <TutorialPracticeSeed>[],
    this.starterSeeds,
    this.focusNodes = const <BlockType>[],
    this.estimatedMinutes = 2,
    this.startFresh = false,
  }) : assert(checks.length + requirements.length > 0);

  /// Stable mission identifier. It is optional for older tutorials, whose
  /// translation step number remains their identifier.
  final String? id;
  final List<TutorialPracticeCheck> checks;
  final List<TutorialPracticeRequirement> requirements;
  final List<TutorialPracticeSeed> resumeSeeds;
  final List<TutorialPracticeSeed>? starterSeeds;
  final List<BlockType> focusNodes;
  final int estimatedMinutes;
  final bool startFresh;

  List<TutorialPracticeRequirement> get allRequirements =>
      <TutorialPracticeRequirement>[
        for (final check in checks) TutorialPracticeRequirement.check(check),
        ...requirements,
      ];

  bool get requiresExecution => allRequirements.any(
    (requirement) => requirement.check == TutorialPracticeCheck.queryExecuted,
  );
}

class TutorialPracticeDefinition {
  const TutorialPracticeDefinition({
    required this.mode,
    required this.simpleStarter,
    required this.advancedStarter,
    required this.steps,
    this.id,
  });

  final TutorialKnowledgeMode mode;
  final List<TutorialPracticeSeed> simpleStarter;
  final List<TutorialPracticeSeed> advancedStarter;
  final List<TutorialPracticeStep> steps;
  final String? id;

  /// Stable identifier for the workshop catalog and external integrations.
  ///
  /// Progress remains keyed by [TutorialKnowledgeMode] to keep older projects
  /// and saved progress compatible.
  String get tutorialId => id ?? mode.name;
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
    final context = TutorialPracticeContext(
      currentSql: currentSql,
      executedSql: executedSql,
      executionSucceeded: executionSucceeded,
    );
    return TutorialPracticeResult({
      for (final requirement in step.allRequirements)
        requirement: _evaluateRequirement(requirement, graph, context),
    });
  }

  bool _evaluateRequirement(
    TutorialPracticeRequirement requirement,
    TutorialPracticeGraph graph,
    TutorialPracticeContext context,
  ) {
    final check = requirement.check;
    if (check != null) {
      return check == TutorialPracticeCheck.queryExecuted
          ? context.currentSqlWasExecuted
          : _evaluate(check, graph);
    }
    return requirement.validator!(graph, context);
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

/// The metadata needed to put a tutorial on the Workshop overview.
///
/// The existing application keeps [mode] for backwards-compatible progress
/// files. New authors normally only need a mode, a practice definition and the
/// translation keys that already follow the `tutorial.*` convention.
class WorkshopTutorialDefinition {
  const WorkshopTutorialDefinition({
    required this.id,
    required this.mode,
    this.practice,
    this.recommended = false,
    this.estimatedMinutes,
  });

  /// A stable, human-readable id, e.g. `select-and-simple-filters`.
  final String id;
  final TutorialKnowledgeMode mode;
  final TutorialPracticeDefinition? practice;
  final bool recommended;
  final int? estimatedMinutes;

  TutorialWorkshopArea get area => mode.area;
  bool get hasWorkspacePractice => practice != null;
  int get missionCount => practice?.stepCount ?? 0;
  int get resolvedEstimatedMinutes =>
      estimatedMinutes ?? practice?.estimatedMinutes ?? 8;
}

/// Validated, single-source registry for all Workshop paths.
///
/// It deliberately exposes lookups by stable id as well as the legacy enum.
/// This lets new tutorial tooling use ids while existing saved progress remains
/// compatible.
class WorkshopTutorialCatalog {
  WorkshopTutorialCatalog(Iterable<WorkshopTutorialDefinition> tutorials)
    : tutorials = List.unmodifiable(tutorials) {
    final ids = <String>{};
    final modes = <TutorialKnowledgeMode>{};
    for (final tutorial in this.tutorials) {
      if (tutorial.id.trim().isEmpty) {
        throw ArgumentError.value(tutorial.id, 'id', 'must not be empty');
      }
      if (!ids.add(tutorial.id)) {
        throw ArgumentError.value(tutorial.id, 'id', 'must be unique');
      }
      if (!modes.add(tutorial.mode)) {
        throw ArgumentError.value(
          tutorial.mode,
          'mode',
          'may only be used by one tutorial',
        );
      }
      final practice = tutorial.practice;
      if (practice != null && practice.mode != tutorial.mode) {
        throw ArgumentError(
          'Tutorial ${tutorial.id} uses ${tutorial.mode.name}, but its '
          'practice definition uses ${practice.mode.name}.',
        );
      }
      if (practice != null && practice.steps.isEmpty) {
        throw ArgumentError(
          'Tutorial ${tutorial.id} needs at least one mission.',
        );
      }
      final missionIds = <String>{};
      for (final step in practice?.steps ?? const <TutorialPracticeStep>[]) {
        final missionId = step.id;
        if (missionId != null) {
          if (missionId.trim().isEmpty) {
            throw ArgumentError(
              'Tutorial ${tutorial.id} contains an empty mission id.',
            );
          }
          if (!missionIds.add(missionId)) {
            throw ArgumentError(
              'Tutorial ${tutorial.id} contains the mission id $missionId twice.',
            );
          }
        }
        final requirementKeys = <String>{};
        for (final requirement in step.allRequirements) {
          if (!requirementKeys.add(requirement.key)) {
            throw ArgumentError(
              'Mission ${missionId ?? 'unnamed'} in ${tutorial.id} repeats '
              'the requirement ${requirement.key}.',
            );
          }
        }
      }
    }
  }

  final List<WorkshopTutorialDefinition> tutorials;

  Iterable<WorkshopTutorialDefinition> get sqliteTutorials => tutorials.where(
    (tutorial) => tutorial.area == TutorialWorkshopArea.sqlite,
  );

  Iterable<WorkshopTutorialDefinition> get nodeQlTutorials => tutorials.where(
    (tutorial) => tutorial.area == TutorialWorkshopArea.nodeQl,
  );

  int get missionCount => tutorials.fold<int>(
    0,
    (count, tutorial) => count + tutorial.missionCount,
  );

  WorkshopTutorialDefinition? byId(String id) {
    for (final tutorial in tutorials) {
      if (tutorial.id == id) return tutorial;
    }
    return null;
  }

  WorkshopTutorialDefinition? byMode(TutorialKnowledgeMode mode) {
    for (final tutorial in tutorials) {
      if (tutorial.mode == mode) return tutorial;
    }
    return null;
  }

  Map<TutorialKnowledgeMode, TutorialPracticeDefinition> get practiceByMode =>
      Map.unmodifiable({
        for (final tutorial in tutorials) tutorial.mode: ?tutorial.practice,
      });
}

/// Compact authoring helper for the starter and resume nodes of a mission.
TutorialPracticeSeed workshopNode(
  BlockType type, [
  Map<String, dynamic> defaults = const {},
]) => TutorialPracticeSeed(type, defaults);

/// Compact authoring helper for a mission that uses built-in checks.
TutorialPracticeStep workshopMission({
  required String id,
  required List<TutorialPracticeCheck> checks,
  List<TutorialPracticeRequirement> requirements = const [],
  List<TutorialPracticeSeed> resumeSeeds = const [],
  List<TutorialPracticeSeed>? starterSeeds,
  List<BlockType> focusNodes = const [],
  int estimatedMinutes = 2,
  bool startFresh = false,
}) => TutorialPracticeStep(
  id: id,
  checks: checks,
  requirements: requirements,
  resumeSeeds: resumeSeeds,
  starterSeeds: starterSeeds,
  focusNodes: focusNodes,
  estimatedMinutes: estimatedMinutes,
  startFresh: startFresh,
);

class TutorialPracticeResult {
  const TutorialPracticeResult(this.outcomes);

  final Map<TutorialPracticeRequirement, bool> outcomes;

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

/// All paths shown in the Workshop.
///
/// A practical tutorial only needs one [TutorialPracticeDefinition] in
/// [_practiceDefinitions]; it is registered here automatically and appears in
/// the Workshop UI without a second list to maintain.
final workshopTutorialCatalog = WorkshopTutorialCatalog([
  const WorkshopTutorialDefinition(
    id: 'database-tools',
    mode: TutorialKnowledgeMode.databaseTools,
  ),
  const WorkshopTutorialDefinition(
    id: 'plugins',
    mode: TutorialKnowledgeMode.plugins,
  ),
]);

/// Compatibility view for callers that still address lessons by enum.
final Map<TutorialKnowledgeMode, TutorialPracticeDefinition>
tutorialPracticeDefinitions = workshopTutorialCatalog.practiceByMode;

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
