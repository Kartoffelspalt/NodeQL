import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_review.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';

void main() {
  test('all published workshops remain previewable', () {
    final bundle = File('assets/workshops/workshops.json').readAsStringSync();
    for (final path in decodeLearningPathBundle(jsonDecode(bundle))) {
      final review = reviewLearningPath(path);
      expect(
        review.canPreview,
        isTrue,
        reason: '${path.id}: ${review.issues.map((issue) => issue.code)}',
      );
    }
  });

  test('finds ambiguous IDs and dangling references before preview', () {
    final review = reviewLearningPath(
      _path([
        _step(id: 'read'),
        _step(
          id: 'read',
          nodes: const [
            LearningPathNodeTemplate(ref: '', type: BlockType.sqlSelect),
            _select,
            _select,
          ],
          highlights: const ['lost'],
          requirements: const [
            LearningPathRequirement(
              action: LearningPathAction.connectNodes,
              nodeRef: 'select',
              otherRef: 'missing',
            ),
          ],
        ),
      ]),
    );
    expect(review.canPreview, isFalse);
    expect(review.canShare, isFalse);
    expect(review.issues.map((issue) => issue.stepIndex).toSet(), {1});
    expect(
      review.issues.map((issue) => issue.code),
      unorderedEquals([
        LearningPathReviewCode.duplicateStepId,
        LearningPathReviewCode.missingNodeRef,
        LearningPathReviewCode.duplicateNodeRef,
        LearningPathReviewCode.invalidHighlight,
        LearningPathReviewCode.invalidRequirementTarget,
      ]),
    );
  });

  test('finds conditions the learner cannot satisfy together', () {
    final review = reviewLearningPath(
      _path([
        _step(
          nodes: const [_select, _where],
          requirements: const [
            LearningPathRequirement(
              action: LearningPathAction.enterInput,
              nodeRef: 'select',
              input: 'table',
              value: 'customers',
            ),
            LearningPathRequirement(
              action: LearningPathAction.enterInput,
              nodeRef: 'select',
              input: 'table',
              value: 'orders',
            ),
            LearningPathRequirement(
              action: LearningPathAction.enterInput,
              nodeRef: 'where',
              input: 'value',
            ),
            LearningPathRequirement(
              action: LearningPathAction.connectNodes,
              nodeRef: 'select',
              otherRef: 'where',
            ),
          ],
        ),
      ]),
    );
    expect(review.canPreview, isFalse);
    expect(
      review.issues.map((issue) => (issue.code, issue.detail)),
      unorderedEquals([
        (LearningPathReviewCode.conflictingRequirements, 'table'),
        (LearningPathReviewCode.invalidRequirementInput, 'value'),
        (LearningPathReviewCode.incompatibleRequirementNodes, 'select'),
      ]),
    );
  });

  test('preserves the player’s cross-step references and text-only tasks', () {
    final review = reviewLearningPath(
      _path([
        _step(id: 'prepare', nodes: const [_select]),
        _step(
          requirements: const [
            LearningPathRequirement(
              action: LearningPathAction.enterInput,
              nodeRef: 'select',
              input: 'table',
              value: 'customers',
            ),
          ],
        ),
      ]),
    );
    expect(review.canPreview, isTrue);
    expect(review.canShare, isFalse);
    expect(
      review.issues.single.code,
      LearningPathReviewCode.distributionRejected,
    );
    expect(review.issues.single.stepIndex, 1);
    expect(review.issues.single.detail, 'requirements.nodeRef');
    expect(reviewLearningPath(_path([_step()])).canShare, isTrue);
  });

  test('identifies the step and node that cannot be shared', () {
    final path = _path([
      _step(id: 'prepare', nodes: const [_select]),
      _step(
        nodes: const [
          LearningPathNodeTemplate(ref: 'update', type: BlockType.sqlUpdate),
        ],
      ),
    ]);
    final review = reviewLearningPath(path);
    expect(review.canPreview, isTrue);
    expect(review.canShare, isFalse);
    final issue = review.issues.single;
    expect(issue.code, LearningPathReviewCode.distributionRejected);
    expect(issue.stepIndex, 1);
    expect(issue.detail, 'sqlUpdate');
    expect(
      issue.distributionProblem,
      WorkshopDistributionProblem.unsupportedNode,
    );
    expect(
      () => validateRemoteWorkshopBundle(encodeLearningPathBundle([path])),
      throwsFormatException,
    );
  });

  test('identifies unsupported defaults without exposing their values', () {
    final review = reviewLearningPath(
      _path([
        _step(
          nodes: const [
            LearningPathNodeTemplate(
              ref: 'select',
              type: BlockType.sqlSelect,
              defaults: {'private_sql': 'SELECT * FROM sample'},
            ),
          ],
        ),
      ]),
    );
    final issue = review.issues.single;
    expect(
      issue.distributionProblem,
      WorkshopDistributionProblem.unsupportedDefault,
    );
    expect(issue.detail, 'sqlSelect.private_sql');
  });

  test('checks the exact classroom step limit', () {
    AuthoredLearningPath pathWithSteps(int count) => _path([
      for (var index = 0; index < count; index++) _step(id: 'step-$index'),
    ]);
    expect(reviewLearningPath(pathWithSteps(32)).canShare, isTrue);
    final review = reviewLearningPath(pathWithSteps(33));
    expect(review.canPreview, isTrue);
    expect(
      review.issues.single.distributionProblem,
      WorkshopDistributionProblem.tooManySteps,
    );
  });
}

const _select = LearningPathNodeTemplate(
  ref: 'select',
  type: BlockType.sqlSelect,
  defaults: {'columns': 'name', 'table': 'customers'},
);

const _where = LearningPathNodeTemplate(ref: 'where', type: BlockType.sqlWhere);

AuthoredLearningPath _path(List<LearningPathStep> steps) =>
    AuthoredLearningPath(
      id: 'workshop',
      title: 'Workshop',
      description: '',
      steps: steps,
    );

LearningPathStep _step({
  String id = 'step',
  List<LearningPathNodeTemplate> nodes = const [],
  List<String> highlights = const [],
  List<LearningPathRequirement> requirements = const [],
}) => LearningPathStep(
  id: id,
  title: 'Task',
  instruction: 'Read from the practice database.',
  nodes: nodes,
  highlights: highlights,
  requirements: requirements,
);
