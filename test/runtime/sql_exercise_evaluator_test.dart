import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/learning/sql_exercise_evaluator.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tempDir;
  late String databasePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nodeql_exercise');
    databasePath = '${tempDir.path}${Platform.pathSeparator}exercise.sqlite3';
    final database = sqlite3.open(databasePath);
    database.execute('''
      CREATE TABLE executions (
        id INTEGER PRIMARY KEY,
        county TEXT NOT NULL,
        age INTEGER NOT NULL,
        last_statement TEXT
      );
      INSERT INTO executions (county, age, last_statement) VALUES
        ('Harris', 24, NULL),
        ('Bexar', 52, ''),
        ('Harris', 52, 'innocent'),
        ('Harris', 52, 'innocent');
    ''');
    database.close();
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('accepts equivalent SQLite results when order is irrelevant', () async {
    final result = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql:
          'SELECT county, COUNT(*) FROM executions GROUP BY county '
          'ORDER BY county DESC',
      solutionSql:
          'SELECT county, COUNT(*) FROM executions GROUP BY county '
          'ORDER BY county ASC',
    );

    expect(result.verdict, SqlExerciseVerdict.correct);
    expect(result.isCorrect, isTrue);
  });

  test('can require row order for ORDER BY exercises', () async {
    final result = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql: 'SELECT county FROM executions ORDER BY id DESC',
      solutionSql: 'SELECT county FROM executions ORDER BY id ASC',
      orderSensitive: true,
    );

    expect(result.verdict, SqlExerciseVerdict.incorrect);
    expect(result.missingRowCount, greaterThan(0));
    expect(result.unexpectedRowCount, greaterThan(0));
  });

  test('keeps duplicate rows and NULL values significant', () async {
    final missingDuplicate = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql:
          "SELECT DISTINCT last_statement FROM executions "
          "WHERE county = 'Harris'",
      solutionSql:
          "SELECT last_statement FROM executions WHERE county = 'Harris'",
    );
    final nullAsEmpty = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql:
          'SELECT COALESCE(last_statement, \'\') FROM executions ORDER BY id',
      solutionSql: 'SELECT last_statement FROM executions ORDER BY id',
      orderSensitive: true,
    );

    expect(missingDuplicate.verdict, SqlExerciseVerdict.incorrect);
    expect(missingDuplicate.missingRowCount, 1);
    expect(nullAsEmpty.verdict, SqlExerciseVerdict.incorrect);
  });

  test('runs submissions read-only and rejects multiple statements', () async {
    final write = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql: "DELETE FROM executions WHERE county = 'Harris'",
      solutionSql: 'SELECT COUNT(*) FROM executions',
    );
    final multiple = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql: 'SELECT 1; SELECT 2;',
      solutionSql: 'SELECT 1',
    );

    expect(write.verdict, SqlExerciseVerdict.invalidSubmission);
    expect(multiple.verdict, SqlExerciseVerdict.invalidSubmission);

    final database = sqlite3.open(databasePath);
    addTearDown(database.close);
    expect(
      database.select('SELECT COUNT(*) AS c FROM executions').single['c'],
      4,
    );
  });

  test('optionally compares result column names', () async {
    final aliasesIgnored = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql: 'SELECT COUNT(*) AS actual FROM executions',
      solutionSql: 'SELECT COUNT(*) AS expected FROM executions',
    );
    final aliasesRequired = await const SqlExerciseEvaluator().evaluate(
      databasePath: databasePath,
      submissionSql: 'SELECT COUNT(*) AS actual FROM executions',
      solutionSql: 'SELECT COUNT(*) AS expected FROM executions',
      compareColumnNames: true,
    );

    expect(aliasesIgnored.verdict, SqlExerciseVerdict.correct);
    expect(aliasesRequired.verdict, SqlExerciseVerdict.incorrect);
  });
}
