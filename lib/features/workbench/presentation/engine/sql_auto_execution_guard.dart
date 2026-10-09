import 'package:nodeql/engine/block/block_node.dart';

/// Whether a workspace contains a Node from the Changes or Structure palette.
///
/// These nodes can modify records or database schema. Their generated SQL must
/// never run as part of the workbench's automatic live preview; execution is
/// reserved for the explicit Run SQLite action.
bool requiresManualSqlExecution(Iterable<BlockNode> roots) {
  final visited = <String>{};

  bool visit(BlockNode node) {
    if (!visited.add(node.id)) return false;
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
