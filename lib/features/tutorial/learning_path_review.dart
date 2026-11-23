import 'dart:convert';

import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/engine/block/block_syntax.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';

import 'learning_path_authoring.dart';
import 'remote_workshop.dart';

enum LearningPathReviewCode {
  missingPathId,
  missingTitle,
  missingSteps,
  missingStepId,
  duplicateStepId,
  missingStepTitle,
  missingInstruction,
  missingNodeRef,
  duplicateNodeRef,
  invalidHighlight,
  invalidCallout,
  invalidRequirementTarget,
  invalidRequirementInput,
  incompatibleRequirementNodes,
  conflictingRequirements,
  distributionRejected,
}

class LearningPathReviewIssue {
  const LearningPathReviewIssue(
    this.code, {
    this.stepIndex,
    this.detail,
    this.distributionProblem,
  });

  final LearningPathReviewCode code;

  /// Zero-based position in the author's current step order.
  final int? stepIndex;
  final String? detail;
  final WorkshopDistributionProblem? distributionProblem;

  bool get blocksPreview => switch (code) {
    LearningPathReviewCode.invalidHighlight ||
    LearningPathReviewCode.invalidCallout ||
    LearningPathReviewCode.distributionRejected => false,
    _ => true,
  };
}

class LearningPathReview {
  LearningPathReview._(List<LearningPathReviewIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<LearningPathReviewIssue> issues;

  bool get canPreview => !issues.any((issue) => issue.blocksPreview);

  /// The bundled catalog can use nodes the download format doesn't allow.
  bool get canExportCatalog => issues.every(
    (issue) => issue.code == LearningPathReviewCode.distributionRejected,
  );

  bool get canShare => issues.isEmpty;
}

/// Checks a draft independently of the editor, then runs the same validation
/// that learners' apps use to accept files, links, and classroom codes.
LearningPathReview reviewLearningPath(AuthoredLearningPath path) {
  final issues = <LearningPathReviewIssue>[
    if (path.id.trim().isEmpty)
      const LearningPathReviewIssue(LearningPathReviewCode.missingPathId),
    if (path.title.trim().isEmpty && path.titleTranslations.isEmpty)
      const LearningPathReviewIssue(LearningPathReviewCode.missingTitle),
    if (path.steps.isEmpty)
      const LearningPathReviewIssue(LearningPathReviewCode.missingSteps),
  ];
  final stepIds = <String>{};
  final availableNodes = <String, LearningPathNodeTemplate>{};
  for (final (index, step) in path.steps.indexed) {
    void report(LearningPathReviewCode code, [String? detail]) {
      issues.add(
        LearningPathReviewIssue(code, stepIndex: index, detail: detail),
      );
    }

    if (step.id.trim().isEmpty) {
      report(LearningPathReviewCode.missingStepId);
    } else if (!stepIds.add(step.id)) {
      report(LearningPathReviewCode.duplicateStepId, step.id);
    }
    if (step.title.trim().isEmpty) {
      report(LearningPathReviewCode.missingStepTitle);
    }
    if (step.instruction.trim().isEmpty) {
      report(LearningPathReviewCode.missingInstruction);
    }

    final stepRefs = <String>{};
    for (final node in step.nodes) {
      if (node.ref.trim().isEmpty) {
        report(LearningPathReviewCode.missingNodeRef, node.type.name);
      } else if (!stepRefs.add(node.ref)) {
        report(LearningPathReviewCode.duplicateNodeRef, node.ref);
      } else {
        availableNodes[node.ref] = node;
      }
    }
    final highlights = <String>{};
    for (final ref in step.highlights) {
      if (!availableNodes.containsKey(ref) || !highlights.add(ref)) {
        report(LearningPathReviewCode.invalidHighlight, ref);
      }
    }
    final calloutIds = <String>{};
    for (final callout in step.callouts) {
      if (callout.id.trim().isEmpty ||
          !calloutIds.add(callout.id) ||
          !availableNodes.containsKey(callout.targetRef) ||
          callout.title.trim().isEmpty ||
          callout.body.trim().isEmpty) {
        report(LearningPathReviewCode.invalidCallout, callout.targetRef);
      }
    }
    final validRules = <LearningPathRequirement>[];
    for (final rule in step.requirements) {
      final issue = _requirementIssue(rule, availableNodes);
      if (issue != null) {
        final detail = switch (issue) {
          LearningPathReviewCode.invalidRequirementTarget =>
            rule.refs
                    .where((ref) => !availableNodes.containsKey(ref))
                    .firstOrNull ??
                rule.action.name,
          _ => rule.input ?? rule.nodeRef ?? rule.action.name,
        };
        report(issue, detail);
        continue;
      }
      if (validRules.any((other) => _conflict(other, rule))) {
        report(
          LearningPathReviewCode.conflictingRequirements,
          rule.input ?? rule.nodeRef ?? rule.action.name,
        );
      }
      validRules.add(rule);
    }
  }

  if (issues.isEmpty) {
    try {
      validateRemoteWorkshopBundle(encodeLearningPathBundle([path]));
    } on WorkshopDistributionException catch (error) {
      issues.add(
        LearningPathReviewIssue(
          LearningPathReviewCode.distributionRejected,
          stepIndex: error.stepIndex,
          detail: error.detail,
          distributionProblem: error.problem,
        ),
      );
    } on FormatException {
      issues.add(_invalidDistribution);
    } on JsonUnsupportedObjectError {
      issues.add(_invalidDistribution);
    }
  }
  return LearningPathReview._(issues);
}

const _invalidDistribution = LearningPathReviewIssue(
  LearningPathReviewCode.distributionRejected,
  distributionProblem: WorkshopDistributionProblem.invalidContent,
);

LearningPathReviewCode? _requirementIssue(
  LearningPathRequirement rule,
  Map<String, LearningPathNodeTemplate> nodes,
) {
  final action = rule.action;
  final target = nodes[rule.nodeRef];
  final other = nodes[rule.otherRef];
  if ((action.needsNode && target == null) ||
      (action.needsOtherNode && other == null) ||
      (!action.needsNode && rule.nodeRef != null) ||
      (!action.needsOtherNode && rule.otherRef != null)) {
    return LearningPathReviewCode.invalidRequirementTarget;
  }
  if ((!action.needsInput && rule.input != null) ||
      (rule.value != null &&
          (action != LearningPathAction.enterInput ||
              rule.value!.trim().isEmpty))) {
    return LearningPathReviewCode.invalidRequirementInput;
  }
  if (action == LearningPathAction.runQuery) return null;
  final node = target!;
  if (action.needsOtherNode &&
      (rule.nodeRef == rule.otherRef ||
          (node.type == BlockType.eventGreenFlag &&
              other!.type == BlockType.eventGreenFlag))) {
    return LearningPathReviewCode.incompatibleRequirementNodes;
  }
  return switch (action) {
    LearningPathAction.selectNode => null,
    LearningPathAction.connectNodes =>
      _canConnect(node, other!)
          ? null
          : LearningPathReviewCode.incompatibleRequirementNodes,
    LearningPathAction.linkColumns =>
      acceptsColumnSource(node.type) && providesColumnSource(other!.type)
          ? null
          : LearningPathReviewCode.incompatibleRequirementNodes,
    LearningPathAction.enterInput ||
    LearningPathAction.attachReporter => _inputIssue(node, rule, other),
    LearningPathAction.runQuery => null,
  };
}

bool _isReporter(LearningPathNodeTemplate node) =>
    isReporterType(node.type) || node.defaults[pluginShapeInput] == 'value';

bool _canConnect(
  LearningPathNodeTemplate child,
  LearningPathNodeTemplate parent,
) {
  if (child.type == BlockType.eventGreenFlag ||
      _isReporter(child) ||
      _isReporter(parent) ||
      blockVisualKindForType(parent.type) == BlockVisualKind.terminal) {
    return false;
  }
  if (parent.defaults.containsKey(pluginBlockKeyInput) ||
      child.defaults.containsKey(pluginBlockKeyInput) ||
      blockVisualKindForType(parent.type) == BlockVisualKind.container) {
    return true;
  }
  if (parent.type == BlockType.eventGreenFlag ||
      isSqlChainType(parent.type) ||
      isSqlChainType(child.type)) {
    return canFollowInSqlChain(parent.type, child.type);
  }
  return true;
}

final _inputSlots = RegExp(r'\[([^\]]+)\]|\{([^}]+)\}');

LearningPathReviewCode? _inputIssue(
  LearningPathNodeTemplate node,
  LearningPathRequirement rule,
  LearningPathNodeTemplate? other,
) {
  final input = rule.input;
  if (input == null || input.trim().isEmpty) {
    return LearningPathReviewCode.invalidRequirementInput;
  }
  if (node.defaults.containsKey(pluginBlockKeyInput)) return null;
  if (node.type == BlockType.sqlJoin &&
      input == 'join_type' &&
      rule.action == LearningPathAction.enterInput) {
    return null;
  }
  final slots = <String>{
    for (final mode in SqlAbstractionMode.values)
      for (final match in _inputSlots.allMatches(
        sqlLabelFor(node.type, mode, node.defaults, 'en'),
      ))
        if (sqlInputKey((match[1] ?? match[2])!) == input) match[0]!,
  };
  if (slots.isEmpty) return LearningPathReviewCode.invalidRequirementInput;
  if (rule.action == LearningPathAction.enterInput) {
    return requiresReporterInput(node.type, input)
        ? LearningPathReviewCode.invalidRequirementInput
        : null;
  }
  if (!slots.any((slot) => slotAcceptsReporter(slot, input))) {
    return LearningPathReviewCode.invalidRequirementInput;
  }
  return slots.any((slot) => slotAcceptsReporterType(slot, input, other!.type))
      ? null
      : LearningPathReviewCode.incompatibleRequirementNodes;
}

// The final step gate requires these conditions to hold at the same time.
bool _conflict(LearningPathRequirement a, LearningPathRequirement b) {
  if (a.nodeRef != b.nodeRef) return false;
  if (a.action == b.action &&
      (a.action == LearningPathAction.linkColumns ||
          a.action == LearningPathAction.connectNodes)) {
    return a.otherRef != b.otherRef;
  }
  if (a.input == null || a.input != b.input) return false;
  return switch ((a.action, b.action)) {
    (LearningPathAction.enterInput, LearningPathAction.enterInput) =>
      a.value != null && b.value != null && a.value!.trim() != b.value!.trim(),
    (LearningPathAction.attachReporter, LearningPathAction.attachReporter) =>
      a.otherRef != b.otherRef,
    (LearningPathAction.enterInput, LearningPathAction.attachReporter) ||
    (LearningPathAction.attachReporter, LearningPathAction.enterInput) => true,
    _ => false,
  };
}
