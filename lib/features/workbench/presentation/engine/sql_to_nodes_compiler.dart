import 'dart:ui';

import 'package:nodeql/engine/block/block_node.dart';

/// Converts a deliberately practical subset of handwritten SQLite into visual
/// NodeQL chains. It does not pretend to be a full SQL parser: unsupported
/// statements stay in the editor and are reported to the caller instead of
/// producing misleading nodes.
class SqlToNodesCompiler {
  int _nextId = 0;

  SqlToNodesImportResult compile(String source) {
    _nextId = 0;
    final roots = <BlockNode>[];
    final warnings = <String>[];

    for (final statement in _splitStatements(source)) {
      final root = _compileStatement(statement, warnings);
      if (root != null) roots.add(root);
    }

    return SqlToNodesImportResult(roots: roots, warnings: warnings);
  }

  BlockNode? _compileStatement(String statement, List<String> warnings) {
    final sql = statement.trim();
    if (sql.isEmpty) return null;
    final root = _eventRoot(Offset(120, 120 + (_nextId * 220.0)));
    final upper = sql.toUpperCase();

    final first = switch (upper) {
      _ when upper.startsWith('SELECT ') || upper == 'SELECT' => _compileSelect(
        sql,
        warnings,
      ),
      _ when upper.startsWith('INSERT ') => _compileInsert(sql, warnings),
      _ when upper.startsWith('UPDATE ') => _compileUpdate(sql, warnings),
      _ when upper.startsWith('DELETE ') => _compileDelete(sql, warnings),
      _ when upper.startsWith('CREATE TABLE ') => _compileCreateTable(sql),
      _ when upper.startsWith('DROP TABLE ') => _compileDropTable(sql),
      _ when upper.startsWith('CREATE ') && upper.contains(' INDEX ') =>
        _compileCreateIndex(sql),
      _ when upper.startsWith('DROP INDEX ') => _compileDropIndex(sql),
      _ when upper.startsWith('ALTER TABLE ') => _compileAlterTable(sql),
      _ when upper.startsWith('BEGIN') => _node(
        BlockType.sqlBeginTransaction,
        <String, dynamic>{'behavior': _transactionBehavior(upper)},
      ),
      _ when upper == 'COMMIT' || upper == 'COMMIT TRANSACTION' => _node(
        BlockType.sqlCommit,
      ),
      _ when upper == 'END' || upper == 'END TRANSACTION' => _node(
        BlockType.sqlEndTransaction,
      ),
      _ when upper == 'ROLLBACK' || upper == 'ROLLBACK TRANSACTION' => _node(
        BlockType.sqlRollback,
      ),
      _ when upper.startsWith('SAVEPOINT ') => _node(
        BlockType.sqlSavepoint,
        <String, dynamic>{'name': sql.substring('SAVEPOINT '.length).trim()},
      ),
      _ when upper.startsWith('RELEASE ') =>
        _node(BlockType.sqlReleaseSavepoint, <String, dynamic>{
          'name': sql
              .replaceFirst(
                RegExp(r'^RELEASE\s+(?:SAVEPOINT\s+)?', caseSensitive: false),
                '',
              )
              .trim(),
        }),
      _ when upper.startsWith('VACUUM') =>
        _node(BlockType.sqlVacuum, <String, dynamic>{
          'schema': sql.length > 'VACUUM'.length
              ? sql.substring('VACUUM'.length).trim()
              : '',
        }),
      _ when upper.startsWith('ANALYZE') =>
        _node(BlockType.sqlAnalyze, <String, dynamic>{
          'target': sql.length > 'ANALYZE'.length
              ? sql.substring('ANALYZE'.length).trim()
              : '',
        }),
      _ when upper.startsWith('REINDEX') =>
        _node(BlockType.sqlReindex, <String, dynamic>{
          'target': sql.length > 'REINDEX'.length
              ? sql.substring('REINDEX'.length).trim()
              : '',
        }),
      _ => null,
    };

    if (first == null) {
      warnings.add(
        'No visual node importer is available for: ${_summary(sql)}',
      );
      return null;
    }
    root.next = first;
    return root;
  }

