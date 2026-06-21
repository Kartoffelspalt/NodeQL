import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
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
        visited: <String>{root.id},
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
    Set<String>? visited,
  }) {
    final seen = visited ?? <String>{};
    if (!seen.add(node.id)) {
      warnings.add(
        'Cycle detected at block "${node.id}". The repeated chain was skipped.',
      );
      return '';
    }
    final current = _compileSingle(
      node,
      pluginBlocks: pluginBlocks,
      warnings: warnings,
      visited: seen,
    );
    final next = node.next == null
        ? ''
        : ' ${_compileNode(node.next!, pluginBlocks: pluginBlocks, warnings: warnings, visited: seen)}';
    seen.remove(node.id);
    return '$current$next'.trim();
  }

  String _compileSingle(
    BlockNode node, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
    Set<String>? visited,
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
              visited: visited,
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
        return 'BEGIN; ${_compileChildren(node.children, pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}; COMMIT';
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
          visited: visited,
        ).trim();
        final reporterColumns = _compileReporterInput(
          node,
          'columns',
          '',
          pluginBlocks: pluginBlocks,
          warnings: warnings,
          visited: visited,
        );
        final cols = reporterColumns.isNotEmpty
            ? reporterColumns
            : (colsFromChildren.isNotEmpty ? colsFromChildren : colsFromInput);
        if (node.next?.type == BlockType.sqlFrom) {
          return 'SELECT $cols';
        }
        final from = node.inputs['table'] as String? ?? 'table_name';
        return 'SELECT $cols FROM $from';
      case BlockType.sqlColumn:
        return node.inputs['column'] as String? ?? '*';
      case BlockType.sqlText:
        final text = '${node.inputs['text'] ?? ''}'.replaceAll("'", "''");
        return "'$text'";
      case BlockType.sqlFrom:
        return 'FROM ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlWhere:
        return 'WHERE ${_predicateFromInputs(node, fallback: '1 = 1')}';
      case BlockType.sqlJoin:
        final joinType = _normalizedJoinType(node.inputs['join_type']);
        final table = node.inputs['table'] as String? ?? 'table_name';
        final condition = _joinConditionFromInputs(node);
        return switch (joinType) {
          'CROSS' => 'CROSS JOIN $table',
          'NATURAL' => 'NATURAL JOIN $table',
          'SELF' => 'JOIN $table AS t2 ON $condition',
          'INNER' ||
          'LEFT' ||
          'RIGHT' ||
          'FULL' => '$joinType JOIN $table ON $condition',
          _ => 'JOIN $table ON $condition',
        };
      case BlockType.sqlInnerJoin:
        return 'INNER JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlLeftJoin:
        return 'LEFT JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlRightJoin:
        return 'RIGHT JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlFullJoin:
        return 'FULL JOIN ${node.inputs['table'] as String? ?? 'table_name'} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlCrossJoin:
        return 'CROSS JOIN ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlSelfJoin:
        return 'JOIN ${node.inputs['table'] as String? ?? 'table_name'} AS t2 ON ${_joinConditionFromInputs(node, fallback: 't1.id = t2.id')}';
      case BlockType.sqlNaturalJoin:
        return 'NATURAL JOIN ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlGroupBy:
        return 'GROUP BY ${node.inputs['column'] as String? ?? node.inputs['expr'] as String? ?? 'id'}';
      case BlockType.sqlHaving:
        return 'HAVING ${_havingPredicateFromInputs(node, pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}';
      case BlockType.sqlOrderBy:
        return 'ORDER BY ${_orderByFromInputs(node)}';
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
        return 'COUNT(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? '*'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlSum:
        return 'SUM(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlAvg:
        return 'AVG(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlMin:
        return 'MIN(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlMax:
        return 'MAX(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlConcat:
        return 'CONCAT(${_compileReporterInput(node, 'a', '${node.inputs['a'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}, ${_compileReporterInput(node, 'b', '${node.inputs['b'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlSubstring:
        return 'SUBSTRING(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}, ${node.inputs['start'] as String? ?? '1'}, ${node.inputs['len'] as String? ?? '1'})';
      case BlockType.sqlLength:
        return 'LENGTH(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlUpper:
        return 'UPPER(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlLower:
        return 'LOWER(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlTrim:
        return 'TRIM(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
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
        return 'CASE WHEN ${_predicateFromInputs(node, columnKey: 'condition_column', valueKey: 'condition_value', fallback: node.inputs['when'] as String? ?? '1 = 1')} THEN ${node.inputs['then'] as String? ?? node.inputs['result'] as String? ?? "'x'"} ELSE ${node.inputs['else'] as String? ?? node.inputs['default'] as String? ?? "'y'"} END';
      case BlockType.sqlIf:
        return 'IF(${_predicateFromInputs(node, columnKey: 'condition_column', valueKey: 'condition_value', fallback: node.inputs['cond'] as String? ?? '1 = 1')}, ${node.inputs['a'] as String? ?? node.inputs['value'] as String? ?? "'x'"}, ${node.inputs['b'] as String? ?? node.inputs['default'] as String? ?? "'y'"})';
      case BlockType.sqlCoalesce:
        return 'COALESCE(${node.inputs['a'] as String? ?? 'NULL'}, ${node.inputs['b'] as String? ?? 'NULL'})';
      case BlockType.sqlNullIf:
        return 'NULLIF(${node.inputs['a'] as String? ?? '1'}, ${node.inputs['b'] as String? ?? '1'})';
      case BlockType.sqlInsert:
        return 'INSERT INTO ${node.inputs['table'] as String? ?? 'table_name'} VALUES (${node.inputs['values'] as String? ?? ''})';
      case BlockType.sqlUpdate:
        return 'UPDATE ${node.inputs['table'] as String? ?? 'table_name'} SET ${node.inputs['column'] as String? ?? 'column_name'} = ${node.inputs['value'] as String? ?? 'value'} WHERE ${_predicateFromInputs(node, columnKey: 'where_column', valueKey: 'where_value', fallback: 'id = 1')}';
      case BlockType.sqlDelete:
        return 'DELETE FROM ${node.inputs['table'] as String? ?? 'table_name'} WHERE ${_predicateFromInputs(node, columnKey: 'where_column', valueKey: 'where_value', fallback: 'id = 1')}';
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
        return 'BEGIN; ${_compileChildren(node.children, pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}; COMMIT';
    }
  }

  String _normalizedJoinType(dynamic value) {
    final normalized = '${value ?? ''}'.trim().toUpperCase();
    const supported = <String>{
      'INNER',
      'LEFT',
      'RIGHT',
      'FULL',
      'CROSS',
      'NATURAL',
      'SELF',
    };
    return supported.contains(normalized) ? normalized : '';
  }

  String _orderByFromInputs(BlockNode node) {
    final column =
        node.inputs['column'] as String? ??
        node.inputs['expr'] as String? ??
        'id';
    final order = _normalizedComparisonOperator(
      node.inputs['order'],
      defaultValue: 'ASC',
    );
    if (column.toUpperCase().endsWith(' ASC') ||
        column.toUpperCase().endsWith(' DESC')) {
      return column;
    }
    return '$column $order';
  }

  String _predicateFromInputs(
    BlockNode node, {
    String columnKey = 'column',
    String operatorKey = 'operator',
    String valueKey = 'value',
    required String fallback,
  }) {
    final column = '${node.inputs[columnKey] ?? ''}'.trim();
    final operator = _normalizedComparisonOperator(node.inputs[operatorKey]);
    final value = '${node.inputs[valueKey] ?? ''}'.trim();
    if (column.isEmpty || value.isEmpty) {
      return node.inputs['predicate'] as String? ?? fallback;
    }
    return '$column $operator $value';
  }

  String _joinConditionFromInputs(BlockNode node, {String fallback = '1 = 1'}) {
    final left = '${node.inputs['left_column'] ?? ''}'.trim();
    final operator = _normalizedComparisonOperator(node.inputs['operator']);
    final right = '${node.inputs['right_column'] ?? ''}'.trim();
    if (left.isEmpty || right.isEmpty) {
      return node.inputs['on'] as String? ?? fallback;
    }
    return '$left $operator $right';
  }

  String _havingPredicateFromInputs(
    BlockNode node, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
    Set<String>? visited,
  }) {
    final aggregateReporter = reporterForInput(node, 'aggregate');
    final aggregate = _aggregateFunctionFromReporter(
      aggregateReporter,
      fallback: node.inputs['aggregate'],
    );
    final column = '${node.inputs['column'] ?? '*'}'.trim();
    final reporterExpr = _compileReporterInput(
      node,
      'expr',
      '',
      pluginBlocks: pluginBlocks,
      warnings: warnings,
      visited: visited,
    );
    final expr = reporterExpr.isNotEmpty
        ? reporterExpr
        : '${node.inputs['expr'] ?? ''}'.trim();
    final operator = _normalizedComparisonOperator(node.inputs['operator']);
    final value = '${node.inputs['value'] ?? '0'}'.trim();
    if (value.isEmpty) {
      return node.inputs['predicate'] as String? ?? 'COUNT(*) > 0';
    }
    if (aggregateReporter != null || node.inputs.containsKey('aggregate')) {
      return '$aggregate(${column.isEmpty ? '*' : column}) $operator $value';
    }
    if (expr.isNotEmpty) return '$expr $operator $value';

    return '$aggregate(${column.isEmpty ? '*' : column}) $operator $value';
  }

  String _aggregateFunctionFromReporter(
    BlockNode? reporter, {
    dynamic fallback,
  }) {
    if (reporter != null) {
      final typeName = switch (reporter.type) {
        BlockType.sqlCount => 'COUNT',
        BlockType.sqlSum => 'SUM',
        BlockType.sqlAvg => 'AVG',
        BlockType.sqlMin => 'MIN',
        BlockType.sqlMax => 'MAX',
        _ => null,
      };
      if (typeName != null) return typeName;
    }
    final normalized = '${fallback ?? 'COUNT'}'.trim().toUpperCase();
    const supported = <String>{'COUNT', 'SUM', 'AVG', 'MIN', 'MAX'};
    return supported.contains(normalized) ? normalized : 'COUNT';
  }

  String _normalizedComparisonOperator(
    dynamic value, {
    String defaultValue = '=',
  }) {
    final normalized = '${value ?? defaultValue}'.trim().toUpperCase();
    const supported = <String>{
      '=',
      '!=',
      '<>',
      '>',
      '>=',
      '<',
      '<=',
      'LIKE',
      'NOT LIKE',
    };
    return supported.contains(normalized) ? normalized : defaultValue;
  }

  String _compileChildren(
    List<BlockNode> children, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
    Set<String>? visited,
  }) {
    final parts = <String>[];
    for (final head in children) {
      parts.add(
        _compileNode(
          head,
          pluginBlocks: pluginBlocks,
          warnings: warnings,
          visited: visited == null ? null : <String>{...visited},
        ),
      );
    }
    return parts.where((p) => p.trim().isNotEmpty).join(', ');
  }

  String _compileReporterInput(
    BlockNode node,
    String key,
    String fallback, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
    Set<String>? visited,
  }) {
    final reporter = reporterForInput(node, key);
    if (reporter == null) return fallback;
    return _compileSingle(
      reporter,
      pluginBlocks: pluginBlocks,
      warnings: warnings,
      visited: <String>{...?visited},
    ).trim();
  }

  String _compileReporterInputAny(
    BlockNode node,
    List<String> keys,
    String fallback, {
    required Map<String, NodeQlPluginBlock> pluginBlocks,
    required List<String> warnings,
    Set<String>? visited,
  }) {
    for (final key in keys) {
      final compiled = _compileReporterInput(
        node,
        key,
        '',
        pluginBlocks: pluginBlocks,
        warnings: warnings,
        visited: visited,
      );
      if (compiled.isNotEmpty) return compiled;
    }
    return fallback;
  }
}

class SqlCompileResult {
  const SqlCompileResult({required this.sql, required this.warnings});

  final String sql;
  final List<String> warnings;
}
