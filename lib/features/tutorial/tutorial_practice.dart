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
}

class TutorialPracticeStep {
  const TutorialPracticeStep({
    required this.checks,
    this.resumeSeeds = const <TutorialPracticeSeed>[],
    this.starterSeeds,
    this.focusNodes = const <BlockType>[],
    this.estimatedMinutes = 2,
  });

  final List<TutorialPracticeCheck> checks;
  final List<TutorialPracticeSeed> resumeSeeds;
  final List<TutorialPracticeSeed>? starterSeeds;
  final List<BlockType> focusNodes;
  final int estimatedMinutes;
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

  TutorialPracticeResult evaluate(List<BlockNode> roots, int stepIndex) {
    final graph = TutorialPracticeGraph.fromRoots(roots);
    final step = steps[stepIndex.clamp(0, steps.length - 1)];
    return TutorialPracticeResult({
      for (final check in step.checks) check: _evaluate(check, graph),
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
                graph.inputConfigured(node, 'table')),
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
        (node) => RegExp(
          r'^\s*select\b',
          caseSensitive: false,
        ).hasMatch('${node.inputs['sql'] ?? ''}'),
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
      TutorialKnowledgeMode.beginner: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.beginner,
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
            estimatedMinutes: 2,
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.selectConnected,
              TutorialPracticeCheck.selectConfigured,
              TutorialPracticeCheck.selectColumnReporter,
            ],
            starterSeeds: [_beginnerSelectDirect],
            focusNodes: [BlockType.sqlColumn],
            estimatedMinutes: 2,
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
            ],
            starterSeeds: [_beginnerSelectWithReporter],
            focusNodes: [BlockType.sqlWhere],
            estimatedMinutes: 2,
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
              TutorialPracticeCheck.whereTextReporter,
            ],
            starterSeeds: [_beginnerSelectWithReporter, _beginnerWhereDirect],
            focusNodes: [BlockType.sqlText],
            estimatedMinutes: 2,
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.andConnected,
              TutorialPracticeCheck.andConfigured,
              TutorialPracticeCheck.whereBeforeAnd,
            ],
            starterSeeds: [
              _beginnerSelectWithReporter,
              _beginnerWhereWithReporter,
            ],
            focusNodes: [BlockType.sqlAnd],
            estimatedMinutes: 2,
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.orderByConnected,
              TutorialPracticeCheck.orderByConfigured,
            ],
            starterSeeds: [
              _beginnerSelectWithReporter,
              _beginnerWhereWithReporter,
              _beginnerAnd,
            ],
            focusNodes: [BlockType.sqlOrderBy],
            estimatedMinutes: 2,
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.limitConnected,
              TutorialPracticeCheck.limitConfigured,
              TutorialPracticeCheck.orderBeforeLimit,
            ],
            starterSeeds: [
              _beginnerSelectWithReporter,
              _beginnerWhereWithReporter,
              _beginnerAnd,
              _beginnerOrder,
            ],
            focusNodes: [BlockType.sqlLimit],
            estimatedMinutes: 3,
          ),
        ],
      ),
      TutorialKnowledgeMode.beginnerSyntax: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.beginnerSyntax,
        simpleStarter: [_separateSelect],
        advancedStarter: [_separateSelect],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.fromConnected,
              TutorialPracticeCheck.fromConfigured,
              TutorialPracticeCheck.selectBeforeFrom,
            ],
            resumeSeeds: [
              TutorialPracticeSeed(BlockType.sqlFrom, {'table': 'customers'}),
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.whereConnected,
              TutorialPracticeCheck.whereConfigured,
            ],
            resumeSeeds: [
              TutorialPracticeSeed(BlockType.sqlWhere, {
                'column': 'country',
                'operator': '=',
                'value': 'DE',
                'predicate': "country = 'DE'",
              }),
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.andConnected,
              TutorialPracticeCheck.andConfigured,
              TutorialPracticeCheck.whereBeforeAnd,
            ],
            resumeSeeds: [],
          ),
        ],
      ),
      TutorialKnowledgeMode.intermediate: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.intermediate,
        simpleStarter: [_joinSelect, _customersFrom],
        advancedStarter: [_joinSelect, _customersFrom],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.joinConnected,
              TutorialPracticeCheck.joinConfigured,
            ],
            resumeSeeds: [
              TutorialPracticeSeed(BlockType.sqlInnerJoin, {
                'table': 'orders',
                'left_column': 'customers.id',
                'operator': '=',
                'right_column': 'orders.customer_id',
                'on': 'customers.id = orders.customer_id',
              }),
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.groupByConnected,
              TutorialPracticeCheck.groupByConfigured,
            ],
            resumeSeeds: [
              TutorialPracticeSeed(BlockType.sqlGroupBy, {
                'column': 'customers.name',
                'expr': 'customers.name',
              }),
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.havingConnected,
              TutorialPracticeCheck.havingConfigured,
              TutorialPracticeCheck.groupBeforeHaving,
            ],
            resumeSeeds: [],
          ),
        ],
      ),
      TutorialKnowledgeMode.expert: TutorialPracticeDefinition(
        mode: TutorialKnowledgeMode.expert,
        simpleStarter: [_inlineSelect],
        advancedStarter: [_inlineSelect],
        steps: [
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.unionConnected,
              TutorialPracticeCheck.unionConfigured,
            ],
            resumeSeeds: [
              TutorialPracticeSeed(BlockType.sqlUnion, {
                'sql': 'SELECT id, name FROM archived_customers',
              }),
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.orderByConnected,
              TutorialPracticeCheck.orderByConfigured,
              TutorialPracticeCheck.unionBeforeOrder,
            ],
            resumeSeeds: [
              TutorialPracticeSeed(BlockType.sqlOrderBy, {
                'column': 'name',
                'order': 'ASC',
                'expr': 'name ASC',
              }),
            ],
          ),
          TutorialPracticeStep(
            checks: [
              TutorialPracticeCheck.limitConnected,
              TutorialPracticeCheck.limitConfigured,
              TutorialPracticeCheck.orderBeforeLimit,
            ],
            resumeSeeds: [],
          ),
        ],
      ),
    };

