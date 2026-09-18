import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';

enum SqlNodeErrorKind {
  missingTable,
  missingColumn,
  ambiguousColumn,
  missingSchemaObject,
  schemaObjectAlreadyExists,
  syntax,
  constraint,
  aggregate,
  datatype,
  readonly,
  locked,
  unknown,
}

/// The result of projecting a SQLite error back onto the visual program.
class SqlNodeErrorProjection {
  const SqlNodeErrorProjection({
    required this.nodeId,
    required this.kind,
    required this.sqliteError,
    this.sourceSpan,
  });

  final String nodeId;
  final SqlNodeErrorKind kind;
  final String sqliteError;
  final SqlNodeSourceSpan? sourceSpan;
}

/// Reverses the relevant part of compilation for diagnostics.
///
/// SQLite usually reports a token or schema identifier, but no source offset.
/// This resolver combines that information with the compiler source map and
/// the structured node inputs to select the most likely originating node.
class SqlBackwardsCompiler {
  const SqlBackwardsCompiler();

  SqlNodeErrorProjection? project({
    required SqlCompileResult compilation,
    required String sqliteError,
  }) {
    final error = sqliteError.trim();
    if (error.isEmpty || compilation.sourceMap.isEmpty) return null;
    final lower = error.toLowerCase();
    if (_isConnectionError(lower)) return null;

    final nodes = _flatten(compilation.program.roots);
    final nodeById = <String, BlockNode>{
      for (final node in nodes) node.id: node,
    };

    final tableMatch = RegExp(
      r'no such table:\s*([^\s,)]+)',
      caseSensitive: false,
    ).firstMatch(error);
    if (tableMatch != null) {
      return _forIdentifier(
        compilation: compilation,
        error: error,
        nodeById: nodeById,
        identifier: tableMatch.group(1)!,
        kind: SqlNodeErrorKind.missingTable,
        preferredTypes: _tableNodeTypes,
        preferredInputKeys: const <String>['table', 'table_name'],
      );
    }

    final columnMatch = RegExp(
      r'(?:no such column|ambiguous column name):\s*([^\s,)]+)',
      caseSensitive: false,
    ).firstMatch(error);
    if (columnMatch != null) {
      return _forIdentifier(
        compilation: compilation,
        error: error,
        nodeById: nodeById,
        identifier: columnMatch.group(1)!,
        kind: lower.contains('ambiguous column')
            ? SqlNodeErrorKind.ambiguousColumn
            : SqlNodeErrorKind.missingColumn,
        preferredTypes: _columnNodeTypes,
        preferredInputKeys: const <String>[
          'column',
          'columns',
          'left_column',
          'right_column',
          'expr',
          'predicate',
          'assignments',
        ],
      );
    }

    final missingObjectMatch = RegExp(
      r'no such (index|view|trigger):\s*([^\s,)]+)',
      caseSensitive: false,
    ).firstMatch(error);
    if (missingObjectMatch != null) {
      return _forIdentifier(
        compilation: compilation,
        error: error,
        nodeById: nodeById,
        identifier: missingObjectMatch.group(2)!,
        kind: SqlNodeErrorKind.missingSchemaObject,
        preferredTypes: _schemaObjectNodeTypes,
        preferredInputKeys: const <String>['name', 'target'],
      );
    }

    final existingObjectMatch = RegExp(
      r'(?:table|index|view|trigger)\s+([^\s,)]+)\s+already exists',
      caseSensitive: false,
    ).firstMatch(error);
    if (existingObjectMatch != null) {
      return _forIdentifier(
        compilation: compilation,
        error: error,
        nodeById: nodeById,
        identifier: existingObjectMatch.group(1)!,
        kind: SqlNodeErrorKind.schemaObjectAlreadyExists,
        preferredTypes: _schemaObjectNodeTypes,
        preferredInputKeys: const <String>['table', 'name'],
      );
    }

    final nearMatch = RegExp(
      r'''near\s+["'`]([^"'`]+)["'`]''',
      caseSensitive: false,
    ).firstMatch(error);
    if (nearMatch != null) {
      final span = _spanForToken(
        compilation,
        nearMatch.group(1)!,
        nodeById: nodeById,
      );
      if (span != null) {
        return SqlNodeErrorProjection(
          nodeId: span.nodeId,
          kind: SqlNodeErrorKind.syntax,
          sqliteError: error,
          sourceSpan: span,
        );
      }
    }

    if (lower.contains('constraint failed') || lower.contains('constraint')) {
      final failedIdentifier = RegExp(
        r'constraint failed:\s*([^\s,)]+)',
        caseSensitive: false,
      ).firstMatch(error)?.group(1);
      final span = _bestDmlSpan(
        compilation,
        nodeById: nodeById,
        identifier: failedIdentifier,
      );
      return _fromSpan(span, SqlNodeErrorKind.constraint, error);
    }

    if (lower.contains('misuse of aggregate') ||
        lower.contains('aggregate functions are not allowed')) {
      final span = _bestSpan(
        compilation,
        nodeById: nodeById,
        preferredTypes: _aggregateNodeTypes,
        textPattern: RegExp(
          r'\b(COUNT|SUM|AVG|MIN|MAX)\s*\(',
          caseSensitive: false,
        ),
      );
      return _fromSpan(span, SqlNodeErrorKind.aggregate, error);
    }

    if (lower.contains('incomplete input')) {
      return _fromSpan(
        _lastSpan(compilation.sourceMap),
        SqlNodeErrorKind.syntax,
        error,
      );
    }
    if (lower.contains('syntax error')) {
      final span = _bestSpan(
        compilation,
        nodeById: nodeById,
        preferredTypes: _syntaxNodeTypes,
      );
      return _fromSpan(span, SqlNodeErrorKind.syntax, error);
    }
    if (lower.contains('datatype mismatch')) {
      return _fromSpan(
        _bestDmlSpan(compilation, nodeById: nodeById),
        SqlNodeErrorKind.datatype,
        error,
      );
    }
    if (lower.contains('readonly') || lower.contains('read-only')) {
      return _fromSpan(
        _bestDmlSpan(compilation, nodeById: nodeById),
        SqlNodeErrorKind.readonly,
        error,
      );
    }
    if (lower.contains('database is locked')) {
      return _fromSpan(
        _lastSpan(compilation.sourceMap),
        SqlNodeErrorKind.locked,
        error,
      );
    }

    return _fromSpan(
      _lastSpan(compilation.sourceMap),
      SqlNodeErrorKind.unknown,
      error,
    );
  }

