import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';

enum SqlCompletionKind { keyword, snippet, table, column }

class SqlCompletion {
  const SqlCompletion({
    required this.label,
    required this.insertText,
    required this.detail,
    required this.kind,
    required this.score,
  });

  final String label;
  final String insertText;
  final String detail;
  final SqlCompletionKind kind;
  final int score;
}

/// Local adaptive completion for SQLite. Ranking combines the current clause,
/// prefix similarity, database schema and previously accepted suggestions.
/// Query text never leaves the device.
class SqlCompletionEngine {
  const SqlCompletionEngine();

  List<SqlCompletion> suggest({
    required String sql,
    required int cursorOffset,
    required List<TableSchema> schemas,
    Map<String, int> acceptedSelections = const <String, int>{},
    bool explicitlyRequested = false,
  }) {
    final offset = cursorOffset.clamp(0, sql.length);
    final before = sql.substring(0, offset);
    final range = tokenAt(sql, offset);
    final prefix = sql.substring(range.start, offset);
    if (prefix.isEmpty && !explicitlyRequested && !_expectsValue(before)) {
      return const <SqlCompletion>[];
    }

    final candidates = <SqlCompletion>[];
    final dot = prefix.lastIndexOf('.');
    if (dot >= 0) {
      final qualifier = prefix.substring(0, dot);
      final schema = _schemaForQualifier(qualifier, before, schemas);
      if (schema != null) {
        for (final column in schema.columns) {
          _add(
            candidates,
            label: '$qualifier.$column',
            insertText: '$qualifier.$column',
            detail: 'column · ${schema.name}',
            kind: SqlCompletionKind.column,
            prefix: prefix,
            contextBonus: 90,
            accepted: acceptedSelections,
          );
        }
      }
    } else {
      final wantsTable = _expectsTable(before);
      final wantsColumn = _expectsColumn(before);
      if (wantsTable || explicitlyRequested) {
        for (final schema in schemas) {
          _add(
            candidates,
            label: schema.name,
            insertText: schema.name,
            detail: 'table',
            kind: SqlCompletionKind.table,
            prefix: prefix,
            contextBonus: wantsTable ? 110 : 20,
            accepted: acceptedSelections,
          );
        }
      }
      if (wantsColumn || explicitlyRequested) {
        for (final schema in schemas) {
          for (final column in schema.columns) {
            _add(
              candidates,
              label: column,
              insertText: column,
              detail: 'column · ${schema.name}',
              kind: SqlCompletionKind.column,
              prefix: prefix,
              contextBonus: wantsColumn ? 75 : 10,
              accepted: acceptedSelections,
            );
          }
        }
      }
      for (final template in _templates) {
        _add(
          candidates,
          label: template.label,
          insertText: template.insertText,
          detail: template.detail,
          kind: template.kind,
          prefix: prefix,
          contextBonus: _keywordBonus(template.label, before),
          accepted: acceptedSelections,
        );
      }
    }

    final unique = <String, SqlCompletion>{};
    for (final item in candidates) {
      final key = item.insertText.toLowerCase();
      if (unique[key] == null || unique[key]!.score < item.score) {
        unique[key] = item;
      }
    }
    final sorted = unique.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.label.compareTo(b.label) : score;
      });
    return sorted.take(8).toList(growable: false);
  }

  TextRange tokenAt(String sql, int cursorOffset) {
    final offset = cursorOffset.clamp(0, sql.length);
    var start = offset;
    while (start > 0 && RegExp(r'[A-Za-z0-9_.]').hasMatch(sql[start - 1])) {
      start--;
    }
    var end = offset;
    while (end < sql.length && RegExp(r'[A-Za-z0-9_.]').hasMatch(sql[end])) {
      end++;
    }
    return TextRange(start: start, end: end);
  }

  void _add(
    List<SqlCompletion> target, {
    required String label,
    required String insertText,
    required String detail,
    required SqlCompletionKind kind,
    required String prefix,
    required int contextBonus,
    required Map<String, int> accepted,
  }) {
    final prefixScore = _prefixScore(label, prefix);
    if (prefixScore < 0) return;
    final learned = math.min(accepted[insertText.toLowerCase()] ?? 0, 20) * 4;
    target.add(
      SqlCompletion(
        label: label,
        insertText: insertText,
        detail: detail,
        kind: kind,
        score: prefixScore + contextBonus + learned,
      ),
    );
  }

  int _prefixScore(String candidate, String prefix) {
    if (prefix.isEmpty) return 20;
    final value = candidate.toLowerCase();
    final search = prefix.toLowerCase();
    if (value == search) return 130;
    if (value.startsWith(search)) return 120;
    final position = value.indexOf(search);
    return position < 0 ? -1 : 70 - math.min(position, 20);
  }

  bool _expectsValue(String sql) => _expectsTable(sql) || _expectsColumn(sql);

  bool _expectsTable(String sql) => RegExp(
    r'\b(?:FROM|JOIN|INTO|UPDATE|TABLE|VIEW|ON)\s+[A-Za-z0-9_.]*$',
    caseSensitive: false,
  ).hasMatch(sql);

  bool _expectsColumn(String sql) => RegExp(
    r'\b(?:SELECT|WHERE|HAVING|SET|BY|ON)\s+(?:.*[,=(]\s*)?[A-Za-z0-9_]*$',
    caseSensitive: false,
    multiLine: true,
  ).hasMatch(sql);

  int _keywordBonus(String keyword, String sql) {
    final upper = sql.toUpperCase();
    if (upper.trim().isEmpty && keyword == 'SELECT') return 100;
    if (RegExp(r'\bSELECT\b[^;]*$').hasMatch(upper)) {
      if (keyword == 'FROM') return 65;
      if (keyword == 'WHERE' || keyword == 'ORDER BY') return 40;
    }
    if (RegExp(r'\bFROM\s+\S+[^;]*$').hasMatch(upper)) {
      if (keyword == 'JOIN' || keyword == 'WHERE') return 60;
      if (keyword == 'GROUP BY' || keyword == 'ORDER BY') return 45;
    }
    if (RegExp(r'\bINSERT\s+$').hasMatch(upper) && keyword == 'INTO') return 80;
    return 0;
  }

  TableSchema? _schemaForQualifier(
    String qualifier,
    String sql,
    List<TableSchema> schemas,
  ) {
    for (final schema in schemas) {
      if (schema.name.toLowerCase() == qualifier.toLowerCase()) return schema;
    }
    final aliases = RegExp(
      r'\b(?:FROM|JOIN|UPDATE|INTO)\s+([A-Za-z_][A-Za-z0-9_]*)'
      r'(?:\s+(?:AS\s+)?([A-Za-z_][A-Za-z0-9_]*))?',
      caseSensitive: false,
    );
    for (final match in aliases.allMatches(sql)) {
      if (match.group(2)?.toLowerCase() != qualifier.toLowerCase()) continue;
      final table = match.group(1)!.toLowerCase();
      for (final schema in schemas) {
        if (schema.name.toLowerCase() == table) return schema;
      }
    }
    return null;
  }
}

