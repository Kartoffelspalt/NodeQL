import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/plugins/plugin_loader.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const manifestJson = <String, dynamic>{
  'schemaVersion': 1,
  'id': 'dev.nodeql.tests',
  'name': 'Test Plugin',
  'version': '1.2.0',
  'minNodeQlVersion': '0.1.0',
  'capabilities': <String>['sql.compile'],
  'blocks': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'ilike',
      'shape': 'statement',
      'label': <String, String>{
        'en': '[column] contains [pattern]',
        'de': '[column] enthaelt [pattern]',
      },
      'description': 'Case-insensitive comparison',
      'inputs': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'column',
          'type': 'identifier',
          'default': 'name',
        },
        <String, dynamic>{
          'name': 'pattern',
          'type': 'string',
          'default': '%node%',
        },
      ],
      'sql': '{{column}} ILIKE {{pattern}}',
    },
  ],
};

void main() {
  test('parses and renders an independent plugin block', () {
    final manifest = NodeQlPluginManifest.fromJson(manifestJson);
    final block = manifest.blocks.single;

    expect(block.qualifiedId, 'dev.nodeql.tests/ilike');
    expect(
      block.renderSql(<String, dynamic>{
        'column': 'users.name',
        'pattern': "O'Reilly",
      }, childrenSql: ''),
      "users.name ILIKE 'O''Reilly'",
    );
    expect(block.uiTemplateFor('de'), '[column] enthaelt [pattern]');
  });

  test('rejects invalid defaults and unknown placeholders', () {
    final invalidDefault = _copyManifest();
    (invalidDefault['blocks'] as List<dynamic>).single['inputs'][0]['default'] =
        'not an identifier';
    expect(
      () => NodeQlPluginManifest.fromJson(invalidDefault),
      throwsFormatException,
    );

    final unknownPlaceholder = _copyManifest();
    (unknownPlaceholder['blocks'] as List<dynamic>).single['sql'] =
        '{{missing}}';
    expect(
      () => NodeQlPluginManifest.fromJson(unknownPlaceholder),
      throwsFormatException,
    );

    final unknownField = _copyManifest()..['executable'] = 'plugin.sh';
    expect(
      () => NodeQlPluginManifest.fromJson(unknownField),
      throwsFormatException,
    );
  });

  test('loader reports incompatible plugins', () async {
    final root = await Directory.systemTemp.createTemp('nodeql-plugin-test-');
    addTearDown(() => root.delete(recursive: true));
    final manifest = File('${root.path}/plugin.json');
    await manifest.writeAsString(_encodeManifest(manifestJson));

    final result = await const NodeQlPluginLoader(
      currentNodeQlVersion: '0.0.9',
    ).load(root);

    expect(result.blocks, isEmpty);
    expect(result.issues.single.message, contains('requires NodeQL 0.1.0'));
  });

  test('repository example is a valid installable plugin', () async {
    final pluginDirectory = Directory(
      'examples/plugins/com.example.text-tools',
    );
    final source = await File(
      p.join(pluginDirectory.path, 'plugin.json'),
    ).readAsString();
    final manifest = NodeQlPluginManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );

    expect(manifest.id, p.basename(pluginDirectory.path));
    expect(manifest.blocks, hasLength(2));

    final comparison = manifest.blocks.singleWhere(
      (block) => block.id == 'ilike',
    );
    expect(
      comparison.renderSql(<String, dynamic>{
        'column': 'name',
        'pattern': '%ADA%',
      }, childrenSql: ''),
      "LOWER(name) LIKE LOWER('%ADA%')",
    );
  });

  test('all repository examples load together without conflicts', () async {
    final result = await const NodeQlPluginLoader(
      currentNodeQlVersion: '0.1.32',
    ).load(Directory('examples/plugins'));

    expect(result.issues, isEmpty);
    expect(result.manifests, hasLength(6));
    expect(result.blocks, hasLength(22));
    expect(
      result.blocksByQualifiedId,
      contains('dev.nodeql.sqlite-power/date-series'),
    );
    for (final block in result.blocks) {
      if (block.sqlTemplate == null) continue;
      expect(
        block.renderSql(block.workspaceDefaults, childrenSql: 'SELECT 1'),
        isNotEmpty,
        reason: block.qualifiedId,
      );
    }
    for (final manifest in result.manifests) {
      final directory = Directory(p.join('examples/plugins', manifest.id));
      expect(
        await directory.exists(),
        isTrue,
        reason: 'Plugin directory must match manifest ID ${manifest.id}.',
      );
    }
  });

  test('text and transaction example blocks execute on SQLite', () async {
    final source = await File(
      'examples/plugins/com.example.text-tools/plugin.json',
    ).readAsString();
    final manifest = NodeQlPluginManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );
    final tempDir = await Directory.systemTemp.createTemp('nodeql-plugin-sql-');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'plugin.db');
    final database = sqlite3.open(dbPath);
    database.execute('''
      CREATE TABLE people (name TEXT NOT NULL);
      INSERT INTO people (name) VALUES ('Ada'), ('Grace');
    ''');
    database.close();

    final comparison = manifest.blocks.singleWhere(
      (block) => block.id == 'ilike',
    );
    final controller = SqlRuntimeController();
    await controller.attachDatabasePath(dbPath);
    await controller.executeWithSnapshot(
      'SELECT name FROM people WHERE ${comparison.renderSql(<String, dynamic>{'column': 'name', 'pattern': '%ADA%'}, childrenSql: '')};',
    );
    expect(controller.state.lastRows, <Map<String, String>>[
      <String, String>{'name': 'Ada'},
    ]);

    final transaction = manifest.blocks.singleWhere(
      (block) => block.id == 'transaction',
    );
    await controller.executeWithSnapshot(
      transaction.renderSql(
        const <String, dynamic>{},
        childrenSql: "INSERT INTO people (name) VALUES ('Lin')",
      ),
    );
    expect(controller.state.lastMessage, 'OK');

    await controller.executeWithSnapshot(
      'SELECT name FROM people ORDER BY rowid;',
    );
    expect(controller.state.lastRows.map((row) => row['name']), <String>[
      'Ada',
      'Grace',
      'Lin',
    ]);
  });

  test('compiler executes plugin SQL and warns on version changes', () {
    final plugin = NodeQlPluginManifest.fromJson(manifestJson).blocks.single;
    final root = EventBlock(id: 'event', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'plugin',
        position: Offset.zero,
        operatorType: plugin.hostBlockType,
        inputs: <String, dynamic>{
          ...plugin.workspaceDefaults,
          pluginVersionInput: '1.0.0',
          'column': 'name',
          'pattern': '%ql%',
        },
      );

    final result = const SqlCompiler().compileWorkspace(
      <BlockNode>[root],
      pluginBlocks: <String, NodeQlPluginBlock>{plugin.qualifiedId: plugin},
    );

    expect(result.sql, "name ILIKE '%ql%';");
    expect(result.warnings.single, contains('running with 1.2.0'));
  });

  test('compiler preserves missing plugin blocks as warnings', () {
    final root = EventBlock(id: 'event', position: Offset.zero)
      ..next = OperatorBlock(
        id: 'missing',
        position: Offset.zero,
        operatorType: BlockType.sqlHaving,
        inputs: <String, dynamic>{
          pluginBlockKeyInput: 'dev.nodeql.missing/block',
          pluginVersionInput: '1.0.0',
        },
      );

    final result = const SqlCompiler().compileWorkspace(<BlockNode>[root]);

    expect(result.sql, isEmpty);
    expect(result.warnings.single, contains('unavailable'));
  });
}

Map<String, dynamic> _copyManifest() {
  return Map<String, dynamic>.from(
    _decodeManifest(_encodeManifest(manifestJson)) as Map,
  );
}

String _encodeManifest(Map<String, dynamic> value) => jsonEncode(value);

Object? _decodeManifest(String value) => jsonDecode(value);
