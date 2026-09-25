import 'dart:io';

import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Disposable, self-contained data set used only by one workshop session.
class WorkshopDatabase {
  WorkshopDatabase._(this.directory, this.path);

  final Directory directory;
  final String path;

  static WorkshopDatabase create() {
    final directory = Directory.systemTemp.createTempSync('nodeql_workshop_');
    final path = p.join(directory.path, 'practice.db');
    try {
      final database = sqlite3.open(path);
      try {
        database.execute('''
          PRAGMA foreign_keys = ON;
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            city TEXT NOT NULL,
            country TEXT NOT NULL,
            active INTEGER NOT NULL
          );
          CREATE TABLE orders (
            id INTEGER PRIMARY KEY,
            customer_id INTEGER NOT NULL REFERENCES customers(id),
            total REAL NOT NULL,
            created_at TEXT NOT NULL
          );
          CREATE TABLE archived_customers (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
          );
          INSERT INTO customers VALUES
            (1, 'Ada', 'Berlin', 'DE', 1),
            (2, 'Bruno', 'Hamburg', 'DE', 1),
            (3, 'Clara', 'Berlin', 'DE', 0),
            (4, 'Dina', 'Paris', 'FR', 1),
            (5, 'Emil', 'Munich', 'DE', 1),
            (6, 'Fatima', 'Berlin', 'DE', 1),
            (7, 'Gio', 'Rome', 'IT', 0),
            (8, 'Hana', 'Lyon', 'FR', 1);
          INSERT INTO orders VALUES
            (1, 1, 89.50, '2026-01-03'),
            (2, 1, 22.00, '2026-01-09'),
            (3, 2, 110.00, '2026-01-15'),
            (4, 3, 15.00, '2026-02-01'),
            (5, 4, 42.75, '2026-02-11'),
            (6, 4, 77.25, '2026-02-15'),
            (7, 5, 12.00, '2026-03-02'),
            (8, 6, 149.99, '2026-03-05'),
            (9, 6, 18.50, '2026-03-06'),
            (10, 6, 31.00, '2026-03-10');
          INSERT INTO archived_customers VALUES
            (1, 'Ada'), (101, 'Iris'), (102, 'Jamal'), (103, 'Kora');
        ''');
      } finally {
        database.close();
      }
      return WorkshopDatabase._(directory, path);
    } catch (_) {
      directory.deleteSync(recursive: true);
      rethrow;
    }
  }

  SqlRuntimeState get initialState => SqlRuntimeState(
    dbPath: path,
    schemas: const <TableSchema>[
      TableSchema(
        name: 'customers',
        columns: <String>['id', 'name', 'city', 'country', 'active'],
      ),
      TableSchema(
        name: 'orders',
        columns: <String>['id', 'customer_id', 'total', 'created_at'],
      ),
      TableSchema(name: 'archived_customers', columns: <String>['id', 'name']),
    ],
  );

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
