import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/features/workbench/presentation/engine/database_browser.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:nodeql/features/workbench/presentation/widgets/database_browser_dialog.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tempDirectory;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'nodeql_database_browser',
    );
    databasePath = '${tempDirectory.path}${Platform.pathSeparator}browser.db';
    final database = sqlite3.open(databasePath);
    database.execute('''
      PRAGMA user_version = 7;
      PRAGMA application_id = 1234;
      PRAGMA foreign_keys = ON;
      CREATE TABLE authors (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      );
      CREATE TABLE "book details" (
        id INTEGER PRIMARY KEY,
        author_id INTEGER NOT NULL REFERENCES authors(id) ON DELETE CASCADE,
        title TEXT DEFAULT 'Untitled',
        notes TEXT,
        cover BLOB
      );
      CREATE INDEX book_title_idx ON "book details" (title);
      INSERT INTO authors VALUES (1, 'Ada');
      INSERT INTO "book details" (id, author_id, title, notes, cover) VALUES
        (1, 1, 'First', NULL, X'00FF'),
        (2, 1, 'Second', 'note', X'CAFE'),
        (3, 1, 'Third', 'last', NULL);
      CREATE VIEW book_titles AS SELECT id, title FROM "book details";
    ''');
    database.close();
  });

  tearDown(() => tempDirectory.delete(recursive: true));

  test('reads database objects, exact schema details, and paged values', () {
    const browser = SqliteDatabaseBrowser();

    final overview = browser.loadOverview(databasePath);

    expect(overview.userVersion, 7);
    expect(overview.applicationId, 1234);
    expect(overview.encoding, 'UTF-8');
    expect(overview.objects.map((object) => object.name), <String>[
      'authors',
      'book details',
      'book_titles',
    ]);
    expect(overview.objects.last.type, DatabaseObjectType.view);

    final firstPage = browser.loadObject(
      databasePath,
      'book details',
      limit: 2,
    );

    expect(firstPage.totalRowCount, 3);
    expect(firstPage.columnNames, <String>[
      'id',
      'author_id',
      'title',
      'notes',
      'cover',
    ]);
    expect(firstPage.columns[1].notNull, isTrue);
    expect(firstPage.columns[2].defaultSql, "'Untitled'");
    expect(firstPage.columns.first.primaryKeyOrder, 1);
    expect(firstPage.rows, hasLength(2));
    expect(firstPage.rows.first[3], isNull);
    expect(firstPage.rows.first[4], Uint8List.fromList(<int>[0, 255]));
    expect(firstPage.foreignKeys.single.referencedTable, 'authors');
    expect(firstPage.foreignKeys.single.fromColumn, 'author_id');
    expect(firstPage.foreignKeys.single.onDelete, 'CASCADE');
    expect(
      firstPage.indexes.map((index) => index.name),
      contains('book_title_idx'),
    );
    expect(firstPage.object.createSql, contains('CREATE TABLE'));

    final secondPage = browser.loadObject(
      databasePath,
      'book details',
      limit: 2,
      offset: 2,
    );
    expect(secondPage.rows, hasLength(1));
    expect(secondPage.rows.single[2], 'Third');
  });

  test('rejects object names that are not present in sqlite_schema', () {
    expect(
      () => const SqliteDatabaseBrowser().loadObject(
        databasePath,
        'book details"; DROP TABLE authors; --',
      ),
      throwsStateError,
    );
    final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
    addTearDown(database.close);
    expect(
      database.select('SELECT COUNT(*) FROM authors').single.columnAt(0),
      1,
    );
  });

  test('loads overview and snapshots through the production worker', () async {
    const worker = DatabaseBrowserWorker();

    final overview = await worker.loadOverview(databasePath);
    final snapshot = await worker.loadObject(databasePath, 'authors', 100, 0);

    expect(overview.objects, hasLength(3));
    expect(snapshot.totalRowCount, 1);
    expect(snapshot.rows.single, <Object?>[1, 'Ada']);
  });

  testWidgets('creates tables from the browser', (tester) async {
    const messages = <String, String>{
      'databaseBrowser.title': 'SQLite table browser',
      'databaseBrowser.refresh': 'Reload database',
      'databaseBrowser.objectCount': '{count} object(s)',
      'databaseBrowser.search': 'Search tables or views',
      'databaseBrowser.clearSearch': 'Clear search',
      'databaseBrowser.tables': 'Tables',
      'databaseBrowser.views': 'Views',
      'databaseBrowser.table': 'Table',
      'databaseBrowser.view': 'View',
      'databaseBrowser.databaseInfo': 'Database information',
      'databaseBrowser.encoding': 'Encoding',
      'databaseBrowser.size': 'File size',
      'databaseBrowser.newTable': 'New table',
      'databaseBrowser.createTable': 'Create table',
      'databaseBrowser.createTableHelp': 'Create a table with SQLite.',
      'databaseBrowser.createCommand': 'SQLite CREATE command',
      'databaseBrowser.executeSql': 'Run SQLite',
      'databaseBrowser.sqlSuccess': 'SQLite statement executed successfully.',
      'databaseBrowser.content': 'Contents',
      'databaseBrowser.structure': 'Structure',
      'databaseBrowser.rows': '{count} row(s)',
      'databaseBrowser.columnsCount': '{count} column(s)',
      'databaseBrowser.rowRange': 'Rows {start}–{end} of {count}',
      'databaseBrowser.page': 'Page {current} of {total}',
      'databaseBrowser.previous': 'Previous page',
      'databaseBrowser.next': 'Next page',
      'databaseBrowser.simple.title': 'View database',
      'databaseBrowser.simple.search': 'Search tables',
      'databaseBrowser.simple.clearSearch': 'Clear search',
      'databaseBrowser.simple.tables': 'Tables',
      'databaseBrowser.simple.views': 'Views',
      'databaseBrowser.simple.noObjects': 'No tables found.',
      'databaseBrowser.simple.noMatches': 'No matching table found.',
      'databaseBrowser.simple.databaseInfo': 'File information',
      'databaseBrowser.simple.encoding': 'Text format',
      'databaseBrowser.simple.size': 'Storage size',
      'databaseBrowser.simple.table': 'Table',
      'databaseBrowser.simple.view': 'View',
      'databaseBrowser.simple.columnsCount': 'Columns: {count}',
      'databaseBrowser.simple.rows': 'Entries: {count}',
      'databaseBrowser.simple.content': 'Data',
      'databaseBrowser.simple.structure': 'Columns & details',
      'databaseBrowser.simple.noRows': 'This table is empty.',
      'databaseBrowser.simple.rowRange': 'Entries {start}–{end} of {count}',
      'databaseBrowser.simple.page': 'Page {current} of {total}',
      'databaseBrowser.simple.previous': 'Back',
      'databaseBrowser.simple.next': 'Next',
      'databaseBrowser.simple.newTable': 'New table',
      'databaseBrowser.simple.createTable': 'Create a table',
      'databaseBrowser.simple.createTableHelp': 'Define a table visually.',
      'databaseBrowser.simple.tableName': 'Table name',
      'databaseBrowser.simple.defineColumns': 'Columns',
      'databaseBrowser.simple.addColumn': 'Add column',
      'databaseBrowser.simple.columnName': 'Column name',
      'databaseBrowser.simple.type': 'Data type',
      'databaseBrowser.simple.columnNumber': 'Column {number}',
      'databaseBrowser.simple.removeColumn': 'Remove column',
      'databaseBrowser.simple.primaryKeyOption': 'Primary key',
      'databaseBrowser.simple.notNullOption': 'Required',
      'databaseBrowser.simple.uniqueOption': 'Unique',
      'databaseBrowser.simple.preview': 'SQLite preview',
      'databaseBrowser.simple.createTableAction': 'Create table',
      'databaseBrowser.simple.tableNameRequired': 'Enter a table name.',
      'databaseBrowser.simple.columnRequired': 'Name every column.',
      'databaseBrowser.simple.duplicateColumn': 'Duplicate: {name}',
      'databaseBrowser.loadFailed': 'Could not read database: {error}',
      'toolbar.simple': 'Simple',
      'toolbar.advanced': 'Advanced',
      'common.close': 'Close',
    };
    const catalog = TranslationCatalog(
      locale: 'en',
      messages: messages,
      englishMessages: messages,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<SqlExecutionResult> execute(String sql) async {
      final database = sqlite3.open(databasePath);
      try {
        database.execute(sql);
        return const SqlExecutionResult(
          success: true,
          message: 'OK',
          changedDatabase: true,
        );
      } finally {
        database.close();
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DatabaseBrowserDialog(
                  databasePath: databasePath,
                  catalog: catalog,
                  sqlExecutor: execute,
                  overviewLoader: (path) async =>
                      const SqliteDatabaseBrowser().loadOverview(path),
                  objectLoader: (path, name, limit, offset) async =>
                      const SqliteDatabaseBrowser().loadObject(
                        path,
                        name,
                        limit: limit,
                        offset: offset,
                      ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('database-browser-new-table')),
    );
    await tester.pump();
    expect(find.text('SQLite CREATE command'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('database-browser-sql-input')),
      'CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL);',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('database-browser-execute-sql')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('database-object-tasks')),
      findsOneWidget,
    );
    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('database-browser-new-table')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('database-browser-create-table-workspace'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('database-browser-new-table')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('database-browser-simple-create-form')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('database-browser-sql-input')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('database-browser-simple-table-name')),
      'categories',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('database-browser-simple-add-column')),
    );
    await tester.pump();
    final simpleForm = find.byKey(
      const ValueKey<String>('database-browser-simple-create-form'),
    );
    final simpleFormScrollable = find
        .descendant(of: simpleForm, matching: find.byType(Scrollable))
        .first;
    final secondColumnName = find.byKey(
      const ValueKey<String>('database-browser-simple-column-name-1'),
    );
    await tester.scrollUntilVisible(
      secondColumnName,
      180,
      scrollable: simpleFormScrollable,
    );
    await tester.enterText(secondColumnName, 'label');
    final createSimpleTable = find.byKey(
      const ValueKey<String>('database-browser-simple-create-submit'),
    );
    await tester.scrollUntilVisible(
      createSimpleTable,
      220,
      scrollable: simpleFormScrollable,
    );
    await tester.drag(simpleFormScrollable, const Offset(0, -180));
    await tester.pump();
    await tester.tap(createSimpleTable);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('database-object-categories')),
      findsOneWidget,
    );
    final verificationDatabase = sqlite3.open(databasePath);
    addTearDown(verificationDatabase.close);
    final categoryColumns = verificationDatabase.select(
      'PRAGMA table_info("categories")',
    );
    expect(categoryColumns.map((row) => row['name']), <Object?>['id', 'label']);
    expect(categoryColumns.first['pk'], 1);
    expect(categoryColumns.last['type'], 'TEXT');
    expect(categoryColumns.last['notnull'], 0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks object metadata when the detail pane is narrow', (
    tester,
  ) async {
    const object = DatabaseObjectSummary(
      name: 'authors',
      type: DatabaseObjectType.table,
      createSql: 'CREATE TABLE authors (id INTEGER PRIMARY KEY)',
    );
    const overview = DatabaseOverview(
      objects: <DatabaseObjectSummary>[object],
      userVersion: 0,
      applicationId: 0,
      pageSize: 4096,
      pageCount: 1,
      encoding: 'UTF-8',
    );
    const snapshot = DatabaseObjectSnapshot(
      object: object,
      columns: <DatabaseColumnInfo>[
        DatabaseColumnInfo(
          id: 0,
          name: 'id',
          declaredType: 'INTEGER',
          notNull: false,
          defaultSql: null,
          primaryKeyOrder: 1,
          hidden: 0,
        ),
      ],
      foreignKeys: <DatabaseForeignKeyInfo>[],
      indexes: <DatabaseIndexInfo>[],
      columnNames: <String>['id'],
      rows: <List<Object?>>[
        <Object?>[1],
      ],
      totalRowCount: 123456789,
      limit: 100,
      offset: 0,
    );
    const messages = <String, String>{
      'databaseBrowser.title': 'SQLite table browser',
      'databaseBrowser.objectCount': '{count} object(s)',
      'databaseBrowser.refresh': 'Reload database',
      'databaseBrowser.search': 'Search tables or views',
      'databaseBrowser.tables': 'Tables',
      'databaseBrowser.table': 'Table',
      'databaseBrowser.databaseInfo': 'Database information',
      'databaseBrowser.encoding': 'Encoding',
      'databaseBrowser.size': 'File size',
      'databaseBrowser.columnsCount': '{count} column(s)',
      'databaseBrowser.rows': '{count} row(s)',
      'databaseBrowser.content': 'Contents',
      'databaseBrowser.structure': 'Structure',
      'databaseBrowser.rowRange': 'Rows {start}–{end} of {count}',
      'databaseBrowser.page': 'Page {current} of {total}',
      'databaseBrowser.previous': 'Previous page',
      'databaseBrowser.next': 'Next page',
      'databaseBrowser.columns': 'Columns',
      'databaseBrowser.column': 'Column',
      'databaseBrowser.type': 'Type',
      'databaseBrowser.notNull': 'NOT NULL',
      'databaseBrowser.defaultValue': 'DEFAULT',
      'databaseBrowser.primaryKey': 'PRIMARY KEY',
      'databaseBrowser.hidden': 'Hidden / generated',
      'databaseBrowser.createSql': 'Original CREATE SQL',
      'databaseBrowser.copyCreateSql': 'Copy CREATE SQL',
      'toolbar.simple': 'Simple',
      'toolbar.advanced': 'Advanced',
      'common.close': 'Close',
    };
    const catalog = TranslationCatalog(
      locale: 'en',
      messages: messages,
      englishMessages: messages,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DatabaseBrowserDialog(
                  databasePath: databasePath,
                  catalog: catalog,
                  overviewLoader: (_) async => overview,
                  objectLoader: (_, _, _, _) async => snapshot,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('database-object-summary-stacked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('database-browser-pagination-stacked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows table contents and structure in the browser dialog', (
    tester,
  ) async {
    const messages = <String, String>{
      'databaseBrowser.title': 'SQLite table browser',
      'databaseBrowser.refresh': 'Reload database',
      'databaseBrowser.objectCount': '{count} object(s)',
      'databaseBrowser.objects': 'Database objects',
      'databaseBrowser.search': 'Search tables or views',
      'databaseBrowser.clearSearch': 'Clear search',
      'databaseBrowser.noMatches': 'No matching objects found.',
      'databaseBrowser.tables': 'Tables',
      'databaseBrowser.views': 'Views',
      'databaseBrowser.table': 'Table',
      'databaseBrowser.view': 'View',
      'databaseBrowser.noObjects': 'No tables or views found.',
      'databaseBrowser.databaseInfo': 'Database information',
      'databaseBrowser.encoding': 'Encoding',
      'databaseBrowser.size': 'File size',
      'databaseBrowser.content': 'Contents',
      'databaseBrowser.structure': 'Structure',
      'databaseBrowser.rows': '{count} row(s)',
      'databaseBrowser.columnsCount': '{count} column(s)',
      'databaseBrowser.rowRange': 'Rows {start}–{end} of {count}',
      'databaseBrowser.page': 'Page {current} of {total}',
      'databaseBrowser.previous': 'Previous page',
      'databaseBrowser.next': 'Next page',
      'databaseBrowser.noRows': 'No rows found.',
      'databaseBrowser.columns': 'Columns',
      'databaseBrowser.column': 'Column',
      'databaseBrowser.type': 'Type',
      'databaseBrowser.hidden': 'Hidden / generated',
      'databaseBrowser.notNull': 'NOT NULL',
      'databaseBrowser.defaultValue': 'DEFAULT',
      'databaseBrowser.primaryKey': 'PRIMARY KEY',
      'databaseBrowser.foreignKeys': 'Foreign keys',
      'databaseBrowser.indexes': 'Indexes',
      'databaseBrowser.createSql': 'Original CREATE SQL',
      'databaseBrowser.copyCreateSql': 'Copy CREATE SQL',
      'databaseBrowser.createSqlCopied': 'CREATE SQL copied',
      'databaseBrowser.value': 'Full value',
      'databaseBrowser.openValue': 'Open full value',
      'databaseBrowser.simple.title': 'View database',
      'databaseBrowser.simple.search': 'Search tables',
      'databaseBrowser.simple.clearSearch': 'Clear search',
      'databaseBrowser.simple.tables': 'Tables',
      'databaseBrowser.simple.views': 'Views',
      'databaseBrowser.simple.noObjects': 'This database has no tables.',
      'databaseBrowser.simple.noMatches': 'No matching table found.',
      'databaseBrowser.simple.databaseInfo': 'File information',
      'databaseBrowser.simple.encoding': 'Text format',
      'databaseBrowser.simple.size': 'Storage size',
      'databaseBrowser.simple.table': 'Table',
      'databaseBrowser.simple.view': 'View',
      'databaseBrowser.simple.columnsCount': 'Columns: {count}',
      'databaseBrowser.simple.rows': 'Entries: {count}',
      'databaseBrowser.simple.content': 'Data',
      'databaseBrowser.simple.structure': 'Columns & details',
      'databaseBrowser.simple.noRows': 'This table is empty.',
      'databaseBrowser.simple.rowRange': 'Entries {start}–{end} of {count}',
      'databaseBrowser.simple.page': 'Page {current} of {total}',
      'databaseBrowser.simple.previous': 'Back',
      'databaseBrowser.simple.next': 'Next',
      'databaseBrowser.simple.columns': 'Table columns',
      'databaseBrowser.simple.column': 'Name',
      'databaseBrowser.simple.type': 'Data type',
      'databaseBrowser.simple.required': 'Required',
      'databaseBrowser.simple.defaultValue': 'Default value',
      'databaseBrowser.simple.primaryKey': 'Main key',
      'databaseBrowser.simple.hidden': 'Other property',
      'databaseBrowser.simple.foreignKeys': 'Links',
      'databaseBrowser.simple.indexes': 'Search indexes',
      'databaseBrowser.simple.createSql': 'SQL used to create it',
      'databaseBrowser.simple.copyCreateSql': 'Copy SQL',
      'databaseBrowser.simple.createSqlCopied': 'SQL copied',
      'databaseBrowser.loadFailed': 'Could not read database: {error}',
      'toolbar.simple': 'Simple',
      'toolbar.advanced': 'Advanced',
      'common.close': 'Close',
    };
    const catalog = TranslationCatalog(
      locale: 'en',
      messages: messages,
      englishMessages: messages,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SqlAbstractionMode? selectedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DatabaseBrowserDialog(
                  databasePath: databasePath,
                  catalog: catalog,
                  onModeChanged: (mode) => selectedMode = mode,
                  overviewLoader: (path) async =>
                      const SqliteDatabaseBrowser().loadOverview(path),
                  objectLoader: (path, name, limit, offset) async =>
                      const SqliteDatabaseBrowser().loadObject(
                        path,
                        name,
                        limit: limit,
                        offset: offset,
                      ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial Advanced layout');

    expect(
      find.byKey(const ValueKey<String>('database-browser-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('database-browser-header-icon-clip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('database-browser-refresh-clip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('database-browser-close-clip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('database-object-authors-clip')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey<String>('database-object-authors')),
          )
          .borderRadius,
      NodeQlSurfaceStyle.standard.mediumBorderRadius,
    );
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).splashBorderRadius,
      NodeQlSurfaceStyle.standard.innerBorderRadius(
        outerRadius: NodeQlSurfaceStyle.standard.radiusMedium,
        gap: 4,
      ),
    );
    expect(
      tester
          .widget<ClipRRect>(
            find.byKey(
              const ValueKey<String>('database-browser-header-icon-clip'),
            ),
          )
          .borderRadius,
      NodeQlSurfaceStyle.standard.innerBorderRadius(
        outerRadius: NodeQlSurfaceStyle.standard.radiusLarge,
        gap: 14,
      ),
    );
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('1 row(s)'), findsOneWidget);
    expect(find.text('2 column(s)'), findsOneWidget);

    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Simple content layout');
    expect(selectedMode, SqlAbstractionMode.simple);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Entries: 1'), findsOneWidget);
    expect(find.text('Columns: 2'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Columns & details'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('database-browser-content-tab')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('database-browser-structure-tab')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Simple structure layout');
    expect(find.text('Table columns'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Main key'), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Advanced structure layout');
    expect(selectedMode, SqlAbstractionMode.advanced);
    expect(
      find.byKey(const ValueKey<String>('database-browser-content-tab')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('database-browser-search')),
      'book',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('database-object-authors')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('database-object-book details')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('database-object-book details')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'selected table layout');
    expect(find.text('First'), findsOneWidget);
    expect(find.text('NULL'), findsWidgets);
    expect(find.text("X'00FF'"), findsOneWidget);
    expect(find.text('Rows 1–3 of 3'), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('database-browser-structure-tab')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Columns'), findsOneWidget);
    expect(find.text('author_id'), findsOneWidget);
    expect(find.text('PRIMARY KEY'), findsOneWidget);
  });
}
