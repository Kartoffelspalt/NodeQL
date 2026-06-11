import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';

class SqlCompiler {
  const SqlCompiler();

  SqlCompileResult compileWorkspace(
    List<BlockNode> roots, {
    Map<String, NodeQlPluginBlock> pluginBlocks =
        const <String, NodeQlPluginBlock>{},
  }) {
    final statements = <String>[];
    final warnings = <String>[];
    final floatingRoots = roots.where(
      (n) => n.type != BlockType.eventGreenFlag,
    );
    for (final floating in floatingRoots) {
      warnings.add(
        'Root "${floating.id}" is not executable. Attach it under an EXECUTE QUERY trigger block.',
      );
    }

    for (final root in roots.where((n) => n.type == BlockType.eventGreenFlag)) {
      if (root.next == null) continue;
      final sql = _compileNode(
        root.next!,
        pluginBlocks: pluginBlocks,
        warnings: warnings,
      ).trim();
      if (sql.isNotEmpty) {
        statements.add(sql.endsWith(';') ? sql : '$sql;');
      }
    }
    return SqlCompileResult(sql: statements.join('\n'), warnings: warnings);
  }

  String _compileNode(
    BlockNode node, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
  }) {
    final current = _compileSingle(
      node,
      pluginBlocks: pluginBlocks,
      warnings: warnings,
    );
    final next = node.next == null
        ? ''
        : ' ${_compileNode(node.next!, pluginBlocks: pluginBlocks, warnings: warnings)}';
    return '$current$next'.trim();
  }

  String _compileSingle(
    BlockNode node, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
  }) {
    final pluginBlockId = node.inputs[pluginBlockKeyInput] as String?;
    if (pluginBlockId != null) {
      final pluginBlock = pluginBlocks[pluginBlockId];
      if (pluginBlock == null) {
        warnings.add(
          'Plugin block "$pluginBlockId" is unavailable. Install or enable its plugin.',
        );
        return '';
      }
      final savedVersion = node.inputs[pluginVersionInput] as String?;
      if (savedVersion != null && savedVersion != pluginBlock.pluginVersion) {
        warnings.add(
          'Plugin block "$pluginBlockId" was created with version '
          '$savedVersion and is running with ${pluginBlock.pluginVersion}.',
        );
      }
      if (pluginBlock.sqlTemplate != null) {
        try {
          return pluginBlock.renderSql(
            node.inputs,
            childrenSql: _compileChildren(
              node.children,
              pluginBlocks: pluginBlocks,
              warnings: warnings,
            ),
          );
        } on Object catch (error) {
          warnings.add('Plugin block "$pluginBlockId" failed: $error');
          return '';
        }
      }
    }

    switch (node.type) {
      case BlockType.eventGreenFlag:
        return '';
      case BlockType.motionMove:
        return 'WHERE ${(node.inputs['steps'] ?? 10)} > 0';
      case BlockType.motionTurn:
        return 'ORDER BY ${(node.inputs['degrees'] ?? 15)}';
      case BlockType.controlRepeat:
      case BlockType.controlForever:
        return 'BEGIN; ${_compileChildren(node.children, pluginBlocks: pluginBlocks, warnings: warnings)}; COMMIT';
      case BlockType.operatorAdd:
        return node.inputs['expr'] as String? ?? 'id';
      case BlockType.variableSet:
        return 'WHERE ${(node.inputs['predicate'] ?? '1 = 1')}';
      case BlockType.sqlSelect:
        final configuredCols = (node.inputs['columns'] as String?)?.trim();
        final colsFromInput = (configuredCols == null || configuredCols.isEmpty)
            ? '*'
            : configuredCols;
        final colsFromChildren = _compileChildren(
          node.children,
          pluginBlocks: pluginBlocks,
          warnings: warnings,
        ).trim();
        final cols = colsFromChildren.isNotEmpty
            ? colsFromChildren
            : colsFromInput;
        final from = node.inputs['table'] as String? ?? 'table_name';
        return 'SELECT $cols FROM $from';
      case BlockType.sqlColumn:
        return node.inputs['column'] as String? ?? '*';
      case BlockType.sqlFrom:
        return 'FROM ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlWhere:
        return 'WHERE ${node.inputs['predicate'] as String? ?? '1 = 1'}';
      case BlockType.sqlJoin:
        return 'JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${node.inputs['on'] as String? ?? '1 = 1'}';
      case BlockType.sqlInnerJoin:
        return 'INNER JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${node.inputs['on'] as String? ?? '1 = 1'}';
      case BlockType.sqlLeftJoin:
        return 'LEFT JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${node.inputs['on'] as String? ?? '1 = 1'}';
      case BlockType.sqlRightJoin:
        return 'RIGHT JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${node.inputs['on'] as String? ?? '1 = 1'}';
      case BlockType.sqlFullJoin:
        return 'FULL JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${node.inputs['on'] as String? ?? '1 = 1'}';
      case BlockType.sqlCrossJoin:
        return 'CROSS JOIN ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlSelfJoin:
        return 'FROM ${node.inputs['table'] as String? ?? 't'} t1, ${node.inputs['table'] as String? ?? 't'} t2 WHERE ${node.inputs['on'] as String? ?? 't1.id = t2.id'}';
      case BlockType.sqlNaturalJoin:
        return 'NATURAL JOIN ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlGroupBy:
        return 'GROUP BY ${node.inputs['expr'] as String? ?? 'id'}';
      case BlockType.sqlHaving:
        return 'HAVING ${node.inputs['predicate'] as String? ?? 'COUNT(*) > 0'}';
      case BlockType.sqlOrderBy:
        return 'ORDER BY ${node.inputs['expr'] as String? ?? 'id'}';
      case BlockType.sqlUnion:
        return 'UNION ${node.inputs['sql'] as String? ?? 'SELECT 1'}';
      case BlockType.sqlIntersect:
        return 'INTERSECT ${node.inputs['sql'] as String? ?? 'SELECT 1'}';
      case BlockType.sqlExcept:
        return 'EXCEPT ${node.inputs['sql'] as String? ?? 'SELECT 1'}';
      case BlockType.sqlSubqueryIn:
        return '${node.inputs['lhs'] as String? ?? 'id'} IN (${node.inputs['sql'] as String? ?? 'SELECT id FROM t'})';
      case BlockType.sqlSubqueryAny:
        return '${node.inputs['lhs'] as String? ?? 'id'} = ANY (${node.inputs['sql'] as String? ?? 'SELECT id FROM t'})';
      case BlockType.sqlSubqueryAll:
        return '${node.inputs['lhs'] as String? ?? 'id'} = ALL (${node.inputs['sql'] as String? ?? 'SELECT id FROM t'})';
      case BlockType.sqlCount:
        return 'COUNT(${node.inputs['expr'] as String? ?? '*'})';
      case BlockType.sqlSum:
        return 'SUM(${node.inputs['expr'] as String? ?? 'amount'})';
      case BlockType.sqlAvg:
        return 'AVG(${node.inputs['expr'] as String? ?? 'amount'})';
      case BlockType.sqlMin:
        return 'MIN(${node.inputs['expr'] as String? ?? 'amount'})';
      case BlockType.sqlMax:
        return 'MAX(${node.inputs['expr'] as String? ?? 'amount'})';
      case BlockType.sqlConcat:
        return 'CONCAT(${node.inputs['a'] as String? ?? "''"}, ${node.inputs['b'] as String? ?? "''"})';
      case BlockType.sqlSubstring:
        return 'SUBSTRING(${node.inputs['expr'] as String? ?? "''"}, ${node.inputs['start'] as String? ?? '1'}, ${node.inputs['len'] as String? ?? '1'})';
      case BlockType.sqlLength:
        return 'LENGTH(${node.inputs['expr'] as String? ?? "''"})';
      case BlockType.sqlUpper:
        return 'UPPER(${node.inputs['expr'] as String? ?? "''"})';
      case BlockType.sqlLower:
        return 'LOWER(${node.inputs['expr'] as String? ?? "''"})';
      case BlockType.sqlTrim:
        return 'TRIM(${node.inputs['expr'] as String? ?? "''"})';
      case BlockType.sqlLeft:
        return 'LEFT(${node.inputs['expr'] as String? ?? "''"}, ${node.inputs['n'] as String? ?? '1'})';
      case BlockType.sqlRight:
        return 'RIGHT(${node.inputs['expr'] as String? ?? "''"}, ${node.inputs['n'] as String? ?? '1'})';
      case BlockType.sqlReplace:
        return 'REPLACE(${node.inputs['expr'] as String? ?? "''"}, ${node.inputs['from'] as String? ?? "''"}, ${node.inputs['to'] as String? ?? "''"})';
      case BlockType.sqlCurrentDate:
        return 'CURRENT_DATE';
      case BlockType.sqlCurrentTime:
        return 'CURRENT_TIME';
      case BlockType.sqlCurrentTimestamp:
        return 'CURRENT_TIMESTAMP';
      case BlockType.sqlDatePart:
        return 'DATE_PART(${node.inputs['part'] as String? ?? "'day'"}, ${node.inputs['expr'] as String? ?? 'CURRENT_DATE'})';
      case BlockType.sqlDateAdd:
        return 'DATE_ADD(${node.inputs['expr'] as String? ?? 'CURRENT_DATE'}, INTERVAL ${node.inputs['n'] as String? ?? '1'} ${node.inputs['unit'] as String? ?? 'DAY'})';
      case BlockType.sqlDateSub:
        return 'DATE_SUB(${node.inputs['expr'] as String? ?? 'CURRENT_DATE'}, INTERVAL ${node.inputs['n'] as String? ?? '1'} ${node.inputs['unit'] as String? ?? 'DAY'})';
      case BlockType.sqlExtract:
        return 'EXTRACT(${node.inputs['part'] as String? ?? 'DAY'} FROM ${node.inputs['expr'] as String? ?? 'CURRENT_DATE'})';
      case BlockType.sqlToChar:
        return 'TO_CHAR(${node.inputs['expr'] as String? ?? 'CURRENT_DATE'}, ${node.inputs['fmt'] as String? ?? "'YYYY-MM-DD'"})';
      case BlockType.sqlTimestampDiff:
        return 'TIMESTAMPDIFF(${node.inputs['unit'] as String? ?? 'DAY'}, ${node.inputs['a'] as String? ?? 'CURRENT_DATE'}, ${node.inputs['b'] as String? ?? 'CURRENT_DATE'})';
      case BlockType.sqlDateDiff:
        return 'DATEDIFF(${node.inputs['a'] as String? ?? 'CURRENT_DATE'}, ${node.inputs['b'] as String? ?? 'CURRENT_DATE'})';
      case BlockType.sqlCase:
        return 'CASE WHEN ${node.inputs['when'] as String? ?? '1=1'} THEN ${node.inputs['then'] as String? ?? "'x'"} ELSE ${node.inputs['else'] as String? ?? "'y'"} END';
      case BlockType.sqlIf:
        return 'IF(${node.inputs['cond'] as String? ?? '1=1'}, ${node.inputs['a'] as String? ?? "'x'"}, ${node.inputs['b'] as String? ?? "'y'"})';
      case BlockType.sqlCoalesce:
        return 'COALESCE(${node.inputs['a'] as String? ?? 'NULL'}, ${node.inputs['b'] as String? ?? 'NULL'})';
      case BlockType.sqlNullIf:
        return 'NULLIF(${node.inputs['a'] as String? ?? '1'}, ${node.inputs['b'] as String? ?? '1'})';
      case BlockType.sqlInsert:
        return 'INSERT INTO ${node.inputs['table'] as String? ?? 'table_name'} VALUES (${node.inputs['values'] as String? ?? ''})';
      case BlockType.sqlUpdate:
        return 'UPDATE ${node.inputs['table'] as String? ?? 'table_name'} SET ${node.inputs['set'] as String? ?? 'col = value'}';
      case BlockType.sqlDelete:
        return 'DELETE FROM ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlCreateTable:
        return 'CREATE TABLE ${node.inputs['table'] as String? ?? 'new_table'} (${node.inputs['definition'] as String? ?? 'id INTEGER PRIMARY KEY'})';
      case BlockType.sqlAlterTable:
        return 'ALTER TABLE ${node.inputs['table'] as String? ?? 'table_name'} ${node.inputs['alter'] as String? ?? 'ADD COLUMN c TEXT'}';
      case BlockType.sqlTruncate:
        return 'TRUNCATE TABLE ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlDropTable:
        return 'DROP TABLE ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlGrant:
        return 'GRANT ${node.inputs['privilege'] as String? ?? 'SELECT'} ON ${node.inputs['table'] as String? ?? 'table_name'} TO ${node.inputs['user'] as String? ?? 'user'}';
      case BlockType.sqlRevoke:
        return 'REVOKE ${node.inputs['privilege'] as String? ?? 'SELECT'} ON ${node.inputs['table'] as String? ?? 'table_name'} FROM ${node.inputs['user'] as String? ?? 'user'}';
      case BlockType.sqlCommit:
        return 'COMMIT';
      case BlockType.sqlRollback:
        return 'ROLLBACK';
      case BlockType.sqlSavepoint:
        return 'SAVEPOINT ${node.inputs['name'] as String? ?? 'sp1'}';
      case BlockType.sqlRollbackToSavepoint:
        return 'ROLLBACK TO SAVEPOINT ${node.inputs['name'] as String? ?? 'sp1'}';
      case BlockType.sqlSetTransaction:
        return 'SET TRANSACTION ISOLATION LEVEL ${node.inputs['level'] as String? ?? 'READ COMMITTED'}';
      case BlockType.sqlLoop:
        // NodeQL loop compiles contained statements as transaction body.
        return 'BEGIN; ${_compileChildren(node.children, pluginBlocks: pluginBlocks, warnings: warnings)}; COMMIT';
    }
  }

  String _compileChildren(
    List<BlockNode> children, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
  }) {
    final parts = <String>[];
    for (final head in children) {
      parts.add(
        _compileNode(head, pluginBlocks: pluginBlocks, warnings: warnings),
      );
    }
    return parts.where((p) => p.trim().isNotEmpty).join(', ');
  }
}

class SqlCompileResult {
  const SqlCompileResult({required this.sql, required this.warnings});

  final String sql;
  final List<String> warnings;
}
