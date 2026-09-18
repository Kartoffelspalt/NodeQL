import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/engine/block/block_syntax.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';

/// A database-neutral representation of the connected visual blocks.
///
/// Workspace nodes are deliberately kept as structured data until they reach
/// the SQLite adapter. This prevents the UI and the workspace engine from
/// passing hand-built SQLite strings around.
class SqliteProgram {
  const SqliteProgram({required this.roots, required this.pluginBlocks});

  final List<BlockNode> roots;
  final Map<String, NodeQlPluginBlock> pluginBlocks;

  bool get isEmpty => roots
      .where((node) => node.type == BlockType.eventGreenFlag)
      .every((node) => node.next == null);
}

class SqlitePlanResult {
  const SqlitePlanResult({required this.program, required this.warnings});

  final SqliteProgram program;
  final List<String> warnings;
}

/// Converts the visual workspace into a structured SQLite program.
class SqliteProgramCompiler {
  const SqliteProgramCompiler();

  SqlitePlanResult compileWorkspace(
    List<BlockNode> roots, {
    Map<String, NodeQlPluginBlock> pluginBlocks =
        const <String, NodeQlPluginBlock>{},
  }) {
    final warnings = <String>[];
    for (final node in roots.where(
      (node) => node.type != BlockType.eventGreenFlag,
    )) {
      warnings.add(
        'Root "${node.id}" is not executable. Attach it under an EXECUTE QUERY trigger block.',
      );
    }
    return SqlitePlanResult(
      program: SqliteProgram(roots: roots, pluginBlocks: pluginBlocks),
      warnings: warnings,
    );
  }
}

/// Compatibility facade for the SQLite command preview.
///
/// The app executes [SqliteProgram]s. The text returned here is only a
/// preview that users can inspect or copy.
class SqlCompiler {
  const SqlCompiler();

  SqlCompileResult compileWorkspace(
    List<BlockNode> roots, {
    Map<String, NodeQlPluginBlock> pluginBlocks =
        const <String, NodeQlPluginBlock>{},
  }) {
    final plan = const SqliteProgramCompiler().compileWorkspace(
      roots,
      pluginBlocks: pluginBlocks,
    );
    final rendered = const SqliteDialectRenderer().render(plan.program);
    return SqlCompileResult(
      program: plan.program,
      sql: rendered.sql,
      warnings: <String>[...plan.warnings, ...rendered.warnings],
      sourceMap: rendered.sourceMap,
    );
  }
}

/// Connects a range in the generated SQLite text back to the visual node that
/// produced it. A node can own more than one range (for example SELECT and its
/// legacy pagination suffix).
class SqlNodeSourceSpan {
  const SqlNodeSourceSpan({
    required this.nodeId,
    required this.nodeType,
    required this.start,
    required this.end,
    required this.statementIndex,
  });

  final String nodeId;
  final BlockType nodeType;
  final int start;
  final int end;
  final int statementIndex;

  bool contains(int offset) => offset >= start && offset < end;

  String textIn(String sql) {
    if (start < 0 || end < start || end > sql.length) return '';
    return sql.substring(start, end);
  }

  SqlNodeSourceSpan shiftedBy(int offset, {int statementIndexOffset = 0}) {
    return SqlNodeSourceSpan(
      nodeId: nodeId,
      nodeType: nodeType,
      start: start + offset,
      end: end + offset,
      statementIndex: statementIndex + statementIndexOffset,
    );
  }
}

/// The sole boundary that turns a visual program into SQLite syntax.
class SqliteDialectRenderer {
  const SqliteDialectRenderer();

  SqliteRenderResult render(SqliteProgram program) {
    final roots = program.roots;
    final pluginBlocks = program.pluginBlocks;
    final sql = StringBuffer();
    final sourceMap = <SqlNodeSourceSpan>[];
    final warnings = <String>[];
    var statementIndex = 0;

    for (final root in roots.where((n) => n.type == BlockType.eventGreenFlag)) {
      if (root.next == null) continue;
      final rendered = _compileNode(
        root.next!,
        pluginBlocks: pluginBlocks,
        warnings: warnings,
        visited: <String>{root.id},
      );
      if (rendered.sql.isNotEmpty) {
        if (sql.isNotEmpty) sql.write('\n');
        final statementOffset = sql.length;
        sql.write(rendered.sql);
        if (!rendered.sql.endsWith(';')) sql.write(';');
        sourceMap.addAll(
          rendered.sourceMap.map(
            (span) => span.shiftedBy(
              statementOffset,
              statementIndexOffset: statementIndex,
            ),
          ),
        );
        final relativeLastStatement = rendered.sourceMap.fold<int>(
          0,
          (latest, span) =>
              span.statementIndex > latest ? span.statementIndex : latest,
        );
        statementIndex += relativeLastStatement + 1;
      }
    }
    return SqliteRenderResult(
      sql: sql.toString(),
      warnings: warnings,
      sourceMap: sourceMap,
    );
  }