  SqlNodeErrorProjection? _forIdentifier({
    required SqlCompileResult compilation,
    required String error,
    required Map<String, BlockNode> nodeById,
    required String identifier,
    required SqlNodeErrorKind kind,
    required Set<BlockType> preferredTypes,
    required List<String> preferredInputKeys,
  }) {
    final complete = _normalizeIdentifier(identifier, keepQualifier: true);
    final leaf = _normalizeIdentifier(identifier);
    SqlNodeSourceSpan? bestSpan;
    var bestScore = -1;

    for (final span in compilation.sourceMap) {
      final node = nodeById[span.nodeId];
      if (node == null) continue;
      var score = preferredTypes.contains(node.type) ? 20 : 0;
      final spanText = span.textIn(compilation.sql);
      if (_containsIdentifier(spanText, complete)) score += 35;
      if (complete != leaf && _containsIdentifier(spanText, leaf)) score += 10;
      for (final key in preferredInputKeys) {
        final input = node.inputs[key];
        if (input != null &&
            _inputContainsIdentifier('$input', complete, leaf)) {
          score += 80;
          break;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestSpan = span;
      }
    }

    // Reporter nodes can be nested inside a fragment owned by their parent.
    // Prefer an exact reporter input match when it is more specific.
    for (final node in nodeById.values) {
      if (!preferredTypes.contains(node.type)) continue;
      if (!preferredInputKeys.any((key) {
        final input = node.inputs[key];
        return input != null &&
            _inputContainsIdentifier('$input', complete, leaf);
      })) {
        continue;
      }
      SqlNodeSourceSpan? mappedSpan;
      for (final span in compilation.sourceMap) {
        if (span.nodeId == node.id) {
          mappedSpan = span;
          break;
        }
      }
      if (mappedSpan != null) continue;
      return SqlNodeErrorProjection(
        nodeId: node.id,
        kind: kind,
        sqliteError: error,
        sourceSpan: mappedSpan,
      );
    }

    return _fromSpan(bestSpan, kind, error);
  }

  SqlNodeSourceSpan? _spanForToken(
    SqlCompileResult compilation,
    String token, {
    required Map<String, BlockNode> nodeById,
  }) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return null;
    final matches = RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(normalizedToken)}(?![A-Za-z0-9_])',
      caseSensitive: false,
    ).allMatches(compilation.sql);
    for (final match in matches) {
      final containing = compilation.sourceMap
          .where((span) => span.contains(match.start))
          .toList(growable: false);
      if (containing.isEmpty) continue;
      containing.sort((a, b) {
        final aPreferred = _syntaxNodeTypes.contains(nodeById[a.nodeId]?.type);
        final bPreferred = _syntaxNodeTypes.contains(nodeById[b.nodeId]?.type);
        if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
        return (a.end - a.start).compareTo(b.end - b.start);
      });
      return containing.first;
    }
    return null;
  }

  SqlNodeSourceSpan? _bestDmlSpan(
    SqlCompileResult compilation, {
    required Map<String, BlockNode> nodeById,
    String? identifier,
  }) {
    final target = identifier == null
        ? ''
        : _normalizeIdentifier(identifier, keepQualifier: true);
    final parts = target.split('.');
    final table = parts.length > 1 ? parts.first : '';
    final column = parts.length > 1 ? parts.last : target;
    SqlNodeSourceSpan? best;
    var bestScore = -1;
    for (final span in compilation.sourceMap) {
      final node = nodeById[span.nodeId];
      if (node == null || !_dmlNodeTypes.contains(node.type)) continue;
      var score = 50 + span.statementIndex;
      if (table.isNotEmpty &&
          _normalizeIdentifier('${node.inputs['table'] ?? ''}') == table) {
        score += 100;
      }
      if (column.isNotEmpty &&
          <String>['columns', 'column', 'assignments'].any((key) {
            final value = node.inputs[key];
            return value != null &&
                _inputContainsIdentifier('$value', column, column);
          })) {
        score += 40;
      }
      final source = span.textIn(compilation.sql);
      if (table.isNotEmpty && _containsIdentifier(source, table)) score += 20;
      if (column.isNotEmpty && _containsIdentifier(source, column)) score += 10;
      if (score >= bestScore) {
        bestScore = score;
        best = span;
      }
    }
    return best;
  }

  SqlNodeSourceSpan? _bestSpan(
    SqlCompileResult compilation, {
    required Map<String, BlockNode> nodeById,
    required Set<BlockType> preferredTypes,
    RegExp? textPattern,
    bool preferLast = false,
  }) {
    SqlNodeSourceSpan? best;
    var bestScore = -1;
    for (final span in compilation.sourceMap) {
      final node = nodeById[span.nodeId];
      if (node == null) continue;
      var score = preferredTypes.contains(node.type) ? 50 : 0;
      if (textPattern?.hasMatch(span.textIn(compilation.sql)) ?? false) {
        score += 30;
      }
      if (preferLast) score += span.statementIndex;
      if (score > bestScore || (preferLast && score == bestScore)) {
        bestScore = score;
        best = span;
      }
    }
    return best;
  }

  SqlNodeErrorProjection? _fromSpan(
    SqlNodeSourceSpan? span,
    SqlNodeErrorKind kind,
    String error,
  ) {
    if (span == null) return null;
    return SqlNodeErrorProjection(
      nodeId: span.nodeId,
      kind: kind,
      sqliteError: error,
      sourceSpan: span,
    );
  }

  List<BlockNode> _flatten(List<BlockNode> roots) {
    final result = <BlockNode>[];
    final seen = <String>{};
    void visit(BlockNode node) {
      if (!seen.add(node.id)) return;
      result.add(node);
      for (final child in node.children) {
        visit(child);
      }
      final next = node.next;
      if (next != null) visit(next);
    }

    for (final root in roots) {
      visit(root);
    }
    return result;
  }

  SqlNodeSourceSpan? _lastSpan(List<SqlNodeSourceSpan> spans) {
    if (spans.isEmpty) return null;
    return spans.reduce((a, b) => a.end >= b.end ? a : b);
  }

  bool _isConnectionError(String lower) {
    return lower.contains('no database connected') ||
        lower.contains('database file not found') ||
        lower.contains('failed to open database');
  }

  String _normalizeIdentifier(String raw, {bool keepQualifier = false}) {
    var result = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll('`', '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll(RegExp(r'[:;]+$'), '');
    if (!keepQualifier && result.contains('.')) result = result.split('.').last;
    return result.toLowerCase();
  }

  bool _containsIdentifier(String source, String identifier) {
    if (identifier.isEmpty) return false;
    return RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(identifier)}(?![A-Za-z0-9_])',
      caseSensitive: false,
    ).hasMatch(source);
  }

  bool _inputContainsIdentifier(String input, String complete, String leaf) {
    final normalized = input.toLowerCase();
    return _containsIdentifier(normalized, complete) ||
        _containsIdentifier(normalized, leaf);
  }
}

