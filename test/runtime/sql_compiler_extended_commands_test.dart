import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';

void main() {
  test('serializes every extended SQLite node type', () {
    const types = <BlockType>[
      BlockType.sqlInsertOrReplace,
      BlockType.sqlUpsert,
      BlockType.sqlDropIndex,
      BlockType.sqlCreateView,
      BlockType.sqlDropView,
      BlockType.sqlCreateTrigger,
      BlockType.sqlDropTrigger,
      BlockType.sqlCreateVirtualTable,
      BlockType.sqlBeginTransaction,
      BlockType.sqlEndTransaction,
      BlockType.sqlReleaseSavepoint,
      BlockType.sqlPragma,
      BlockType.sqlAttachDatabase,
      BlockType.sqlDetachDatabase,
      BlockType.sqlVacuum,
      BlockType.sqlReindex,
      BlockType.sqlAnalyze,
      BlockType.sqlExplain,
      BlockType.sqlWith,
      BlockType.sqlValues,
    ];

    for (final type in types) {
      final restored = BlockNode.fromJson(
        _node(type, <String, dynamic>{'marker': type.name}).toJson(),
      );
      expect(restored.type, type);
      expect(restored.inputs['marker'], type.name);
    }
  });

  group('extended SQLite DML', () {
    test('compiles INSERT OR REPLACE and UPSERT conflict actions', () {
      expect(
        _compile(BlockType.sqlInsertOrReplace, <String, dynamic>{
          'table': 'kunden',
          'columns': 'kunden_id, status',
          'values': "(1, 'Aktiv')",
        }).sql,
        "INSERT OR REPLACE INTO kunden (kunden_id, status) VALUES (1, 'Aktiv');",
      );

      expect(
        _compile(BlockType.sqlUpsert, <String, dynamic>{
          'table': 'kunden',
          'columns': 'kunden_id, status',
          'values': "(1, 'Aktiv')",
          'conflict_columns': 'kunden_id',
          'action': 'DO UPDATE',
          'assignments': 'status = excluded.status',
          'update_where': "excluded.status != 'Gesperrt'",
        }).sql,
        "INSERT INTO kunden (kunden_id, status) VALUES (1, 'Aktiv') "
        'ON CONFLICT (kunden_id) DO UPDATE SET status = excluded.status '
        "WHERE excluded.status != 'Gesperrt';",
      );

      expect(
        _compile(BlockType.sqlUpsert, <String, dynamic>{
          'table': 'kunden',
          'columns': 'kunden_id',
          'values': '(1)',
          'conflict_columns': 'kunden_id',
          'action': 'DO NOTHING',
        }).sql,
        'INSERT INTO kunden (kunden_id) VALUES (1) '
        'ON CONFLICT (kunden_id) DO NOTHING;',
      );
    });
  });

  group('extended SQLite DDL', () {
    test('compiles indexes, views, triggers and virtual tables', () {
      expect(
        _compile(BlockType.sqlDropIndex, <String, dynamic>{
          'if_exists': 'IF EXISTS',
          'name': 'idx_status',
        }).sql,
        'DROP INDEX IF EXISTS idx_status;',
      );
      expect(
        _compile(BlockType.sqlCreateView, <String, dynamic>{
          'temporary': 'TEMP',
          'if_not_exists': 'IF NOT EXISTS',
          'name': 'aktive_kunden',
          'columns': 'kunden_id, status',
          'sql': "SELECT kunden_id, status FROM kunden WHERE status = 'Aktiv';",
        }).sql,
        'CREATE TEMP VIEW IF NOT EXISTS aktive_kunden (kunden_id, status) '
        "AS SELECT kunden_id, status FROM kunden WHERE status = 'Aktiv';",
      );
      expect(
        _compile(BlockType.sqlDropView, <String, dynamic>{
          'if_exists': 'IF EXISTS',
          'name': 'aktive_kunden',
        }).sql,
        'DROP VIEW IF EXISTS aktive_kunden;',
      );
      expect(
        _compile(BlockType.sqlCreateTrigger, <String, dynamic>{
          'if_not_exists': 'IF NOT EXISTS',
          'name': 'log_insert',
          'timing': 'AFTER',
          'event': 'INSERT',
          'table': 'kunden',
          'when': 'NEW.kunden_id > 0',
          'body': 'INSERT INTO audit (kunden_id) VALUES (NEW.kunden_id);',
        }).sql,
        'CREATE TRIGGER IF NOT EXISTS log_insert AFTER INSERT ON kunden '
        'FOR EACH ROW WHEN NEW.kunden_id > 0 BEGIN '
        'INSERT INTO audit (kunden_id) VALUES (NEW.kunden_id); END;',
      );
      expect(
        _compile(BlockType.sqlDropTrigger, <String, dynamic>{
          'if_exists': 'IF EXISTS',
          'name': 'log_insert',
        }).sql,
        'DROP TRIGGER IF EXISTS log_insert;',
      );
      expect(
        _compile(BlockType.sqlCreateVirtualTable, <String, dynamic>{
          'if_not_exists': 'IF NOT EXISTS',
          'table': 'suche',
          'module': 'FTS5',
          'arguments': 'titel, inhalt',
        }).sql,
        'CREATE VIRTUAL TABLE IF NOT EXISTS suche USING fts5(titel, inhalt);',
      );
      expect(
        _compile(BlockType.sqlAlterTable, <String, dynamic>{
          'table': 'kunden',
          'alter_action': 'ADD COLUMN',
          'alter_value': "email TEXT DEFAULT ''",
        }).sql,
        "ALTER TABLE kunden ADD COLUMN email TEXT DEFAULT '';",
      );
      expect(
        _compile(BlockType.sqlAlterTable, <String, dynamic>{
          'table': 'kunden',
          'alter_action': 'RENAME COLUMN',
          'alter_value': 'status TO kundenstatus',
        }).sql,
        'ALTER TABLE kunden RENAME COLUMN status TO kundenstatus;',
      );
    });
  });

  group('snapshot-style TCL', () {
    test('separates restore operations in one executable script', () {
      final begin = _node(BlockType.sqlBeginTransaction, <String, dynamic>{
        'behavior': 'IMMEDIATE',
      }, id: 'begin');
      final insert = _node(BlockType.sqlInsert, <String, dynamic>{
        'table': 'notes',
        'columns': 'body',
        'values': "('one')",
      }, id: 'insert');
      final savepoint = _node(BlockType.sqlSavepoint, <String, dynamic>{
        'name': 'before_change',
      }, id: 'savepoint');
      final rollbackTo = _node(
        BlockType.sqlRollbackToSavepoint,
        <String, dynamic>{'name': 'before_change'},
        id: 'rollback-to',
      );
      final release = _node(BlockType.sqlReleaseSavepoint, <String, dynamic>{
        'name': 'before_change',
      }, id: 'release');
      final commit = _node(BlockType.sqlCommit, const {}, id: 'commit');
      begin.next = insert;
      insert.next = savepoint;
      savepoint.next = rollbackTo;
      rollbackTo.next = release;
      release.next = commit;

      final result = _compileChain(begin);

      expect(
        result.sql,
        'BEGIN IMMEDIATE TRANSACTION; '
        "INSERT INTO notes (body) VALUES ('one'); "
        'SAVEPOINT before_change; '
        'ROLLBACK TO SAVEPOINT before_change; '
        'RELEASE SAVEPOINT before_change; COMMIT;',
      );
      expect(
        result.sourceMap.map((span) => span.nodeId).toSet(),
        containsAll(<String>{
          'begin',
          'insert',
          'savepoint',
          'rollback-to',
          'release',
          'commit',
        }),
      );
      expect(
        <String, int>{
          for (final span in result.sourceMap)
            if (span.nodeId != 'select') span.nodeId: span.statementIndex,
        },
        <String, int>{
          'begin': 0,
          'insert': 1,
          'savepoint': 2,
          'rollback-to': 3,
          'release': 4,
          'commit': 5,
        },
      );
    });
  });

  group('SQLite tools and advanced queries', () {
    test('compiles supported PRAGMA forms and maintenance commands', () {
      expect(
        _compile(BlockType.sqlPragma, <String, dynamic>{
          'pragma': 'foreign_keys',
          'value': 'ON',
        }).sql,
        'PRAGMA foreign_keys = ON;',
      );
      expect(
        _compile(BlockType.sqlPragma, <String, dynamic>{
          'pragma': 'table_info',
          'value': "kunden'archiv",
        }).sql,
        "PRAGMA table_info('kunden''archiv');",
      );
      expect(
        _compile(BlockType.sqlPragma, <String, dynamic>{
          'pragma': 'database_list',
        }).sql,
        'PRAGMA database_list;',
      );
      expect(
        _compile(BlockType.sqlPragma, <String, dynamic>{
          'pragma': 'journal_mode',
          'value': 'WAL',
        }).sql,
        'PRAGMA journal_mode = WAL;',
      );
      expect(_compile(BlockType.sqlVacuum, const {}).sql, 'VACUUM;');
      expect(
        _compile(BlockType.sqlReindex, <String, dynamic>{
          'target': 'idx_status',
        }).sql,
        'REINDEX idx_status;',
      );
      expect(
        _compile(BlockType.sqlAnalyze, <String, dynamic>{
          'target': 'kunden',
        }).sql,
        'ANALYZE kunden;',
      );
    });

    test('compiles ATTACH, DETACH, WITH, VALUES and EXPLAIN', () {
      expect(
        _compile(BlockType.sqlAttachDatabase, <String, dynamic>{
          'path': "archive's.db",
          'schema': 'year 2025',
        }).sql,
        "ATTACH DATABASE 'archive''s.db' AS \"year 2025\";",
      );
      expect(
        _compile(BlockType.sqlDetachDatabase, <String, dynamic>{
          'schema': 'year 2025',
        }).sql,
        'DETACH DATABASE "year 2025";',
      );
      expect(
        _compile(BlockType.sqlValues, <String, dynamic>{
          'values': "(1, 'A'), (2, 'B')",
        }).sql,
        "VALUES (1, 'A'), (2, 'B');",
      );

      final withNode = _node(BlockType.sqlWith, <String, dynamic>{
        'recursive': 'RECURSIVE',
        'name': 'numbers',
        'columns': 'n',
        'sql': 'VALUES (1)',
      }, id: 'with');
      withNode.next = _node(BlockType.sqlSelect, <String, dynamic>{
        'columns': 'n',
        'table': 'numbers',
      }, id: 'select-after-with');
      expect(
        _compileChain(withNode).sql,
        'WITH RECURSIVE numbers (n) AS (VALUES (1)) '
        'SELECT n FROM numbers;',
      );

      final explain = _node(BlockType.sqlExplain, <String, dynamic>{
        'mode': 'EXPLAIN QUERY PLAN',
      }, id: 'explain');
      explain.next = _node(BlockType.sqlSelect, <String, dynamic>{
        'columns': '*',
        'table': 'kunden',
      }, id: 'explained-select');
      expect(
        _compileChain(explain).sql,
        'EXPLAIN QUERY PLAN SELECT * FROM kunden;',
      );
    });
  });
}

SqlCompileResult _compile(BlockType type, Map<String, dynamic> inputs) {
  return _compileChain(_node(type, inputs));
}

SqlCompileResult _compileChain(BlockNode first) {
  final root = EventBlock(id: 'run-${first.id}', position: Offset.zero)
    ..next = first;
  return const SqlCompiler().compileWorkspace(<BlockNode>[root]);
}

OperatorBlock _node(BlockType type, Map<String, dynamic> inputs, {String? id}) {
  return OperatorBlock(
    id: id ?? type.name,
    position: Offset.zero,
    operatorType: type,
    inputs: inputs,
  );
}
