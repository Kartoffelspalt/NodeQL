import 'package:nodeql/core/platform/sqlite.dart';

/// Creates the built-in practice dataset in an empty SQLite connection.
void seedWorkshopDataset(CommonDatabase database) {
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
      (1, 'Albrecht', 'Berlin', 'DE', 1),
      (2, 'Berthold', 'Hamburg', 'DE', 1),
      (3, 'Gertrud', 'Berlin', 'DE', 0),
      (4, 'Hildegard', 'Paris', 'FR', 1),
      (5, 'Friedrich', 'Munich', 'DE', 1),
      (6, 'Ottilie', 'Berlin', 'DE', 1),
      (7, 'Siegfried', 'Rome', 'IT', 0),
      (8, 'Walburga', 'Lyon', 'FR', 1);
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
      (1, 'Albrecht'), (101, 'Anneliese'), (102, 'Burkhard'), (103, 'Edeltraud');
  ''');
}
