import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

enum DatabaseObjectType { table, view }

class DatabaseObjectSummary {
  const DatabaseObjectSummary({
    required this.name,
    required this.type,
    required this.createSql,
  });

  final String name;
  final DatabaseObjectType type;
  final String createSql;
}

class DatabaseOverview {
  const DatabaseOverview({
    required this.objects,
    required this.userVersion,
    required this.applicationId,
    required this.pageSize,
    required this.pageCount,
    required this.encoding,
  });

  final List<DatabaseObjectSummary> objects;
  final int userVersion;
  final int applicationId;
  final int pageSize;
  final int pageCount;
  final String encoding;
}

class DatabaseColumnInfo {
  const DatabaseColumnInfo({
    required this.id,
    required this.name,
    required this.declaredType,
    required this.notNull,
    required this.defaultSql,
    required this.primaryKeyOrder,
    required this.hidden,
  });

  final int id;
  final String name;
  final String declaredType;
  final bool notNull;
  final String? defaultSql;
  final int primaryKeyOrder;
  final int hidden;
}

class DatabaseForeignKeyInfo {
  const DatabaseForeignKeyInfo({
    required this.id,
    required this.sequence,
    required this.referencedTable,
    required this.fromColumn,
    required this.toColumn,
    required this.onUpdate,
    required this.onDelete,
    required this.match,
  });

  final int id;
  final int sequence;
  final String referencedTable;
  final String fromColumn;
  final String? toColumn;
  final String onUpdate;
  final String onDelete;
  final String match;
}

class DatabaseIndexInfo {
  const DatabaseIndexInfo({
    required this.name,
    required this.unique,
    required this.origin,
    required this.partial,
    required this.columns,
    required this.createSql,
  });

  final String name;
  final bool unique;
  final String origin;
  final bool partial;
  final List<String> columns;
  final String? createSql;
}

class DatabaseObjectSnapshot {
  const DatabaseObjectSnapshot({
    required this.object,
    required this.columns,
    required this.foreignKeys,
    required this.indexes,
    required this.columnNames,
    required this.rows,
    required this.totalRowCount,
    required this.limit,
    required this.offset,
  });

  final DatabaseObjectSummary object;
  final List<DatabaseColumnInfo> columns;
  final List<DatabaseForeignKeyInfo> foreignKeys;
  final List<DatabaseIndexInfo> indexes;
  final List<String> columnNames;
  final List<List<Object?>> rows;
  final int totalRowCount;
  final int limit;
  final int offset;
}

/// Read-only SQLite introspection used by the database browser.
///
/// Object names are first resolved from sqlite_schema and then quoted before
/// being used in PRAGMA or SELECT statements. This keeps browsing separate
/// from the writable execution connection.
class SqliteDatabaseBrowser {
  const SqliteDatabaseBrowser();