const _beginnerSelectDirect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'name',
  'table': 'customers',
  'separate_from': false,
});

const _beginnerSelectWithReporter = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': '',
  'table': 'customers',
  'separate_from': false,
  reporterInputsKey: {
    'columns': {
      'kind': 'OperatorBlock',
      'id': 'tutorial_beginner_column',
      'type': 'sqlColumn',
      'position': {'dx': 0, 'dy': 0},
      'next': null,
      'children': <Object>[],
      'inputs': {'column': 'name'},
    },
  },
});

const _beginnerWhereDirect = TutorialPracticeSeed(BlockType.sqlWhere, {
  'column': 'city',
  'operator': '=',
  'value': 'Berlin',
  'predicate': '',
});

const _beginnerWhereWithReporter = TutorialPracticeSeed(BlockType.sqlWhere, {
  'column': 'city',
  'operator': '=',
  'value': '',
  'predicate': '',
  reporterInputsKey: {
    'value': {
      'kind': 'OperatorBlock',
      'id': 'tutorial_beginner_text',
      'type': 'sqlText',
      'position': {'dx': 0, 'dy': 0},
      'next': null,
      'children': <Object>[],
      'inputs': {'text': 'Berlin'},
    },
  },
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

const _separateSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'name, city',
  'table': 'customers',
  'separate_from': true,
});
const _joinSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'customers.name, orders.total',
  'table': 'customers',
  'separate_from': true,
});
const _customersFrom = TutorialPracticeSeed(BlockType.sqlFrom, {
  'table': 'customers',
});
const _inlineSelect = TutorialPracticeSeed(BlockType.sqlSelect, {
  'columns': 'id, name',
  'table': 'customers',
  'separate_from': false,
});

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
  if (_semanticText(node.inputs['predicate'])) return true;
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
