import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/workshop_database.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('workshop has related rows and is removed with its session', () {
    final sample = WorkshopDatabase.create();
    final database = sqlite3.open(sample.path);
    try {
      expect(sample.initialState.schemas, hasLength(3));
      expect(
        database.select('SELECT COUNT(*) AS n FROM customers').single['n'],
        8,
      );
      expect(
        database.select('SELECT COUNT(*) AS n FROM orders').single['n'],
        10,
      );
    } finally {
      database.close();
    }

    sample.dispose();
    expect(File(sample.path).existsSync(), isFalse);
  });

  test('isolated workshop runtime supports explicit write exercises', () async {
    final sample = WorkshopDatabase.create();
    addTearDown(sample.dispose);
    final runtime = SqlRuntimeController(initialState: sample.initialState);
    addTearDown(runtime.dispose);

    final result = await runtime.executeWithSnapshot('''
      INSERT INTO archived_customers (id, name) VALUES (999, 'Workshop');
      UPDATE archived_customers SET name = 'NodeQL' WHERE id = 999;
      DELETE FROM archived_customers WHERE id = 999;
    ''');
    expect(result.success, isTrue);
    expect(result.changedDatabase, isTrue);

    final database = sqlite3.open(sample.path);
    try {
      expect(
        database.select('SELECT id FROM archived_customers WHERE id = 999'),
        isEmpty,
      );
    } finally {
      database.close();
    }
  });
}