const Set<BlockType> _tableNodeTypes = <BlockType>{
  BlockType.sqlSelect,
  BlockType.sqlFrom,
  BlockType.sqlJoin,
  BlockType.sqlInnerJoin,
  BlockType.sqlLeftJoin,
  BlockType.sqlRightJoin,
  BlockType.sqlFullJoin,
  BlockType.sqlCrossJoin,
  BlockType.sqlSelfJoin,
  BlockType.sqlNaturalJoin,
  BlockType.sqlInsert,
  BlockType.sqlInsertOrReplace,
  BlockType.sqlUpsert,
  BlockType.sqlUpdate,
  BlockType.sqlDelete,
  BlockType.sqlCreateTable,
  BlockType.sqlCreateIndex,
  BlockType.sqlCreateView,
  BlockType.sqlCreateTrigger,
  BlockType.sqlCreateVirtualTable,
  BlockType.sqlAlterTable,
  BlockType.sqlDropTable,
};

const Set<BlockType> _columnNodeTypes = <BlockType>{
  BlockType.sqlColumn,
  BlockType.sqlSelect,
  BlockType.sqlWhere,
  BlockType.sqlAnd,
  BlockType.sqlOr,
  BlockType.sqlJoin,
  BlockType.sqlInnerJoin,
  BlockType.sqlLeftJoin,
  BlockType.sqlRightJoin,
  BlockType.sqlFullJoin,
  BlockType.sqlGroupBy,
  BlockType.sqlHaving,
  BlockType.sqlOrderBy,
  BlockType.sqlInsert,
  BlockType.sqlInsertOrReplace,
  BlockType.sqlUpsert,
  BlockType.sqlUpdate,
  BlockType.sqlCreateIndex,
};