  BlockNode? _compileSelect(String sql, List<String> warnings) {
    final compound = _firstTopLevelKeyword(sql, const <String>[
      'UNION ALL',
      'UNION',
      'INTERSECT',
      'EXCEPT',
    ], start: 'SELECT'.length);
    final selectSql = compound == null ? sql : sql.substring(0, compound.index);
    final rest = selectSql.substring('SELECT'.length).trim();
    final from = _firstTopLevelKeyword(rest, const <String>['FROM']);
    final selectHead = from == null
        ? rest
        : rest.substring(0, from.index).trim();
    final distinct = selectHead.toUpperCase().startsWith('DISTINCT ');
    final columns = distinct
        ? selectHead.substring('DISTINCT'.length).trim()
        : selectHead;
    final select = _node(BlockType.sqlSelect, <String, dynamic>{
      'columns': columns.isEmpty ? '*' : columns,
      'table': '',
      'table_alias': '',
      'omit_from': from == null,
      // A following FROM node owns the source. Mark this explicitly so the
      // visual SELECT node does not render an empty, duplicate table slot.
      'separate_from': from != null,
      'distinct': distinct,
      'select_mode': distinct ? 'DISTINCT' : 'ALL',
    });
    BlockNode tail = select;

    if (from != null) {
      final clauses = _topLevelClauses(
        rest.substring(from.index + 'FROM'.length),
        const <String>['WHERE', 'GROUP BY', 'HAVING', 'ORDER BY', 'LIMIT'],
      );
      final sourceEnd = clauses.isEmpty
          ? rest.length
          : from.index + 'FROM'.length + clauses.first.index;
      final source = rest
          .substring(from.index + 'FROM'.length, sourceEnd)
          .trim();
      final fromChain = _compileFromSource(source, warnings);
      if (fromChain == null) {
        warnings.add('Could not read the FROM source in: ${_summary(sql)}');
      } else {
        select.inputs['table'] = fromChain.$1.inputs['table'];
        select.inputs['table_alias'] = fromChain.$1.inputs['table_alias'];
        tail.next = fromChain.$1;
        tail = fromChain.$2;
      }

      for (final clause in clauses) {
        final valueStart =
            from.index + 'FROM'.length + clause.index + clause.keyword.length;
        final valueEnd = _nextClauseEnd(
          clauses,
          clause,
          rest.length,
          from.index + 'FROM'.length,
        );
        final value = rest.substring(valueStart, valueEnd).trim();
        final node = switch (clause.keyword) {
          'WHERE' => _clause(BlockType.sqlWhere, _predicateInputs(value)),
          'GROUP BY' => _node(BlockType.sqlGroupBy, <String, dynamic>{
            'column': value,
            'expr': value,
          }),
          'HAVING' => _node(BlockType.sqlHaving, _havingInputs(value)),
          'ORDER BY' => _clause(BlockType.sqlOrderBy, _orderByInputs(value)),
          'LIMIT' => _limitNode(value, warnings),
          _ => null,
        };
        if (node != null) {
          tail.next = node;
          tail = node;
        }
      }
    }

    if (compound != null) {
      final kind = compound.keyword == 'INTERSECT'
          ? BlockType.sqlIntersect
          : compound.keyword == 'EXCEPT'
          ? BlockType.sqlExcept
          : BlockType.sqlUnion;
      final rhs = sql
          .substring(compound.index + compound.keyword.length)
          .trim();
      final inputs = <String, dynamic>{'sql': rhs};
      if (compound.keyword == 'UNION ALL') inputs['set_mode'] = 'ALL';
      final node = _node(kind, inputs);
      tail.next = node;
    }
    return select;
  }