  DatabaseOverview loadOverview(String path) {
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final objects = database.select('''
        SELECT name, type, sql
        FROM sqlite_schema
        WHERE type IN ('table', 'view')
          AND name NOT LIKE 'sqlite_%'
        ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name COLLATE NOCASE
      ''');
      return DatabaseOverview(
        objects: <DatabaseObjectSummary>[
          for (final row in objects)
            DatabaseObjectSummary(
              name: row['name'] as String,
              type: row['type'] == 'view'
                  ? DatabaseObjectType.view
                  : DatabaseObjectType.table,
              createSql: row['sql'] as String? ?? '',
            ),
        ],
        userVersion: _pragmaInt(database, 'user_version'),
        applicationId: _pragmaInt(database, 'application_id'),
        pageSize: _pragmaInt(database, 'page_size'),
        pageCount: _pragmaInt(database, 'page_count'),
        encoding: '${database.select('PRAGMA encoding').single.columnAt(0)}',
      );
    } finally {
      database.close();
    }
  }

  DatabaseObjectSnapshot loadObject(
    String path,
    String objectName, {
    int limit = 100,
    int offset = 0,
  }) {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final matches = database.select(
        '''
        SELECT name, type, sql
        FROM sqlite_schema
        WHERE name = ? AND type IN ('table', 'view')
          AND name NOT LIKE 'sqlite_%'
        LIMIT 1
        ''',
        <Object?>[objectName],
      );
      if (matches.isEmpty) {
        throw StateError('Table or view not found: $objectName');
      }
      final schemaRow = matches.single;
      final resolvedName = schemaRow['name'] as String;
      final quotedName = _quoteIdentifier(resolvedName);
      final object = DatabaseObjectSummary(
        name: resolvedName,
        type: schemaRow['type'] == 'view'
            ? DatabaseObjectType.view
            : DatabaseObjectType.table,
        createSql: schemaRow['sql'] as String? ?? '',
      );
      final columns = database.select('PRAGMA table_xinfo($quotedName)');
      final result = database.select(
        'SELECT * FROM $quotedName LIMIT ? OFFSET ?',
        <Object?>[limit, offset],
      );
      final count =
          database
                  .select('SELECT COUNT(*) AS row_count FROM $quotedName')
                  .single['row_count']
              as int;

      return DatabaseObjectSnapshot(
        object: object,
        columns: <DatabaseColumnInfo>[
          for (final row in columns)
            DatabaseColumnInfo(
              id: row['cid'] as int,
              name: row['name'] as String,
              declaredType: row['type'] as String? ?? '',
              notNull: row['notnull'] == 1,
              defaultSql: row['dflt_value'] as String?,
              primaryKeyOrder: row['pk'] as int,
              hidden: row['hidden'] as int? ?? 0,
            ),
        ],
        foreignKeys: _loadForeignKeys(database, quotedName),
        indexes: object.type == DatabaseObjectType.table
            ? _loadIndexes(database, resolvedName, quotedName)
            : const <DatabaseIndexInfo>[],
        columnNames: result.columnNames,
        rows: <List<Object?>>[
          for (final row in result)
            <Object?>[
              for (var index = 0; index < result.columnNames.length; index++)
                _copyValue(row.columnAt(index)),
            ],
        ],
        totalRowCount: count,
        limit: limit,
        offset: offset,
      );
    } finally {
      database.close();
    }
  }

  static List<DatabaseForeignKeyInfo> _loadForeignKeys(
    Database database,
    String quotedName,
  ) {
    return <DatabaseForeignKeyInfo>[
      for (final row in database.select('PRAGMA foreign_key_list($quotedName)'))
        DatabaseForeignKeyInfo(
          id: row['id'] as int,
          sequence: row['seq'] as int,
          referencedTable: row['table'] as String,
          fromColumn: row['from'] as String,
          toColumn: row['to'] as String?,
          onUpdate: row['on_update'] as String,
          onDelete: row['on_delete'] as String,
          match: row['match'] as String,
        ),
    ];
  }

  static List<DatabaseIndexInfo> _loadIndexes(
    Database database,
    String resolvedName,
    String quotedName,
  ) {
    final rows = database.select('PRAGMA index_list($quotedName)');
    return <DatabaseIndexInfo>[
      for (final row in rows)
        DatabaseIndexInfo(
          name: row['name'] as String,
          unique: row['unique'] == 1,
          origin: row['origin'] as String,
          partial: row['partial'] == 1,
          columns: database
              .select(
                'PRAGMA index_info(${_quoteIdentifier(row['name'] as String)})',
              )
              .map((column) => column['name'] as String? ?? '')
              .toList(growable: false),
          createSql:
              database
                      .select(
                        '''
                SELECT sql FROM sqlite_schema
                WHERE type = 'index' AND tbl_name = ? AND name = ?
                ''',
                        <Object?>[resolvedName, row['name']],
                      )
                      .firstOrNull?['sql']
                  as String?,
        ),
    ];
  }

  static int _pragmaInt(Database database, String name) =>
      database.select('PRAGMA $name').single.columnAt(0) as int;

  static Object? _copyValue(Object? value) {
    if (value is Uint8List) return Uint8List.fromList(value);
    return value;
  }

  static String _quoteIdentifier(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';
}