class _SqlTemplate {
  const _SqlTemplate(this.label, this.insertText, this.detail, this.kind);

  final String label;
  final String insertText;
  final String detail;
  final SqlCompletionKind kind;
}

const List<_SqlTemplate> _templates = <_SqlTemplate>[
  _SqlTemplate('SELECT', 'SELECT ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate(
    'SELECT … FROM',
    'SELECT *\nFROM ',
    'query snippet',
    SqlCompletionKind.snippet,
  ),
  _SqlTemplate('FROM', 'FROM ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('WHERE', 'WHERE ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('JOIN', 'JOIN ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('LEFT JOIN', 'LEFT JOIN ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('GROUP BY', 'GROUP BY ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('HAVING', 'HAVING ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('ORDER BY', 'ORDER BY ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate('LIMIT', 'LIMIT ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate(
    'INSERT INTO',
    'INSERT INTO ',
    'statement',
    SqlCompletionKind.snippet,
  ),
  _SqlTemplate('INTO', 'INTO ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate(
    'UPDATE … SET',
    'UPDATE \nSET ',
    'statement',
    SqlCompletionKind.snippet,
  ),
  _SqlTemplate(
    'DELETE FROM',
    'DELETE FROM ',
    'statement',
    SqlCompletionKind.snippet,
  ),
  _SqlTemplate(
    'CREATE TABLE',
    'CREATE TABLE ',
    'statement',
    SqlCompletionKind.snippet,
  ),
  _SqlTemplate('VALUES', 'VALUES ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate(
    'ON CONFLICT',
    'ON CONFLICT ',
    'keyword',
    SqlCompletionKind.keyword,
  ),
  _SqlTemplate('WITH', 'WITH ', 'keyword', SqlCompletionKind.keyword),
  _SqlTemplate(
    'EXPLAIN QUERY PLAN',
    'EXPLAIN QUERY PLAN ',
    'statement',
    SqlCompletionKind.snippet,
  ),
  _SqlTemplate('BEGIN', 'BEGIN;', 'snapshot', SqlCompletionKind.snippet),
  _SqlTemplate(
    'SAVEPOINT',
    'SAVEPOINT ',
    'snapshot',
    SqlCompletionKind.keyword,
  ),
  _SqlTemplate('COMMIT', 'COMMIT;', 'snapshot', SqlCompletionKind.snippet),
  _SqlTemplate('ROLLBACK', 'ROLLBACK;', 'snapshot', SqlCompletionKind.snippet),
  _SqlTemplate('AND', 'AND ', 'operator', SqlCompletionKind.keyword),
  _SqlTemplate('OR', 'OR ', 'operator', SqlCompletionKind.keyword),
  _SqlTemplate('NOT NULL', 'NOT NULL', 'constraint', SqlCompletionKind.keyword),
  _SqlTemplate('IS NULL', 'IS NULL', 'predicate', SqlCompletionKind.keyword),
  _SqlTemplate(
    'IS NOT NULL',
    'IS NOT NULL',
    'predicate',
    SqlCompletionKind.keyword,
  ),
];