  (BlockNode, BlockNode)? _compileFromSource(
    String source,
    List<String> warnings,
  ) {
    final joins = _topLevelClauses(source, const <String>[
      'INNER JOIN',
      'LEFT JOIN',
      'RIGHT JOIN',
      'FULL JOIN',
      'CROSS JOIN',
      'NATURAL JOIN',
      'JOIN',
    ]);
    final table = source
        .substring(0, joins.isEmpty ? source.length : joins.first.index)
        .trim();
    if (table.isEmpty) return null;
    final sourceReference = _tableReference(table);
    final from = _node(BlockType.sqlFrom, <String, dynamic>{
      'table': sourceReference.table,
      'table_alias': sourceReference.alias,
    });
    BlockNode tail = from;
    for (var index = 0; index < joins.length; index++) {
      final join = joins[index];
      final end = index + 1 < joins.length
          ? joins[index + 1].index
          : source.length;
      final body = source
          .substring(join.index + join.keyword.length, end)
          .trim();
      final on = _firstTopLevelKeyword(body, const <String>['ON']);
      final tablePart = (on == null ? body : body.substring(0, on.index))
          .trim();
      if (tablePart.isEmpty) {
        warnings.add('A JOIN without a table was skipped.');
        continue;
      }
      final joinType = join.keyword == 'JOIN'
          ? 'INNER'
          : join.keyword.replaceFirst(' JOIN', '');
      final tableReference = _tableReference(tablePart);
      final inputs = <String, dynamic>{
        'join_type': joinType,
        'table': tableReference.table,
        'table_alias': tableReference.alias,
        'left_column': '',
        'operator': '=',
        'right_column': '',
      };
      if (on != null) {
        final condition = body.substring(on.index + 'ON'.length).trim();
        inputs['on'] = condition;
        inputs.addAll(_joinConditionInputs(condition));
      }
      final node = _node(BlockType.sqlJoin, inputs);
      tail.next = node;
      tail = node;
    }
    return (from, tail);
  }

  BlockNode? _compileInsert(String sql, List<String> warnings) {
    final match = RegExp(
      r'^INSERT\s+(OR\s+REPLACE\s+)?INTO\s+([^\s(]+)\s*(?:\(([^)]*)\))?\s+VALUES\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    if (match == null) {
      warnings.add('Only INSERT ... VALUES can be converted to nodes.');
      return null;
    }
    return _node(
      match.group(1) == null
          ? BlockType.sqlInsert
          : BlockType.sqlInsertOrReplace,
      <String, dynamic>{
        'table': match.group(2)!.trim(),
        'columns': match.group(3)?.trim() ?? '',
        'values': match.group(4)!.trim(),
      },
    );
  }

