import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_interactions.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';

const _input = LearningPathRequirement(
  action: LearningPathAction.enterInput,
  nodeRef: 'select',
  input: 'table',
  value: 'customers',
);
const _connect = LearningPathRequirement(
  action: LearningPathAction.connectNodes,
  nodeRef: 'where',
  otherRef: 'select',
);
const _link = LearningPathRequirement(
  action: LearningPathAction.linkColumns,
  nodeRef: 'where',
  otherRef: 'select',
);
const _attach = LearningPathRequirement(
  action: LearningPathAction.attachReporter,
  nodeRef: 'where',
  otherRef: 'city',
  input: 'value',
);
const _select = LearningPathRequirement(
  action: LearningPathAction.selectNode,
  nodeRef: 'where',
);
const _run = LearningPathRequirement(action: LearningPathAction.runQuery);

const _step = LearningPathStep(
  id: 'filter',
  title: 'Filter rows',
  instruction: 'Build and run a filter.',
  nodes: [
    LearningPathNodeTemplate(ref: 'select', type: BlockType.sqlSelect),
    LearningPathNodeTemplate(ref: 'where', type: BlockType.sqlWhere),
    LearningPathNodeTemplate(ref: 'city', type: BlockType.sqlText),
  ],
  highlights: ['select', 'city'],
  requirements: [_input, _connect, _link, _select, _attach, _run],
);

void main() {
  test(
    'checks input events and live connections when their nodes are introduced',
    () {
      final select = OperatorBlock(
        id: 'select-id',
        position: Offset.zero,
        operatorType: BlockType.sqlSelect,
        inputs: {'table': 'customers'},
      );
      final where = OperatorBlock(
        id: 'where-id',
        position: Offset.zero,
        operatorType: BlockType.sqlWhere,
      );
      final city = OperatorBlock(
        id: 'city-id',
        position: Offset.zero,
        operatorType: BlockType.sqlText,
      );
      final nodes = {'select': select, 'where': where, 'city': city};
      final interactions = <String>{};
      String? columnSource;

      LearningPathRequirement? pending(int index, {bool ran = false}) =>
          pendingLearningPathRequirement(
            step: _step,
            nodeIndex: index,
            findNode: (ref) => nodes[ref],
            columnSourceId: (_) => columnSource,
            interactions: interactions,
            currentQueryRan: ran,
          );

      expect(pending(0), _input);
      interactions.add(
        learningPathInteractionKey(_input.action, select.id, 'table'),
      );
      expect(pending(0), isNull);
      expect(pending(1), _connect);
      select.next = where;
      expect(pending(1), _link);
      columnSource = select.id;
      expect(pending(1), _select);
      interactions.add(learningPathInteractionKey(_select.action, where.id));
      expect(pending(1), isNull);
      expect(pending(2), _attach);
      setReporterForInput(where, 'value', city);
      expect(pending(2), _run);
      expect(pending(2, ran: true), isNull);
      select.inputs['table'] = 'orders';
      expect(pending(2, ran: true), _input);
      select.inputs['table'] = 'customers';
      select.next = null;
      expect(pending(2, ran: true), _connect);
    },
  );

  test(
    'portable bundles round-trip only declared interaction types and references',
    () {
      const path = AuthoredLearningPath(
        id: 'lesson',
        title: 'Filters',
        description: '',
        steps: [_step],
      );
      final bundle = encodeLearningPathBundle([path]);
      expect(bundle, contains('"schemaVersion": 2'));
      final step = validateRemoteWorkshopBundle(bundle).steps.single;
      expect(step.highlights, _step.highlights);
      expect(
        step.requirements.map((rule) => rule.toJson()),
        _step.requirements.map((rule) => rule.toJson()),
      );

      for (final broken in [
        bundle.replaceFirst('"enterInput"', '"runScript"'),
        bundle.replaceFirst('"nodeRef": "select"', '"nodeRef": "missing"'),
        bundle.replaceFirst('"input": "table"', '"input": "../../hidden"'),
        bundle.replaceFirst('"schemaVersion": 2', '"schemaVersion": 1'),
      ]) {
        expect(
          () => validateRemoteWorkshopBundle(broken),
          throwsFormatException,
        );
      }
    },
  );
}