const Set<BlockType> _dmlNodeTypes = <BlockType>{
  BlockType.sqlInsert,
  BlockType.sqlInsertOrReplace,
  BlockType.sqlUpsert,
  BlockType.sqlUpdate,
  BlockType.sqlDelete,
};

const Set<BlockType> _schemaObjectNodeTypes = <BlockType>{
  BlockType.sqlCreateTable,
  BlockType.sqlDropTable,
  BlockType.sqlAlterTable,
  BlockType.sqlCreateIndex,
  BlockType.sqlDropIndex,
  BlockType.sqlCreateView,
  BlockType.sqlDropView,
  BlockType.sqlCreateTrigger,
  BlockType.sqlDropTrigger,
  BlockType.sqlCreateVirtualTable,
  BlockType.sqlReindex,
  BlockType.sqlAnalyze,
};

const Set<BlockType> _aggregateNodeTypes = <BlockType>{
  BlockType.sqlCount,
  BlockType.sqlSum,
  BlockType.sqlAvg,
  BlockType.sqlMin,
  BlockType.sqlMax,
  BlockType.sqlSelect,
  BlockType.sqlHaving,
};

const Set<BlockType> _syntaxNodeTypes = <BlockType>{
  BlockType.sqlWhere,
  BlockType.sqlAnd,
  BlockType.sqlOr,
  BlockType.sqlJoin,
  BlockType.sqlInnerJoin,
  BlockType.sqlLeftJoin,
  BlockType.sqlRightJoin,
  BlockType.sqlFullJoin,
  BlockType.sqlGroupBy,
  BlockType.sqlHaving,
  BlockType.sqlOrderBy,
  BlockType.sqlLimit,
  BlockType.sqlUnion,
  BlockType.sqlIntersect,
  BlockType.sqlExcept,
  BlockType.sqlInsert,
  BlockType.sqlInsertOrReplace,
  BlockType.sqlUpsert,
  BlockType.sqlUpdate,
  BlockType.sqlDelete,
  BlockType.sqlCreateTable,
  BlockType.sqlCreateIndex,
  BlockType.sqlDropIndex,
  BlockType.sqlCreateView,
  BlockType.sqlDropView,
  BlockType.sqlCreateTrigger,
  BlockType.sqlDropTrigger,
  BlockType.sqlCreateVirtualTable,
  BlockType.sqlAlterTable,
  BlockType.sqlDropTable,
  BlockType.sqlPragma,
  BlockType.sqlAttachDatabase,
  BlockType.sqlDetachDatabase,
  BlockType.sqlExplain,
  BlockType.sqlWith,
  BlockType.sqlValues,
};