  BlockNode? _compileUpdate(String sql, List<String> warnings) {
    final match = RegExp(
      r'^UPDATE\s+([^\s]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    if (match == null) return null;
    final assignment = RegExp(
      r'^(.+?)\s*=\s*(.+)$',
      dotAll: true,
    ).firstMatch(match.group(2)!.trim());
    if (assignment == null || assignment.group(2)!.contains(',')) {
      warnings.add('Only one UPDATE assignment can be converted to a node.');
      return null;
    }
    final where = _whereInputs(match.group(3)?.trim() ?? '1 = 1');
    return _node(BlockType.sqlUpdate, <String, dynamic>{
      'table': match.group(1)!.trim(),
      'column': assignment.group(1)!.trim(),
      'value': assignment.group(2)!.trim(),
      ...where,
    });
  }

  BlockNode? _compileDelete(String sql, List<String> warnings) {
    final match = RegExp(
      r'^DELETE\s+FROM\s+([^\s]+)(?:\s+WHERE\s+(.+))?$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    if (match == null) return null;
    final where = _whereInputs(match.group(2)?.trim() ?? '1 = 1');
    return _node(BlockType.sqlDelete, <String, dynamic>{
      'table': match.group(1)!.trim(),
      ...where,
    });
  }

  BlockNode? _compileCreateTable(String sql) {
    final match = RegExp(
      r'^CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([^\s(]+)\s*\((.*)\)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    if (match == null) return null;
    return _node(BlockType.sqlCreateTable, <String, dynamic>{
      'if_not_exists': match.group(1) == null ? '' : 'IF NOT EXISTS',
      'table': match.group(2)!.trim(),
      'definition': match.group(3)!.trim(),
    });
  }

  BlockNode? _compileDropTable(String sql) {
    final match = RegExp(
      r'^DROP\s+TABLE\s+(IF\s+EXISTS\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(sql);
    if (match == null) return null;
    return _node(BlockType.sqlDropTable, <String, dynamic>{
      'if_exists': match.group(1) == null ? '' : 'IF EXISTS',
      'table': match.group(2)!.trim(),
    });
  }

  BlockNode? _compileCreateIndex(String sql) {
    final match = RegExp(
      r'^CREATE\s+(UNIQUE\s+)?INDEX\s+(IF\s+NOT\s+EXISTS\s+)?([^\s]+)\s+ON\s+([^\s(]+)\s*\((.*)\)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    if (match == null) return null;
    return _node(BlockType.sqlCreateIndex, <String, dynamic>{
      'unique': match.group(1) == null ? '' : 'UNIQUE',
      'if_not_exists': match.group(2) == null ? '' : 'IF NOT EXISTS',
      'name': match.group(3)!.trim(),
      'table': match.group(4)!.trim(),
      'columns': match.group(5)!.trim(),
    });
  }

  BlockNode? _compileDropIndex(String sql) {
    final match = RegExp(
      r'^DROP\s+INDEX\s+(IF\s+EXISTS\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(sql);
    if (match == null) return null;
    return _node(BlockType.sqlDropIndex, <String, dynamic>{
      'if_exists': match.group(1) == null ? '' : 'IF EXISTS',
      'name': match.group(2)!.trim(),
    });
  }

  BlockNode? _compileAlterTable(String sql) {
    final match = RegExp(
      r'^ALTER\s+TABLE\s+([^\s]+)\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    if (match == null) return null;
    final alter = match.group(2)!.trim();
    return _node(BlockType.sqlAlterTable, <String, dynamic>{
      'table': match.group(1)!.trim(),
      'alter': alter,
      ..._alterInputs(alter),
    });
  }

  _SqlTableReference _tableReference(String source) {
    final value = source.trim();
    if (value.isEmpty || value.startsWith('(')) {
      return _SqlTableReference(value, '');
    }
    final match = RegExp(
      r'^(.*?)\s+(?:AS\s+)?("[^"]+"|`[^`]+`|\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_$]*)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(value);
    if (match == null) return _SqlTableReference(value, '');
    final table = match.group(1)!.trim();
    final alias = match.group(2)!.trim();
    if (table.isEmpty || table.endsWith('.')) {
      return _SqlTableReference(value, '');
    }
    return _SqlTableReference(table, alias);
  }

  Map<String, dynamic> _predicateInputs(String predicate) {
    final parsed = _parsePredicate(predicate);
    if (parsed == null) {
      return <String, dynamic>{
        'predicate': predicate,
        'imported_raw_predicate': true,
      };
    }
    return <String, dynamic>{
      'predicate': predicate,
      'negation': parsed.negation,
      'column': parsed.column,
      'operator': parsed.operator,
      'value': parsed.value,
    };
  }

  Map<String, dynamic> _whereInputs(String predicate) {
    final parsed = _parsePredicate(predicate);
    if (parsed == null) {
      return <String, dynamic>{
        'predicate': predicate,
        'imported_raw_where': true,
      };
    }
    return <String, dynamic>{
      'predicate': predicate,
      'negation': parsed.negation,
      'where_column': parsed.column,
      'operator': parsed.operator,
      'where_value': parsed.value,
    };
  }

  _SqlPredicate? _parsePredicate(String source) {
    final original = source.trim();
    if (original.isEmpty || _hasCompoundPredicate(original)) return null;

    var value = original;
    var negation = '';
    if (value.toUpperCase().startsWith('NOT ')) {
      negation = 'NOT';
      value = _withoutOuterParentheses(value.substring(4).trim());
    }

    final match = RegExp(
      r'^(.*?)\s*(IS\s+NOT\s+NULL|IS\s+NULL|NOT\s+BETWEEN|BETWEEN|NOT\s+IN|IN|NOT\s+LIKE|LIKE|GLOB|MATCH|REGEXP|IS\s+NOT|IS|>=|<=|<>|!=|=|>|<)\s*(.*?)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(value);
    if (match == null) return null;
    final column = match.group(1)!.trim();
    final operator = match
        .group(2)!
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
    final operand = match.group(3)!.trim();
    if (column.isEmpty ||
        (operand.isEmpty &&
            operator != 'IS NULL' &&
            operator != 'IS NOT NULL')) {
      return null;
    }
    return _SqlPredicate(
      negation: negation,
      column: column,
      operator: operator,
      value: operand,
    );
  }

  bool _hasCompoundPredicate(String value) {
    final upper = value.toUpperCase();
    if (upper.contains(' OR ') || upper.contains(' CASE ')) return true;
    if (!upper.contains(' AND ') || upper.contains(' BETWEEN ')) return false;
    return true;
  }

  Map<String, dynamic> _joinConditionInputs(String condition) {
    final parsed = _parsePredicate(condition);
    if (parsed == null || parsed.negation.isNotEmpty) {
      return const <String, dynamic>{'imported_raw_on': true};
    }
    return <String, dynamic>{
      'left_column': parsed.column,
      'operator': parsed.operator,
      'right_column': parsed.value,
    };
  }

  Map<String, dynamic> _havingInputs(String predicate) {
    final match = RegExp(
      r'^(COUNT|SUM|AVG|MIN|MAX)\s*\(\s*(.*?)\s*\)\s*(>=|<=|<>|!=|=|>|<|NOT\s+LIKE|LIKE|IS\s+NOT|IS)\s*(.*?)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(predicate.trim());
    if (match == null || match.group(4)!.trim().isEmpty) {
      return <String, dynamic>{
        'predicate': predicate,
        'imported_raw_having': true,
      };
    }
    return <String, dynamic>{
      'predicate': predicate,
      'aggregate': match.group(1)!.toUpperCase(),
      'column': match.group(2)!.trim(),
      'operator': match.group(3)!.replaceAll(RegExp(r'\s+'), ' ').toUpperCase(),
      'value': match.group(4)!.trim(),
    };
  }

  Map<String, dynamic> _orderByInputs(String expression) {
    final value = expression.trim();
    if (_hasTopLevelComma(value)) {
      return <String, dynamic>{'expr': value, 'imported_raw_order': true};
    }
    final match = RegExp(
      r'^(.*?)\s+(ASC|DESC)$',
      caseSensitive: false,
    ).firstMatch(value);
    final column = (match?.group(1) ?? value).trim();
    final order = (match?.group(2) ?? 'ASC').toUpperCase();
    if (column.isEmpty || column.toUpperCase().contains(' COLLATE ')) {
      return <String, dynamic>{'expr': value, 'imported_raw_order': true};
    }
    return <String, dynamic>{
      'column': column,
      'order': order,
      'expr': '$column $order',
    };
  }

  bool _hasTopLevelComma(String source) {
    var depth = 0;
    var quote = '';
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      final next = index + 1 < source.length ? source[index + 1] : '';
      if (quote.isNotEmpty) {
        if (char == quote && next == quote) {
          index++;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == "'" || char == '"' || char == '`') {
        quote = char;
      } else if (char == '(') {
        depth++;
      } else if (char == ')' && depth > 0) {
        depth--;
      } else if (char == ',' && depth == 0) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _alterInputs(String alter) {
    final add = RegExp(
      r'^ADD\s+(?:COLUMN\s+)?(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(alter);
    if (add != null) {
      return <String, dynamic>{
        'alter_action': 'ADD COLUMN',
        'alter_value': add.group(1)!.trim(),
      };
    }
    final drop = RegExp(
      r'^DROP\s+COLUMN\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(alter);
    if (drop != null) {
      return <String, dynamic>{
        'alter_action': 'DROP COLUMN',
        'alter_value': drop.group(1)!.trim(),
      };
    }
    final renameColumn = RegExp(
      r'^RENAME\s+COLUMN\s+(.+?)\s+TO\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(alter);
    if (renameColumn != null) {
      return <String, dynamic>{
        'alter_action': 'RENAME COLUMN',
        'alter_value':
            '${renameColumn.group(1)!.trim()} TO ${renameColumn.group(2)!.trim()}',
      };
    }
    final renameTable = RegExp(
      r'^RENAME\s+TO\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(alter);
    if (renameTable != null) {
      return <String, dynamic>{
        'alter_action': 'RENAME TO',
        'alter_value': renameTable.group(1)!.trim(),
      };
    }
    return const <String, dynamic>{'imported_raw_alter': true};
  }

  String _withoutOuterParentheses(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  BlockNode? _limitNode(String value, List<String> warnings) {
    final match = RegExp(
      r'^(\d+)(?:\s+OFFSET\s+(\d+))?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      warnings.add(
        'Only numeric LIMIT / OFFSET values can be converted to nodes.',
      );
      return null;
    }
    return _clause(BlockType.sqlLimit, <String, dynamic>{
      'count': match.group(1)!,
      'offset': match.group(2) ?? '',
    });
  }

  String _transactionBehavior(String upper) {
    for (final behavior in const <String>[
      'IMMEDIATE',
      'EXCLUSIVE',
      'DEFERRED',
    ]) {
      if (upper.contains(behavior)) return behavior;
    }
    return 'DEFERRED';
  }

  EventBlock _eventRoot(Offset position) =>
      EventBlock(id: _id('event'), position: position);

  BlockNode _node(BlockType type, [Map<String, dynamic>? inputs]) =>
      OperatorBlock(
        id: _id(type.name),
        position: Offset.zero,
        operatorType: type,
        inputs: inputs,
      );

  BlockNode _clause(BlockType type, Map<String, dynamic> inputs) => MotionBlock(
    id: _id(type.name),
    position: Offset.zero,
    motionType: type,
    inputs: inputs,
  );

  String _id(String prefix) => '${prefix}_${_nextId++}';

  List<_SqlClause> _topLevelClauses(String source, List<String> keywords) {
    final clauses = <_SqlClause>[];
    var cursor = 0;
    while (cursor < source.length) {
      final next = _firstTopLevelKeyword(source, keywords, start: cursor);
      if (next == null) break;
      clauses.add(next);
      cursor = next.index + next.keyword.length;
    }
    return clauses;
  }

  int _nextClauseEnd(
    List<_SqlClause> clauses,
    _SqlClause current,
    int defaultEnd,
    int offset,
  ) {
    final index = clauses.indexOf(current);
    return index + 1 < clauses.length
        ? offset + clauses[index + 1].index
        : defaultEnd;
  }

  _SqlClause? _firstTopLevelKeyword(
    String source,
    List<String> keywords, {
    int start = 0,
  }) {
    final upper = source.toUpperCase();
    var depth = 0;
    var quote = '';
    for (var index = start; index < source.length; index++) {
      final char = source[index];
      final next = index + 1 < source.length ? source[index + 1] : '';
      if (quote.isNotEmpty) {
        if (char == quote && next == quote) {
          index++;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == "'" || char == '"' || char == '`') {
        quote = char;
      } else if (char == '(') {
        depth++;
      } else if (char == ')' && depth > 0) {
        depth--;
      } else if (depth == 0) {
        for (final keyword in keywords) {
          if (!upper.startsWith(keyword, index)) continue;
          final before = index == 0 ? '' : upper[index - 1];
          final afterIndex = index + keyword.length;
          final after = afterIndex >= upper.length ? '' : upper[afterIndex];
          if (_isWordChar(before) || _isWordChar(after)) continue;
          return _SqlClause(index, keyword);
        }
      }
    }
    return null;
  }

  bool _isWordChar(String value) =>
      value.isNotEmpty && RegExp(r'[A-Z0-9_]').hasMatch(value);

  List<String> _splitStatements(String source) {
    final statements = <String>[];
    var start = 0;
    var depth = 0;
    var quote = '';
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      final next = index + 1 < source.length ? source[index + 1] : '';
      if (quote.isNotEmpty) {
        if (char == quote && next == quote) {
          index++;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == "'" || char == '"' || char == '`') {
        quote = char;
      } else if (char == '(') {
        depth++;
      } else if (char == ')' && depth > 0) {
        depth--;
      } else if (char == ';' && depth == 0) {
        final statement = source.substring(start, index).trim();
        if (statement.isNotEmpty) statements.add(statement);
        start = index + 1;
      }
    }
    final trailing = source.substring(start).trim();
    if (trailing.isNotEmpty) statements.add(trailing);
    return statements;
  }

  String _summary(String sql) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 72
        ? normalized
        : '${normalized.substring(0, 69)}...';
  }
}

class SqlToNodesImportResult {
  const SqlToNodesImportResult({required this.roots, required this.warnings});

  final List<BlockNode> roots;
  final List<String> warnings;

  bool get hasNodes => roots.isNotEmpty;
  int get importedStatementCount => roots.length;
}

class _SqlClause {
  const _SqlClause(this.index, this.keyword);

  final int index;
  final String keyword;
}

class _SqlTableReference {
  const _SqlTableReference(this.table, this.alias);

  final String table;
  final String alias;
}

class _SqlPredicate {
  const _SqlPredicate({
    required this.negation,
    required this.column,
    required this.operator,
    required this.value,
  });

  final String negation;
  final String column;
  final String operator;
  final String value;
}
