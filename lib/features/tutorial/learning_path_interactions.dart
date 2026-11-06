import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/localization/translation_catalog.dart';

import 'learning_path_authoring.dart';

String learningPathInteractionKey(
  LearningPathAction action,
  String nodeId, [
  String? input,
]) => '${action.name}:$nodeId:${input ?? ''}';

/// Gates a rule once its last required node has been introduced. The final
/// gate rechecks the whole step, including conditions that can be undone.
LearningPathRequirement? pendingLearningPathRequirement({
  required LearningPathStep step,
  required int nodeIndex,
  required BlockNode? Function(String ref) findNode,
  required String? Function(String nodeId) columnSourceId,
  required Set<String> interactions,
  required bool currentQueryRan,
}) {
  if (step.requirements.isEmpty) return null;
  final lastIndex = step.nodes.lastIndexWhere(
    (node) => node.type != BlockType.eventGreenFlag,
  );
  final indices = {
    for (var index = 0; index < step.nodes.length; index++)
      step.nodes[index].ref: index,
  };
  for (final rule in step.requirements) {
    if (nodeIndex < lastIndex &&
        (rule.action == LearningPathAction.runQuery ||
            rule.refs.any((ref) => (indices[ref] ?? lastIndex) > nodeIndex))) {
      continue;
    }
    if (rule.action == LearningPathAction.runQuery) {
      if (!currentQueryRan) return rule;
      continue;
    }
    final nodeRef = rule.nodeRef;
    final node = nodeRef == null ? null : findNode(nodeRef);
    final otherRef = rule.otherRef;
    final other = otherRef == null ? null : findNode(otherRef);
    if (node == null || (rule.action.needsOtherNode && other == null)) {
      return rule;
    }
    final done = switch (rule.action) {
      LearningPathAction.selectNode => interactions.contains(
        learningPathInteractionKey(rule.action, node.id),
      ),
      LearningPathAction.enterInput => _inputMatches(node, rule, interactions),
      LearningPathAction.connectNodes =>
        other!.next?.id == node.id ||
            other.children.any((child) => child.id == node.id),
      LearningPathAction.attachReporter =>
        rule.input != null &&
            reporterForInput(node, rule.input!)?.id == other!.id,
      LearningPathAction.linkColumns => columnSourceId(node.id) == other!.id,
      LearningPathAction.runQuery => currentQueryRan,
    };
    if (!done) return rule;
  }
  return null;
}

bool _inputMatches(
  BlockNode node,
  LearningPathRequirement rule,
  Set<String> interactions,
) {
  final input = rule.input;
  if (input == null ||
      !interactions.contains(
        learningPathInteractionKey(rule.action, node.id, input),
      ) ||
      reporterForInput(node, input) != null) {
    return false;
  }
  final value = node.inputs[input];
  if (value is! String && value is! num && value is! bool) return false;
  final text = value.toString().trim();
  return text.isNotEmpty && (rule.value == null || text == rule.value!.trim());
}

String learningPathInputLabel(TranslationCatalog catalog, String input) {
  final key = 'tutorial.action.field.$input';
  final label = catalog.text(key);
  return label == key ? input.replaceAll('_', ' ') : label;
}

String learningPathRequirementLabel(
  TranslationCatalog catalog,
  LearningPathRequirement rule,
  String Function(String ref) nodeLabel,
) => catalog.text('tutorial.action.${rule.action.name}.task', {
  if (rule.nodeRef case final ref?) 'node': nodeLabel(ref),
  if (rule.otherRef case final ref?) 'other': nodeLabel(ref),
  if (rule.input case final input?)
    'field': learningPathInputLabel(catalog, input),
});
