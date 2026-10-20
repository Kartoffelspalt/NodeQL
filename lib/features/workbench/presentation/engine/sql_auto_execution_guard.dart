import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';

/// Whether a workspace contains a Node from the Changes or Structure palette.
///
/// These nodes can modify records or database schema. Their generated SQL must
/// never run as part of the workbench's automatic live preview; execution is
/// reserved for the explicit Run SQLite action.
bool requiresManualSqlExecution(Iterable<BlockNode> roots) {
  final visited = <String>{};

  bool visit(BlockNode node) {
    if (!visited.add(node.id)) return false;
    // Plugin templates can render arbitrary SQLite. Even when their host
    // block type resembles a read-only built-in node, they require the
    // explicit Run action instead of automatic preview execution.
    if (node.inputs.containsKey(pluginBlockKeyInput)) return true;
    if (_hasPluginReporter(node.inputs)) return true;
    if (_isChangeOrStructureNode(node.type)) return true;
    for (final child in node.children) {
      if (visit(child)) return true;
    }
    final next = node.next;
    return next != null && visit(next);
  }

  for (final root in roots) {
    if (visit(root)) return true;
  }
  return false;
}

bool _hasPluginReporter(Map<String, dynamic> inputs) {
  return _hasPluginReporterInInputs(inputs, _ReporterTraversalBudget(), 0);
}

bool _hasPluginReporterInInputs(
  Map inputs,
  _ReporterTraversalBudget budget,
  int depth,
) {
  final reporters = inputs[reporterInputsKey];
  if (reporters is! Map) return false;
  for (final reporter in reporters.values) {
    if (_hasPluginReporterInNode(reporter, budget, depth + 1)) return true;
  }
  return false;
}

bool _hasPluginReporterInNode(
  Object? encoded,
  _ReporterTraversalBudget budget,
  int depth,
) {
  if (encoded is! Map) return false;
  // A malformed or unexpectedly large reporter graph must not obtain
  // automatic execution privileges.
  if (depth > BlockNode.maxDecodedDepth ||
      ++budget.nodeCount > BlockNode.maxDecodedNodes) {
    return true;
  }
  final rawInputs = encoded['inputs'];
  if (rawInputs is Map) {
    if (rawInputs[pluginBlockKeyInput] is String) return true;
    if (_hasPluginReporterInInputs(rawInputs, budget, depth)) return true;
  }
  if (_hasPluginReporterInNode(encoded['next'], budget, depth + 1)) {
    return true;
  }
  final children = encoded['children'];
  if (children is List) {
    for (final child in children) {
      if (_hasPluginReporterInNode(child, budget, depth + 1)) return true;
    }
  }
  return false;
}

class _ReporterTraversalBudget {
  int nodeCount = 0;
}

bool _isChangeOrStructureNode(BlockType type) => switch (type) {
  // Changes palette (DML)
  BlockType.sqlInsert ||
  BlockType.sqlInsertOrReplace ||
  BlockType.sqlUpsert ||
  BlockType.sqlUpdate ||
  BlockType.sqlDelete ||
  // Structure palette (DDL)
  BlockType.sqlCreateTable ||
  BlockType.sqlCreateIndex ||
  BlockType.sqlDropIndex ||
  BlockType.sqlCreateView ||
  BlockType.sqlDropView ||
  BlockType.sqlCreateTrigger ||
  BlockType.sqlDropTrigger ||
  BlockType.sqlCreateVirtualTable ||
  BlockType.sqlAlterTable ||
  BlockType.sqlTruncate ||
  BlockType.sqlDropTable => true,
  _ => false,
};