  _RenderedSqlFragment _compileNode(
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
      return const _RenderedSqlFragment.empty();
    }
    final current = _compileSingle(
      node,
      pluginBlocks: pluginBlocks,
      warnings: warnings,
      visited: seen,
    ).trim();
    final spans = <SqlNodeSourceSpan>[
      if (current.isNotEmpty)
        SqlNodeSourceSpan(
          nodeId: node.id,
          nodeType: node.type,
          start: 0,
          end: current.length,
          statementIndex: 0,
        ),
    ];
    final buffer = StringBuffer(current);
    if (node.next != null) {
      final next = _compileNode(
        node.next!,
        pluginBlocks: pluginBlocks,
        warnings: warnings,
        visited: seen,
      );
      if (next.sql.isNotEmpty) {
        var statementIndexOffset = 0;
        if (buffer.isNotEmpty) {
          final separator = _separatorBetween(node.type, node.next!.type);
          buffer.write(separator);
          if (separator.contains(';')) statementIndexOffset = 1;
        }
        final nextOffset = buffer.length;
        buffer.write(next.sql);
        spans.addAll(
          next.sourceMap.map(
            (span) => span.shiftedBy(
              nextOffset,
              statementIndexOffset: statementIndexOffset,
            ),
          ),
        );
      }
    }
    seen.remove(node.id);
    if (node.type == BlockType.sqlSelect) {
      final pagination = _selectPagination(node, warnings).trim();
      if (pagination.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        final paginationStart = buffer.length;
        buffer.write(pagination);
        spans.add(
          SqlNodeSourceSpan(
            nodeId: node.id,
            nodeType: node.type,
            start: paginationStart,
            end: buffer.length,
            statementIndex: 0,
          ),
        );
      }
    }
    return _RenderedSqlFragment(sql: buffer.toString(), sourceMap: spans);
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
        final selectKeyword =
            _isEnabled(node.inputs['distinct']) ||
                '${node.inputs['select_mode'] ?? ''}'.trim().toUpperCase() ==
                    'DISTINCT'
            ? 'SELECT DISTINCT'
            : 'SELECT';
        if (node.next?.type == BlockType.sqlFrom) {
          return '$selectKeyword $cols';
        }
        final configuredFrom = node.inputs['table'] as String?;
        if (_isEnabled(node.inputs['omit_from']) ||
            (configuredFrom != null && configuredFrom.trim().isEmpty)) {
          return '$selectKeyword $cols';
        }
        final from = configuredFrom ?? 'table_name';
        return '$selectKeyword $cols FROM ${_withTableAlias(from, node)}';
      case BlockType.sqlColumn:
        return _withAlias(node.inputs['column'] as String? ?? '*', node);
      case BlockType.sqlText:
        final literalType = '${node.inputs['literal_type'] ?? 'text'}'
            .trim()
            .toLowerCase();
        final rawValue = '${node.inputs['text'] ?? ''}'.trim();
        switch (literalType) {
          case 'null':
            return 'NULL';
          case 'integer':
            final value = int.tryParse(rawValue);
            if (value == null) {
              warnings.add(
                '"$rawValue" is not a valid SQLite integer; using 0.',
              );
              return '0';
            }
            return '$value';
          case 'real':
            final value = double.tryParse(rawValue);
            if (value == null || !value.isFinite) {
              warnings.add(
                '"$rawValue" is not a valid SQLite real; using 0.0.',
              );
              return '0.0';
            }
            final compiled = '$value';
            return compiled.contains('.') ? compiled : '$compiled.0';
          case 'blob':
            final hex = rawValue.replaceAll(RegExp(r'\s+'), '').toUpperCase();
            if (hex.length.isOdd || !RegExp(r'^[0-9A-F]*$').hasMatch(hex)) {
              warnings.add(
                '"$rawValue" is not valid SQLite BLOB hex; using an empty BLOB.',
              );
              return "X''";
            }
            return "X'$hex'";
          default:
            final text = '${node.inputs['text'] ?? ''}'.replaceAll("'", "''");
            return "'$text'";
        }
      case BlockType.sqlAlias:
        final expression = _compileReporterInputAny(
          node,
          const <String>['value', 'expr'],
          '${node.inputs['value'] ?? node.inputs['expr'] ?? 'id'}',
          pluginBlocks: pluginBlocks,
          warnings: warnings,
          visited: visited,
        );
        return _withAlias(expression, node);
      case BlockType.sqlFrom:
        return 'FROM ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)}';
      case BlockType.sqlWhere:
        return 'WHERE ${_predicateFromInputs(node, fallback: '1 = 1')}';
      case BlockType.sqlAnd:
        return 'AND ${_predicateFromInputs(node, fallback: '1 = 1')}';
      case BlockType.sqlOr:
        return 'OR ${_predicateFromInputs(node, fallback: '1 = 1')}';
      case BlockType.sqlJoin:
        final joinType = _normalizedJoinType(node.inputs['join_type']);
        final table = node.inputs['table'] as String? ?? 'table_name';
        final source = _withTableAlias(
          table,
          node,
          fallbackAlias: joinType == 'SELF' ? 't2' : null,
        );
        final condition = _joinConditionFromInputs(node);
        return switch (joinType) {
          'CROSS' => 'CROSS JOIN $source',
          'NATURAL' => 'NATURAL JOIN $source',
          'SELF' => 'JOIN $source ON $condition',
          'INNER' ||
          'LEFT' ||
          'RIGHT' ||
          'FULL' => '$joinType JOIN $source ON $condition',
          _ => 'JOIN $source ON $condition',
        };
      case BlockType.sqlInnerJoin:
        return 'INNER JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlLeftJoin:
        return 'LEFT JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlRightJoin:
        return 'RIGHT JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlFullJoin:
        return 'FULL JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)} ON ${_joinConditionFromInputs(node)}';
      case BlockType.sqlCrossJoin:
        return 'CROSS JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)}';
      case BlockType.sqlSelfJoin:
        return 'JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node, fallbackAlias: 't2')} ON ${_joinConditionFromInputs(node, fallback: 't1.id = t2.id')}';
      case BlockType.sqlNaturalJoin:
        return 'NATURAL JOIN ${_withTableAlias(node.inputs['table'] as String? ?? 'table_name', node)}';
      case BlockType.sqlGroupBy:
        return 'GROUP BY ${node.inputs['column'] as String? ?? node.inputs['expr'] as String? ?? 'id'}';
      case BlockType.sqlHaving:
        return 'HAVING ${_havingPredicateFromInputs(node, pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}';
      case BlockType.sqlOrderBy:
        return 'ORDER BY ${_orderByFromInputs(node)}';
      case BlockType.sqlLimit:
        return _limitFromInputs(node, warnings);
      case BlockType.sqlUnion:
        final all =
            _isEnabled(node.inputs['all']) ||
            '${node.inputs['set_mode'] ?? ''}'.trim().toUpperCase() == 'ALL';
        return 'UNION${all ? ' ALL' : ''} ${_subquerySql(node.inputs['sql'], fallback: 'SELECT 1')}';
      case BlockType.sqlIntersect:
        return 'INTERSECT ${_subquerySql(node.inputs['sql'], fallback: 'SELECT 1')}';
      case BlockType.sqlExcept:
        return 'EXCEPT ${_subquerySql(node.inputs['sql'], fallback: 'SELECT 1')}';
      case BlockType.sqlSubqueryIn:
        return _subqueryInPredicate(node);
      case BlockType.sqlSubqueryAny:
        return '${node.inputs['lhs'] as String? ?? 'id'} IN (${node.inputs['sql'] as String? ?? 'SELECT id FROM t'})';
      case BlockType.sqlSubqueryAll:
        warnings.add(
          'SQLite does not support the ALL subquery operator. Use NOT EXISTS instead.',
        );
        return '';
      case BlockType.sqlCount:
        final expression = _compileReporterInputAny(
          node,
          const <String>['column', 'expr'],
          '${node.inputs['column'] ?? node.inputs['expr'] ?? '*'}',
          pluginBlocks: pluginBlocks,
          warnings: warnings,
          visited: visited,
        );
        final argument = _isEnabled(node.inputs['distinct'])
            ? 'DISTINCT $expression'
            : expression;
        return _withAlias('COUNT($argument)', node);
      case BlockType.sqlSum:
        return _withAlias(
          'SUM(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})',
          node,
        );
      case BlockType.sqlAvg:
        return _withAlias(
          'AVG(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})',
          node,
        );
      case BlockType.sqlMin:
        return _withAlias(
          'MIN(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})',
          node,
        );
      case BlockType.sqlMax:
        return _withAlias(
          'MAX(${_compileReporterInputAny(node, const <String>['column', 'expr'], '${node.inputs['column'] ?? node.inputs['expr'] ?? 'amount'}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})',
          node,
        );
      case BlockType.sqlConcat:
        return '(${_compileReporterInput(node, 'a', '${node.inputs['a'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)} || ${_compileReporterInput(node, 'b', '${node.inputs['b'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlSubstring:
        return 'substr(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}, ${node.inputs['start'] as String? ?? '1'}, ${node.inputs['len'] as String? ?? '1'})';
      case BlockType.sqlLength:
        return 'LENGTH(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlUpper:
        return 'UPPER(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlLower:
        return 'LOWER(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlTrim:
        return 'TRIM(${_compileReporterInput(node, 'expr', '${node.inputs['expr'] ?? "''"}', pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)})';
      case BlockType.sqlLeft:
        return 'substr(${node.inputs['expr'] as String? ?? "''"}, 1, ${node.inputs['n'] as String? ?? '1'})';
      case BlockType.sqlRight:
        return 'substr(${node.inputs['expr'] as String? ?? "''"}, -${node.inputs['n'] as String? ?? '1'})';
      case BlockType.sqlReplace:
        return 'REPLACE(${node.inputs['expr'] as String? ?? "''"}, ${node.inputs['from'] as String? ?? "''"}, ${node.inputs['to'] as String? ?? "''"})';
      case BlockType.sqlCurrentDate:
        return 'CURRENT_DATE';
      case BlockType.sqlCurrentTime:
        return 'CURRENT_TIME';
      case BlockType.sqlCurrentTimestamp:
        return 'CURRENT_TIMESTAMP';
      case BlockType.sqlDatePart:
        return _sqliteDatePart(
          '${node.inputs['part'] ?? 'day'}',
          node.inputs['expr'] as String? ?? 'CURRENT_DATE',
        );
      case BlockType.sqlDateAdd:
        return _sqliteDateModify(node, '+');
      case BlockType.sqlDateSub:
        return _sqliteDateModify(node, '-');
      case BlockType.sqlExtract:
        return _sqliteDatePart(
          '${node.inputs['part'] ?? 'day'}',
          node.inputs['expr'] as String? ?? 'CURRENT_DATE',
        );
      case BlockType.sqlToChar:
        return "strftime('${_sqliteDateFormat(node.inputs['fmt'] as String? ?? 'YYYY-MM-DD')}', ${node.inputs['expr'] as String? ?? 'CURRENT_DATE'})";
      case BlockType.sqlTimestampDiff:
        return _sqliteTimestampDiff(node);
      case BlockType.sqlDateDiff:
        return 'CAST(julianday(${node.inputs['b'] as String? ?? 'CURRENT_DATE'}) - julianday(${node.inputs['a'] as String? ?? 'CURRENT_DATE'}) AS INTEGER)';
      case BlockType.sqlCase:
        return 'CASE WHEN ${_predicateFromInputs(node, columnKey: 'condition_column', valueKey: 'condition_value', fallback: node.inputs['when'] as String? ?? '1 = 1')} THEN ${node.inputs['then'] as String? ?? node.inputs['result'] as String? ?? "'x'"} ELSE ${node.inputs['else'] as String? ?? node.inputs['default'] as String? ?? "'y'"} END';
      case BlockType.sqlIf:
        return 'CASE WHEN ${_predicateFromInputs(node, columnKey: 'condition_column', valueKey: 'condition_value', fallback: node.inputs['cond'] as String? ?? '1 = 1')} THEN ${node.inputs['a'] as String? ?? node.inputs['value'] as String? ?? "'x'"} ELSE ${node.inputs['b'] as String? ?? node.inputs['default'] as String? ?? "'y'"} END';
      case BlockType.sqlCoalesce:
        return 'COALESCE(${node.inputs['a'] as String? ?? 'NULL'}, ${node.inputs['b'] as String? ?? 'NULL'})';
      case BlockType.sqlNullIf:
        return 'NULLIF(${node.inputs['a'] as String? ?? '1'}, ${node.inputs['b'] as String? ?? '1'})';
      case BlockType.sqlInsert:
        final table = node.inputs['table'] as String? ?? 'table_name';
        final columns = '${node.inputs['columns'] ?? ''}'.trim();
        final columnList = columns.isEmpty ? '' : ' ($columns)';
        return 'INSERT INTO $table$columnList VALUES ${_insertRows(node.inputs['values'])}';
      case BlockType.sqlInsertOrReplace:
        final table = node.inputs['table'] as String? ?? 'table_name';
        final columns = '${node.inputs['columns'] ?? ''}'.trim();
        final columnList = columns.isEmpty ? '' : ' ($columns)';
        return 'INSERT OR REPLACE INTO $table$columnList VALUES ${_insertRows(node.inputs['values'])}';
      case BlockType.sqlUpsert:
        final table = node.inputs['table'] as String? ?? 'table_name';
        final columns = '${node.inputs['columns'] ?? ''}'.trim();
        final columnList = columns.isEmpty ? '' : ' ($columns)';
        final conflictColumns = '${node.inputs['conflict_columns'] ?? ''}'
            .trim();
        final conflictTarget = conflictColumns.isEmpty
            ? ''
            : ' ($conflictColumns)';
        final action = '${node.inputs['action'] ?? 'DO UPDATE'}'
            .trim()
            .toUpperCase();
        if (action == 'DO NOTHING') {
          return 'INSERT INTO $table$columnList VALUES ${_insertRows(node.inputs['values'])} ON CONFLICT$conflictTarget DO NOTHING';
        }
        final assignments = '${node.inputs['assignments'] ?? ''}'.trim();
        final fallbackColumn = columns.isEmpty
            ? 'id'
            : columns.split(',').first.trim();
        final update = assignments.isEmpty
            ? '$fallbackColumn = excluded.$fallbackColumn'
            : assignments;
        final where = '${node.inputs['update_where'] ?? ''}'.trim();
        return 'INSERT INTO $table$columnList VALUES ${_insertRows(node.inputs['values'])} ON CONFLICT$conflictTarget DO UPDATE SET $update${where.isEmpty ? '' : ' WHERE $where'}';
      case BlockType.sqlUpdate:
        return 'UPDATE ${node.inputs['table'] as String? ?? 'table_name'} SET ${node.inputs['column'] as String? ?? 'column_name'} = ${node.inputs['value'] as String? ?? 'value'} WHERE ${_predicateFromInputs(node, columnKey: 'where_column', valueKey: 'where_value', fallback: 'id = 1')}';
      case BlockType.sqlDelete:
        return 'DELETE FROM ${node.inputs['table'] as String? ?? 'table_name'} WHERE ${_predicateFromInputs(node, columnKey: 'where_column', valueKey: 'where_value', fallback: 'id = 1')}';
      case BlockType.sqlCreateTable:
        final ifNotExists = _isSqlOptionEnabled(
          node.inputs['if_not_exists'],
          'IF NOT EXISTS',
        );
        final table = node.inputs['table'] as String? ?? 'new_table';
        final definition = _tableDefinition(
          node.inputs['definition'],
          fallback: 'id INTEGER PRIMARY KEY',
        );
        return 'CREATE TABLE${ifNotExists ? ' IF NOT EXISTS' : ''} $table ($definition)';
      case BlockType.sqlCreateIndex:
        final unique = _isSqlOptionEnabled(node.inputs['unique'], 'UNIQUE');
        final ifNotExists = _isSqlOptionEnabled(
          node.inputs['if_not_exists'],
          'IF NOT EXISTS',
        );
        final name = node.inputs['name'] as String? ?? 'index_name';
        final table = node.inputs['table'] as String? ?? 'table_name';
        final columns = node.inputs['columns'] as String? ?? 'column_name';
        return 'CREATE${unique ? ' UNIQUE' : ''} INDEX${ifNotExists ? ' IF NOT EXISTS' : ''} $name ON $table ($columns)';
      case BlockType.sqlDropIndex:
        final ifExists = _isSqlOptionEnabled(
          node.inputs['if_exists'],
          'IF EXISTS',
        );
        return 'DROP INDEX${ifExists ? ' IF EXISTS' : ''} ${node.inputs['name'] ?? 'index_name'}';
      case BlockType.sqlCreateView:
        final temporary = _isSqlOptionEnabled(node.inputs['temporary'], 'TEMP');
        final ifNotExists = _isSqlOptionEnabled(
          node.inputs['if_not_exists'],
          'IF NOT EXISTS',
        );
        final name = node.inputs['name'] as String? ?? 'view_name';
        final columns = '${node.inputs['columns'] ?? ''}'.trim();
        final query = _trimSqlTerminator(
          '${node.inputs['sql'] ?? 'SELECT * FROM table_name'}',
        );
        return 'CREATE${temporary ? ' TEMP' : ''} VIEW${ifNotExists ? ' IF NOT EXISTS' : ''} $name${columns.isEmpty ? '' : ' ($columns)'} AS $query';
      case BlockType.sqlDropView:
        final ifExists = _isSqlOptionEnabled(
          node.inputs['if_exists'],
          'IF EXISTS',
        );
        return 'DROP VIEW${ifExists ? ' IF EXISTS' : ''} ${node.inputs['name'] ?? 'view_name'}';
      case BlockType.sqlCreateTrigger:
        final temporary = _isSqlOptionEnabled(node.inputs['temporary'], 'TEMP');
        final ifNotExists = _isSqlOptionEnabled(
          node.inputs['if_not_exists'],
          'IF NOT EXISTS',
        );
        final timing = _oneOf(node.inputs['timing'], const <String>{
          'BEFORE',
          'AFTER',
          'INSTEAD OF',
        }, 'AFTER');
        final event = _oneOf(node.inputs['event'], const <String>{
          'INSERT',
          'UPDATE',
          'DELETE',
        }, 'INSERT');
        final when = '${node.inputs['when'] ?? ''}'.trim();
        final body = _trimSqlTerminator('${node.inputs['body'] ?? 'SELECT 1'}');
        return 'CREATE${temporary ? ' TEMP' : ''} TRIGGER${ifNotExists ? ' IF NOT EXISTS' : ''} ${node.inputs['name'] ?? 'trigger_name'} $timing $event ON ${node.inputs['table'] ?? 'table_name'} FOR EACH ROW${when.isEmpty ? '' : ' WHEN $when'} BEGIN $body; END';
      case BlockType.sqlDropTrigger:
        final ifExists = _isSqlOptionEnabled(
          node.inputs['if_exists'],
          'IF EXISTS',
        );
        return 'DROP TRIGGER${ifExists ? ' IF EXISTS' : ''} ${node.inputs['name'] ?? 'trigger_name'}';
      case BlockType.sqlCreateVirtualTable:
        final ifNotExists = _isSqlOptionEnabled(
          node.inputs['if_not_exists'],
          'IF NOT EXISTS',
        );
        final module = _oneOf(node.inputs['module'], const <String>{
          'FTS5',
          'RTREE',
        }, 'FTS5').toLowerCase();
        final arguments = '${node.inputs['arguments'] ?? 'content'}'.trim();
        return 'CREATE VIRTUAL TABLE${ifNotExists ? ' IF NOT EXISTS' : ''} ${node.inputs['table'] ?? 'virtual_table'} USING $module($arguments)';
      case BlockType.sqlAlterTable:
        final legacyAlter = '${node.inputs['alter'] ?? ''}'.trim();
        if (legacyAlter.isNotEmpty) {
          return 'ALTER TABLE ${node.inputs['table'] as String? ?? 'table_name'} $legacyAlter';
        }
        final action = _oneOf(node.inputs['alter_action'], const <String>{
          'ADD COLUMN',
          'RENAME COLUMN',
          'DROP COLUMN',
          'RENAME TO',
        }, 'ADD COLUMN');
        return 'ALTER TABLE ${node.inputs['table'] as String? ?? 'table_name'} $action ${node.inputs['alter_value'] ?? 'new_column TEXT'}';
      case BlockType.sqlTruncate:
        return 'DELETE FROM ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlDropTable:
        final ifExists = _isSqlOptionEnabled(
          node.inputs['if_exists'],
          'IF EXISTS',
        );
        return 'DROP TABLE${ifExists ? ' IF EXISTS' : ''} ${node.inputs['table'] as String? ?? 'table_name'}';
      case BlockType.sqlGrant:
        warnings.add('SQLite has no GRANT statement or user management.');
        return '';
      case BlockType.sqlRevoke:
        warnings.add('SQLite has no REVOKE statement or user management.');
        return '';
      case BlockType.sqlCommit:
        return 'COMMIT';
      case BlockType.sqlBeginTransaction:
        final behavior = _oneOf(node.inputs['behavior'], const <String>{
          'DEFERRED',
          'IMMEDIATE',
          'EXCLUSIVE',
        }, 'DEFERRED');
        return 'BEGIN $behavior TRANSACTION';
      case BlockType.sqlEndTransaction:
        return 'END TRANSACTION';
      case BlockType.sqlRollback:
        return 'ROLLBACK';
      case BlockType.sqlSavepoint:
        return 'SAVEPOINT ${node.inputs['name'] as String? ?? 'sp1'}';
      case BlockType.sqlRollbackToSavepoint:
        return 'ROLLBACK TO SAVEPOINT ${node.inputs['name'] as String? ?? 'sp1'}';
      case BlockType.sqlReleaseSavepoint:
        return 'RELEASE SAVEPOINT ${node.inputs['name'] as String? ?? 'sp1'}';
      case BlockType.sqlSetTransaction:
        warnings.add(
          'SQLite does not support SET TRANSACTION isolation levels.',
        );
        return '';
      case BlockType.sqlPragma:
        return _compilePragma(node, warnings);
      case BlockType.sqlAttachDatabase:
        final path = _quoteSqlString('${node.inputs['path'] ?? 'database.db'}');
        final schema = _quoteSqlIdentifier(
          '${node.inputs['schema'] ?? 'attached'}',
        );
        return 'ATTACH DATABASE $path AS $schema';
      case BlockType.sqlDetachDatabase:
        return 'DETACH DATABASE ${_quoteSqlIdentifier('${node.inputs['schema'] ?? 'attached'}')}';
      case BlockType.sqlVacuum:
        final schema = '${node.inputs['schema'] ?? ''}'.trim();
        return 'VACUUM${schema.isEmpty ? '' : ' ${_quoteSqlIdentifier(schema)}'}';
      case BlockType.sqlReindex:
        final target = '${node.inputs['target'] ?? ''}'.trim();
        return 'REINDEX${target.isEmpty ? '' : ' $target'}';
      case BlockType.sqlAnalyze:
        final target = '${node.inputs['target'] ?? ''}'.trim();
        return 'ANALYZE${target.isEmpty ? '' : ' $target'}';
      case BlockType.sqlExplain:
        final mode = _oneOf(node.inputs['mode'], const <String>{
          'EXPLAIN',
          'EXPLAIN QUERY PLAN',
        }, 'EXPLAIN QUERY PLAN');
        if (node.next != null) return mode;
        return '$mode ${_trimSqlTerminator('${node.inputs['sql'] ?? 'SELECT 1'}')}';
      case BlockType.sqlWith:
        final recursive = _isSqlOptionEnabled(
          node.inputs['recursive'],
          'RECURSIVE',
        );
        final name = node.inputs['name'] as String? ?? 'cte';
        final columns = '${node.inputs['columns'] ?? ''}'.trim();
        final cteSql = _trimSqlTerminator(
          '${node.inputs['sql'] ?? 'SELECT 1'}',
        );
        final prefix =
            'WITH${recursive ? ' RECURSIVE' : ''} $name${columns.isEmpty ? '' : ' ($columns)'} AS ($cteSql)';
        if (node.next != null) return prefix;
        final statement = _trimSqlTerminator(
          '${node.inputs['statement'] ?? 'SELECT * FROM $name'}',
        );
        return '$prefix $statement';
      case BlockType.sqlValues:
        return 'VALUES ${_insertRows(node.inputs['values'])}';
      case BlockType.sqlLoop:
        // NodeQL loop compiles contained statements as transaction body.
        return 'BEGIN; ${_compileChildren(node.children, pluginBlocks: pluginBlocks, warnings: warnings, visited: visited)}; COMMIT';
    }
  }

  String _sqliteDatePart(String part, String expression) {
    final format = switch (part.trim().toLowerCase().replaceAll("'", '')) {
      'year' => '%Y',
      'month' => '%m',
      'day' => '%d',
      'hour' => '%H',
      'minute' => '%M',
      'second' => '%S',
      'weekday' => '%w',
      _ => '%d',
    };
    return "CAST(strftime('$format', $expression) AS INTEGER)";
  }

  String _sqliteDateModify(BlockNode node, String sign) {
    final expression = node.inputs['expr'] as String? ?? 'CURRENT_DATE';
    final amount = node.inputs['n'] as String? ?? '1';
    final unit = (node.inputs['unit'] as String? ?? 'DAY').toLowerCase();
    return "datetime($expression, '$sign$amount $unit')";
  }

  String _sqliteDateFormat(String format) {
    return format
        .replaceAll("'", '')
        .replaceAll('YYYY', '%Y')
        .replaceAll('YY', '%y')
        .replaceAll('MM', '%m')
        .replaceAll('DD', '%d')
        .replaceAll('HH24', '%H')
        .replaceAll('MI', '%M')
        .replaceAll('SS', '%S');
  }

  String _sqliteTimestampDiff(BlockNode node) {
    final a = node.inputs['a'] as String? ?? 'CURRENT_DATE';
    final b = node.inputs['b'] as String? ?? 'CURRENT_DATE';
    final divisor = switch ((node.inputs['unit'] as String? ?? 'DAY')
        .toUpperCase()) {
      'SECOND' || 'SECONDS' => 1 / 86400,
      'MINUTE' || 'MINUTES' => 1 / 1440,
      'HOUR' || 'HOURS' => 1 / 24,
      'WEEK' || 'WEEKS' => 7,
      _ => 1,
    };
    return 'CAST((julianday($b) - julianday($a)) / $divisor AS INTEGER)';
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
    final requestedOrder = '${node.inputs['order'] ?? 'ASC'}'
        .trim()
        .toUpperCase();
    final order = requestedOrder == 'DESC' ? 'DESC' : 'ASC';
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
    final conditions = node.inputs['conditions'];
    if (conditions is List && conditions.isNotEmpty) {
      final compiled = _compileStructuredConditions(
        conditions,
        node.inputs['match'],
      );
      if (compiled.isNotEmpty) {
        return _negatePredicate(
          compiled,
          node.inputs['negated'] ?? node.inputs['negation'],
        );
      }
    }

    final valueReporter = reporterForInput(node, valueKey);
    if (valueReporter?.type == BlockType.sqlSubqueryIn) {
      return _negatePredicate(
        _subqueryInPredicate(valueReporter!),
        node.inputs['negated'] ?? node.inputs['negation'],
      );
    }

    final column = '${node.inputs[columnKey] ?? ''}'.trim();
    final operator = _normalizedComparisonOperator(node.inputs[operatorKey]);
    final value = '${node.inputs[valueKey] ?? ''}'.trim();
    if (column.isEmpty ||
        (value.isEmpty && operator != 'IS NULL' && operator != 'IS NOT NULL')) {
      final predicate = node.inputs['predicate'] as String? ?? fallback;
      return _negatePredicate(
        predicate,
        node.inputs['negated'] ?? node.inputs['negation'],
      );
    }
    if (operator == 'IS NULL' || operator == 'IS NOT NULL') {
      return _negatePredicate(
        '$column $operator',
        node.inputs['negated'] ?? node.inputs['negation'],
      );
    }
    final predicate = switch (operator) {
      'IN' || 'NOT IN' => '$column $operator (${_inOperand(value)})',
      'BETWEEN' || 'NOT BETWEEN' => '$column $operator $value',
      _ => '$column $operator $value',
    };
    return _negatePredicate(
      predicate,
      node.inputs['negated'] ?? node.inputs['negation'],
    );
  }

  String _compileStructuredPredicate(Map<String, dynamic> condition) {
    final nested = condition['conditions'];
    if (nested is List && nested.isNotEmpty) {
      final group = _compileStructuredConditions(nested, condition['match']);
      if (group.isEmpty) return '';
      return _isNegated(condition['negated'] ?? condition['negation'])
          ? 'NOT ($group)'
          : '($group)';
    }

    final column = '${condition['column'] ?? ''}'.trim();
    if (column.isEmpty) return '';
    final operator = _normalizedComparisonOperator(condition['operator']);
    if (operator == 'IS NULL' || operator == 'IS NOT NULL') {
      return _negatePredicate(
        '$column $operator',
        condition['negated'] ?? condition['negation'],
      );
    }

    if (operator == 'BETWEEN' || operator == 'NOT BETWEEN') {
      final rawValue = condition['value'];
      final values = rawValue is List ? rawValue : const <dynamic>[];
      final lower =
          '${condition['lower'] ?? (values.isNotEmpty ? values[0] : '')}'
              .trim();
      final upper =
          '${condition['upper'] ?? (values.length > 1 ? values[1] : '')}'
              .trim();
      if (lower.isEmpty || upper.isEmpty) return '';
      return _negatePredicate(
        '$column $operator $lower AND $upper',
        condition['negated'] ?? condition['negation'],
      );
    }

    if (operator == 'IN' || operator == 'NOT IN') {
      final rawValue = condition['value'];
      final value = rawValue is List
          ? rawValue.map((entry) => '$entry').join(', ')
          : '${rawValue ?? ''}'.trim();
      if (value.isEmpty) return '';
      return _negatePredicate(
        '$column $operator (${_inOperand(value)})',
        condition['negated'] ?? condition['negation'],
      );
    }

    final value = '${condition['value'] ?? ''}'.trim();
    if (value.isEmpty) return '';
    return _negatePredicate(
      '$column $operator $value',
      condition['negated'] ?? condition['negation'],
    );
  }

  String _compileStructuredConditions(List<dynamic> conditions, dynamic match) {
    final fallbackConnector = '${match ?? 'ALL'}'.trim().toUpperCase() == 'ANY'
        ? 'OR'
        : 'AND';
    final compiled = <String>[];
    for (final condition in conditions) {
      if (condition is! Map) continue;
      final values = Map<String, dynamic>.from(condition);
      final predicate = _compileStructuredPredicate(values);
      if (predicate.isEmpty) continue;
      if (compiled.isNotEmpty) {
        final requested = '${values['connector'] ?? fallbackConnector}'
            .trim()
            .toUpperCase();
        compiled.add(requested == 'OR' ? 'OR' : 'AND');
      }
      compiled.add(predicate);
    }
    return compiled.join(' ');
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
      'GLOB',
      'IS',
      'IS NOT',
      'IS NULL',
      'IS NOT NULL',
      'IN',
      'NOT IN',
      'BETWEEN',
      'NOT BETWEEN',
    };
    return supported.contains(normalized) ? normalized : defaultValue;
  }

  String _selectPagination(BlockNode node, List<String> warnings) {
    final rawLimit = _nonBlank(node.inputs['limit']);
    final rawOffset = _nonBlank(node.inputs['offset']);
    if (rawLimit == null && rawOffset == null) return '';

    final limit = rawLimit == null ? null : int.tryParse('$rawLimit'.trim());
    final offset = rawOffset == null ? null : int.tryParse('$rawOffset'.trim());
    if (rawLimit != null && (limit == null || limit < 0)) {
      warnings.add(
        'SELECT block "${node.id}" has an invalid LIMIT. Use a non-negative integer.',
      );
      return '';
    }
    if (rawOffset != null && (offset == null || offset < 0)) {
      warnings.add(
        'SELECT block "${node.id}" has an invalid OFFSET. Use a non-negative integer.',
      );
      return limit == null ? '' : ' LIMIT $limit';
    }
    if (limit == null) return ' LIMIT -1 OFFSET $offset';
    return offset == null ? ' LIMIT $limit' : ' LIMIT $limit OFFSET $offset';
  }

  String _limitFromInputs(BlockNode node, List<String> warnings) {
    final rawCount = _nonBlank(node.inputs['count'] ?? node.inputs['limit']);
    final rawOffset = _nonBlank(node.inputs['offset']);
    final count = rawCount == null ? null : int.tryParse('$rawCount'.trim());
    final offset = rawOffset == null ? null : int.tryParse('$rawOffset'.trim());
    if (count == null || count < 0) {
      warnings.add(
        'LIMIT block "${node.id}" needs a non-negative integer count.',
      );
      return '';
    }
    if (rawOffset != null && (offset == null || offset < 0)) {
      warnings.add(
        'LIMIT block "${node.id}" has an invalid OFFSET. Use a non-negative integer.',
      );
      return 'LIMIT $count';
    }
    return offset == null ? 'LIMIT $count' : 'LIMIT $count OFFSET $offset';
  }

  dynamic _nonBlank(dynamic value) {
    if (value == null) return null;
    return '$value'.trim().isEmpty ? null : value;
  }

  String _negatePredicate(String predicate, dynamic negated) {
    return _isNegated(negated) ? 'NOT ($predicate)' : predicate;
  }

  bool _isNegated(dynamic value) {
    return _isEnabled(value) || '${value ?? ''}'.trim().toUpperCase() == 'NOT';
  }

  String _withoutOuterParentheses(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith('(') &&
        trimmed.endsWith(')')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  String _inOperand(String value) {
    final operand = _withoutOuterParentheses(value);
    return operand.trimLeft().toUpperCase().startsWith('SELECT ')
        ? _subquerySql(operand, fallback: operand)
        : operand;
  }

  String _subqueryInPredicate(BlockNode node) {
    final lhs =
        node.inputs['lhs'] as String? ??
        node.inputs['column'] as String? ??
        'id';
    final sql = _subquerySql(node.inputs['sql'], fallback: 'SELECT id FROM t');
    return '$lhs IN ($sql)';
  }

  String _subquerySql(dynamic value, {required String fallback}) {
    final sql = '${value ?? fallback}'.trim();
    return sql.endsWith(';') ? sql.substring(0, sql.length - 1).trim() : sql;
  }

  String _insertRows(dynamic value) {
    var rows = '${value ?? ''}'.trim();
    if (rows.toUpperCase().startsWith('VALUES ')) {
      rows = rows.substring('VALUES '.length).trimLeft();
    }
    if (rows.endsWith(';')) {
      rows = rows.substring(0, rows.length - 1).trimRight();
    }
    if (rows.isEmpty) return '()';
    return rows.startsWith('(') ? rows : '($rows)';
  }

  String _tableDefinition(dynamic value, {required String fallback}) {
    var definition = '${value ?? fallback}'.trim();
    if (definition.endsWith(';')) {
      definition = definition.substring(0, definition.length - 1).trimRight();
    }
    if (definition.startsWith('(') && definition.endsWith(')')) {
      definition = definition.substring(1, definition.length - 1).trim();
    }
    return definition.isEmpty ? fallback : definition;
  }

  bool _isSqlOptionEnabled(dynamic value, String sqlKeyword) {
    return _isEnabled(value) ||
        '${value ?? ''}'.trim().toUpperCase() == sqlKeyword;
  }

  bool _isEnabled(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const <String>{
      'TRUE',
      'YES',
      'ON',
      '1',
    }.contains('${value ?? ''}'.trim().toUpperCase());
  }

  String _withAlias(String expression, BlockNode node) {
    return _withIdentifierAlias(expression, node.inputs['alias']);
  }

  String _withTableAlias(
    String table,
    BlockNode node, {
    String? fallbackAlias,
  }) {
    final configuredAlias = '${node.inputs['table_alias'] ?? ''}'.trim();
    return _withIdentifierAlias(
      table,
      configuredAlias.isEmpty ? fallbackAlias : configuredAlias,
    );
  }

  String _withIdentifierAlias(String expression, dynamic rawAlias) {
    final alias = '${rawAlias ?? ''}'.trim();
    if (alias.isEmpty) return expression;
    final simpleIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (simpleIdentifier.hasMatch(alias)) return '$expression AS $alias';
    return '$expression AS "${alias.replaceAll('"', '""')}"';
  }

  String _separatorBetween(BlockType current, BlockType next) {
    if (current == BlockType.sqlWith || current == BlockType.sqlExplain) {
      return ' ';
    }
    if (startsSqlStatement(current) && startsSqlStatement(next)) {
      return '; ';
    }
    return ' ';
  }

  String _oneOf(dynamic value, Set<String> choices, String fallback) {
    final normalized = '${value ?? ''}'.trim().toUpperCase();
    return choices.contains(normalized) ? normalized : fallback;
  }

  String _trimSqlTerminator(String sql) {
    return sql.trim().replaceFirst(RegExp(r';+\s*$'), '');
  }

  String _quoteSqlString(String value) {
    final unquoted =
        value.length >= 2 && value.startsWith("'") && value.endsWith("'")
        ? value.substring(1, value.length - 1).replaceAll("''", "'")
        : value;
    return "'${unquoted.replaceAll("'", "''")}'";
  }

  String _quoteSqlIdentifier(String value) {
    return '"${value.trim().replaceAll('"', '""')}"';
  }

  String _compilePragma(BlockNode node, List<String> warnings) {
    final name = '${node.inputs['pragma'] ?? 'foreign_keys'}'
        .trim()
        .toLowerCase();
    final value = '${node.inputs['value'] ?? ''}'.trim();
    switch (name) {
      case 'foreign_keys':
        return 'PRAGMA foreign_keys = ${_oneOf(value, const <String>{'ON', 'OFF'}, 'ON')}';
      case 'table_info':
        return 'PRAGMA table_info(${_quoteSqlString(value.isEmpty ? 'table_name' : value)})';
      case 'database_list':
        return 'PRAGMA database_list';
      case 'journal_mode':
        return 'PRAGMA journal_mode = ${_oneOf(value, const <String>{'DELETE', 'TRUNCATE', 'PERSIST', 'MEMORY', 'WAL', 'OFF'}, 'WAL')}';
      default:
        warnings.add(
          'Unsupported PRAGMA "$name" at block "${node.id}". Using foreign_keys = ON.',
        );
        return 'PRAGMA foreign_keys = ON';
    }
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
        ).sql,
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

class SqliteRenderResult {
  const SqliteRenderResult({
    required this.sql,
    required this.warnings,
    this.sourceMap = const <SqlNodeSourceSpan>[],
  });

  final String sql;
  final List<String> warnings;
  final List<SqlNodeSourceSpan> sourceMap;
}

class SqlCompileResult {
  const SqlCompileResult({
    required this.program,
    required this.sql,
    required this.warnings,
    this.sourceMap = const <SqlNodeSourceSpan>[],
  });

  final SqliteProgram program;
  final String sql;
  final List<String> warnings;
  final List<SqlNodeSourceSpan> sourceMap;
}

class _RenderedSqlFragment {
  const _RenderedSqlFragment({required this.sql, required this.sourceMap});

  const _RenderedSqlFragment.empty()
    : sql = '',
      sourceMap = const <SqlNodeSourceSpan>[];

  final String sql;
  final List<SqlNodeSourceSpan> sourceMap;
}
