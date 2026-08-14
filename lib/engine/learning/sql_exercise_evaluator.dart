import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

enum SqlExerciseVerdict {
  correct,
  incorrect,
  invalidSubmission,
  invalidSolution,
  databaseUnavailable,
}

class SqlExerciseResult {
  const SqlExerciseResult({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<Object?>> rows;
}

class SqlExerciseEvaluation {
  const SqlExerciseEvaluation({
    required this.verdict,
    required this.message,
    this.submission,
    this.solution,
    this.missingRowCount = 0,
    this.unexpectedRowCount = 0,
  });

  final SqlExerciseVerdict verdict;
  final String message;
  final SqlExerciseResult? submission;
  final SqlExerciseResult? solution;
  final int missingRowCount;
  final int unexpectedRowCount;

  bool get isCorrect => verdict == SqlExerciseVerdict.correct;
}

/// Compares a learner query with a reference query against the same database.
///
/// Both queries run on independent read-only connections. This makes exercise
/// checking safe for project data and ensures that one query cannot influence
/// the other. Unordered comparisons are multiset comparisons, so duplicate
/// rows still matter.
class SqlExerciseEvaluator {
  const SqlExerciseEvaluator({this.maximumRows = 10000});

  final int maximumRows;

  Future<SqlExerciseEvaluation> evaluate({
    required String databasePath,
    required String submissionSql,
    required String solutionSql,
    bool orderSensitive = false,
    bool compareColumnNames = false,
  }) {
    return Isolate.run(
      () => _evaluateOnWorker(
        databasePath: databasePath,
        submissionSql: submissionSql,
        solutionSql: solutionSql,
        orderSensitive: orderSensitive,
        compareColumnNames: compareColumnNames,
        maximumRows: maximumRows,
      ),
    );
  }

  static SqlExerciseEvaluation _evaluateOnWorker({
    required String databasePath,
    required String submissionSql,
    required String solutionSql,
    required bool orderSensitive,
    required bool compareColumnNames,
    required int maximumRows,
  }) {
    if (submissionSql.trim().isEmpty) {
      return const SqlExerciseEvaluation(
        verdict: SqlExerciseVerdict.invalidSubmission,
        message: 'The submitted query is empty.',
      );
    }
    if (solutionSql.trim().isEmpty) {
      return const SqlExerciseEvaluation(
        verdict: SqlExerciseVerdict.invalidSolution,
        message: 'The reference query is empty.',
      );
    }

    late final SqlExerciseResult solution;
    try {
      solution = _executeReadOnly(databasePath, solutionSql, maximumRows);
    } on Object catch (error) {
      return SqlExerciseEvaluation(
        verdict: SqlExerciseVerdict.invalidSolution,
        message: 'The reference query could not be evaluated: $error',
      );
    }

    late final SqlExerciseResult submission;
    try {
      submission = _executeReadOnly(databasePath, submissionSql, maximumRows);
    } on Object catch (error) {
      return SqlExerciseEvaluation(
        verdict: SqlExerciseVerdict.invalidSubmission,
        message: 'The submitted query could not be evaluated: $error',
        solution: solution,
      );
    }

    if (compareColumnNames &&
        !_listEquals(submission.columns, solution.columns)) {
      return SqlExerciseEvaluation(
        verdict: SqlExerciseVerdict.incorrect,
        message: 'The result columns do not match the expected columns.',
        submission: submission,
        solution: solution,
      );
    }

    final difference = orderSensitive
        ? _orderedDifference(submission.rows, solution.rows)
        : _unorderedDifference(submission.rows, solution.rows);
    if (difference.missing == 0 && difference.unexpected == 0) {
      return SqlExerciseEvaluation(
        verdict: SqlExerciseVerdict.correct,
        message: 'Correct result.',
        submission: submission,
        solution: solution,
      );
    }

    return SqlExerciseEvaluation(
      verdict: SqlExerciseVerdict.incorrect,
      message: orderSensitive
          ? 'The rows or their order do not match the expected result.'
          : 'The returned rows do not match the expected result.',
      submission: submission,
      solution: solution,
      missingRowCount: difference.missing,
      unexpectedRowCount: difference.unexpected,
    );
  }

  static SqlExerciseResult _executeReadOnly(
    String path,
    String sql,
    int maximumRows,
  ) {
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    List<PreparedStatement>? statements;
    try {
      statements = database.prepareMultiple(sql);
      if (statements.length != 1) {
        throw const FormatException(
          'Exercises require exactly one SQL statement.',
        );
      }
      final result = statements.single.select();
      if (result.columnNames.isEmpty) {
        throw const FormatException('The statement does not return rows.');
      }
      if (result.length > maximumRows) {
        throw StateError(
          'The result exceeds the exercise limit of $maximumRows rows.',
        );
      }
      return SqlExerciseResult(
        columns: List<String>.unmodifiable(result.columnNames),
        rows: List<List<Object?>>.unmodifiable(
          result.rows.map((row) => List<Object?>.unmodifiable(row)),
        ),
      );
    } finally {
      if (statements != null) {
        for (final statement in statements) {
          statement.close();
        }
      }
      database.close();
    }
  }

  static _RowDifference _orderedDifference(
    List<List<Object?>> actual,
    List<List<Object?>> expected,
  ) {
    final sharedLength = actual.length < expected.length
        ? actual.length
        : expected.length;
    var mismatches = 0;
    for (var index = 0; index < sharedLength; index++) {
      if (_rowKey(actual[index]) != _rowKey(expected[index])) mismatches++;
    }
    return _RowDifference(
      missing: mismatches + (expected.length - sharedLength),
      unexpected: mismatches + (actual.length - sharedLength),
    );
  }

  static _RowDifference _unorderedDifference(
    List<List<Object?>> actual,
    List<List<Object?>> expected,
  ) {
    final counts = <String, int>{};
    for (final row in expected) {
      final key = _rowKey(row);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    var unexpected = 0;
    for (final row in actual) {
      final key = _rowKey(row);
      final remaining = counts[key] ?? 0;
      if (remaining == 0) {
        unexpected++;
      } else if (remaining == 1) {
        counts.remove(key);
      } else {
        counts[key] = remaining - 1;
      }
    }
    return _RowDifference(
      missing: counts.values.fold(0, (sum, count) => sum + count),
      unexpected: unexpected,
    );
  }

  static String _rowKey(List<Object?> row) {
    return jsonEncode(row.map(_normalizedValue).toList(growable: false));
  }

  static Object _normalizedValue(Object? value) {
    if (value == null) return const <Object>['null'];
    if (value is int) return <Object>['number', value.toString()];
    if (value is double) {
      final normalized = value == 0
          ? '0'
          : (value.isFinite && value == value.truncateToDouble()
                ? value.toInt().toString()
                : value.toString());
      return <Object>['number', normalized];
    }
    if (value is Uint8List) return <Object>['blob', base64Encode(value)];
    return <Object>['text', value.toString()];
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

class _RowDifference {
  const _RowDifference({required this.missing, required this.unexpected});

  final int missing;
  final int unexpected;
}
