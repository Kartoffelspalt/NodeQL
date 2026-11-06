import 'package:nodeql/core/platform/storage.dart';

import 'package:nodeql/features/tutorial/workshop_dataset.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:nodeql/core/platform/sqlite.dart';

/// Disposable, self-contained data set used only by one workshop session.
class WorkshopDatabase {
  WorkshopDatabase._(this.directory, this.path);

  final Directory directory;
  final String path;

  static WorkshopDatabase create() {
    final directory = temporaryDirectory.createTempSync('nodeql_workshop_');
    final path = p.join(directory.path, 'practice.db');
    try {
      final database = sqlite3.open(path);
      try {
        seedWorkshopDataset(database);
      } finally {
        database.close();
      }
      return WorkshopDatabase._(directory, path);
    } catch (_) {
      directory.deleteSync(recursive: true);
      rethrow;
    }
  }

  SqlRuntimeState get initialState =>
      SqlRuntimeState(dbPath: path, schemas: practiceSchemas);

  static const practiceSchemas = <TableSchema>[
    TableSchema(
      name: 'customers',
      columns: <String>['id', 'name', 'city', 'country', 'active'],
    ),
    TableSchema(
      name: 'orders',
      columns: <String>['id', 'customer_id', 'total', 'created_at'],
    ),
    TableSchema(name: 'archived_customers', columns: <String>['id', 'name']),
  ];

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
