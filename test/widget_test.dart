import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nodeql/core/app/nodeql_app.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/features/workbench/presentation/engine/plugin_registry.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_tabs.dart';
import 'package:nodeql/features/workbench/presentation/workbench_page.dart';
import 'package:nodeql/features/workbench/presentation/widgets/block_shape_painter.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_models.dart';
import 'package:nodeql/localization/translation_repository.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('renders localized workspace shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationControllerProvider.overrideWith(
            (_) => _ReadyTranslationController(),
          ),
          pluginPaletteProvider.overrideWith(
            (_) => _ReadyPluginPaletteController(),
          ),
        ],
        child: const NodeQlApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));

    expect(find.byType(WorkbenchPage), findsOneWidget);
    expect(find.text('NodeQL'), findsOneWidget);
    expect(find.text('SQLite-Command Output'), findsOneWidget);
    expect(find.text('Query Language'), findsOneWidget);
    expect(find.text('Query 1'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/appicon/iconv4dark.png',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('workspace-tab-rename-query_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('workspace-tab-rename-field')),
      'Customer report',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('workspace-tab-rename-submit')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Customer report'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('workspace-tab-add')));
    await tester.pumpAndSettle();
    expect(find.text('Query 2'), findsOneWidget);

    final paletteSearch = find.byType(TextField).first;
    await tester.enterText(paletteSearch, 'sqlSubqueryIn');
    await tester.pump();
    expect(
      find.text(
        'Checks whether a value matches any value returned by a subquery.',
      ),
      findsOneWidget,
    );
    await tester.enterText(paletteSearch, 'sqlCreateIndex');
    await tester.pump();
    expect(
      find.text('Creates an optionally unique index over one or more columns.'),
      findsOneWidget,
    );
    await tester.enterText(paletteSearch, '');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pumpAndSettle();
    expect(find.text('SQLite data types'), findsOneWidget);
    expect(
      find.text('The SQLite NULL value: no value or an unknown value.'),
      findsOneWidget,
    );

    final connectionTool = find.byKey(const ValueKey('column-link-tool'));
    expect(connectionTool, findsOneWidget);
    expect(tester.widget<IconButton>(connectionTool).isSelected, isFalse);
    await tester.tap(connectionTool);
    await tester.pump();
    expect(tester.widget<IconButton>(connectionTool).isSelected, isTrue);

    await tester.tap(connectionTool);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkbenchPage)),
    );
    expect(
      find.byKey(const ValueKey<String>('open-database-browser')),
      findsNothing,
    );
    final browserDirectory = Directory.systemTemp.createTempSync(
      'nodeql_dbb_shortcut',
    );
    addTearDown(() => browserDirectory.deleteSync(recursive: true));
    final browserDatabasePath =
        '${browserDirectory.path}${Platform.pathSeparator}shortcut.db';
    final browserDatabase = sqlite3.open(browserDatabasePath);
    browserDatabase.execute('''
      CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);
      INSERT INTO notes (body) VALUES ('Shortcut works');
    ''');
    browserDatabase.close();
    await tester.runAsync(
      () => container
          .read(sqlRuntimeProvider.notifier)
          .attachDatabasePath(browserDatabasePath),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('open-database-browser')),
      findsNothing,
    );

    final customSqlButton = find.byKey(
      const ValueKey<String>('toggle-custom-sql'),
    );
    expect(tester.widget<IconButton>(customSqlButton).onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey<String>('custom-sql-input')),
      findsNothing,
    );
    await tester.tap(customSqlButton);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('custom-sql-input')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('sql-ide-pane')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('full-output-preview')),
      findsOneWidget,
    );
    expect(find.text('Output preview'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('open-database-browser')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey<String>('close-sql-ide')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('custom-sql-input')),
      findsNothing,
    );

    await tester.tap(paletteSearch);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('database-browser-dialog')),
      findsNothing,
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey<String>('database-browser-dialog')),
      findsOneWidget,
    );
    final databaseBrowserClip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey<String>('database-browser-surface-clip')),
    );
    expect(
      databaseBrowserClip.borderRadius,
      NodeQlSurfaceStyle.standard.largeBorderRadius,
    );
    final databaseBrowserDialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(databaseBrowserDialog.backgroundColor, Colors.transparent);
    expect(databaseBrowserDialog.elevation, 0);
    expect(databaseBrowserDialog.shadowColor, Colors.transparent);
    final databaseBrowserBackground = tester.widget<Material>(
      find.byKey(const ValueKey<String>('database-browser-surface-background')),
    );
    final databaseBrowserBackgroundColor = databaseBrowserBackground.color;
    expect(databaseBrowserBackgroundColor, isNotNull);
    expect(databaseBrowserBackgroundColor!.a, 1);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey<String>('database-browser-dialog')),
      findsNothing,
    );

    final workspaceController = container.read(workspaceProvider.notifier);
    workspaceController.addTemplate(
      BlockType.sqlSelect,
      workspaceController.suggestedTemplatePosition(BlockType.sqlSelect),
    );
    workspaceController.addTemplate(
      BlockType.sqlOrderBy,
      workspaceController.suggestedTemplatePosition(BlockType.sqlOrderBy),
    );
    final select = workspaceController.allBlocks().firstWhere(
      (node) => node.type == BlockType.sqlSelect,
    );
    final order = workspaceController.allBlocks().firstWhere(
      (node) => node.type == BlockType.sqlOrderBy,
    );
    expect(
      workspaceController.connectColumnSource(select.id, order.id),
      isTrue,
    );
    expect(workspaceController.selectColumnLink(order.id), isTrue);
    await tester.pump();
    final sourceShape = tester
        .widgetList<BlockShape>(find.byType(BlockShape))
        .firstWhere((shape) => shape.node.id == select.id);
    final targetShape = tester
        .widgetList<BlockShape>(find.byType(BlockShape))
        .firstWhere((shape) => shape.node.id == order.id);
    expect(sourceShape.isSelected, isTrue);
    expect(sourceShape.selectedOutlineColor, const Color(0xFF8ADFFF));
    expect(sourceShape.selectedOutlineHaloColor, const Color(0xD9FFFFFF));
    expect(targetShape.isSelected, isTrue);
    expect(targetShape.selectedOutlineColor, const Color(0xFFFFC078));
    expect(targetShape.selectedOutlineHaloColor, const Color(0xD9FFFFFF));
    expect(
      find.byKey(const ValueKey<String>('column-link-manager')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('column-link-manager-close')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('column-link-manager')),
      findsNothing,
    );
    workspaceController.selectColumnLink(order.id);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('column-link-delete')));
    await tester.pump();
    expect(workspaceController.columnLinks(), isEmpty);

    expect(container.read(nodeQlThemeProvider).theme, NodeQlTheme.dark);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    final settingsClip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey<String>('settings-dialog-surface-clip')),
    );
    expect(
      settingsClip.borderRadius,
      NodeQlSurfaceStyle.standard.largeBorderRadius,
    );
    final settingsSurface = find.byKey(
      const ValueKey<String>('settings-dialog-surface-clip'),
    );
    expect(tester.getSize(settingsSurface).width, lessThanOrEqualTo(380));
    expect(tester.getCenter(settingsSurface).dx, closeTo(800, 1));
    expect(tester.getTopLeft(settingsSurface).dx, greaterThan(40));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RadioListTile<NodeQlTheme> &&
            widget.value == NodeQlTheme.neoBrutalism,
      ),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField).first;
    await tester.tap(searchField);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pump();
    expect(container.read(nodeQlThemeProvider).theme, NodeQlTheme.dark);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();

    expect(container.read(nodeQlThemeProvider).theme, NodeQlTheme.neoBrutalism);

    final activeTabId = container.read(workspaceTabsProvider).activeTabId;
    final brutalRenameButton = tester.widget<IconButton>(
      find.byKey(ValueKey<String>('workspace-tab-rename-$activeTabId')),
    );
    expect(
      brutalRenameButton.style?.fixedSize?.resolve(<WidgetState>{}),
      const Size.square(32),
    );
    expect(
      brutalRenameButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      NodeQlNeoBrutalism.ink,
    );
    expect(
      brutalRenameButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      NodeQlNeoBrutalism.yellow,
    );
    expect(
      brutalRenameButton.style?.side?.resolve(<WidgetState>{})?.width,
      NodeQlNeoBrutalism.borderWidth,
    );
    expect(
      brutalRenameButton.style?.shape?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'nested workspace tab action radius',
        BorderRadius.circular(
          NodeQlSurfaceStyle.neoBrutalism.innerRadius(
            outerRadius: NodeQlSurfaceStyle.neoBrutalism.radiusSmall,
            gap: 4,
          ),
        ),
      ),
    );

    expect(
      workspaceController.connectColumnSource(select.id, order.id),
      isTrue,
    );
    expect(workspaceController.selectColumnLink(order.id), isTrue);
    await tester.pump();
    final lightSourceShape = tester
        .widgetList<BlockShape>(find.byType(BlockShape))
        .firstWhere((shape) => shape.node.id == select.id);
    final lightTargetShape = tester
        .widgetList<BlockShape>(find.byType(BlockShape))
        .firstWhere((shape) => shape.node.id == order.id);
    expect(lightSourceShape.selectedOutlineColor, const Color(0xFF38BDF8));
    expect(lightSourceShape.selectedOutlineHaloColor, const Color(0xB8000000));
    expect(lightTargetShape.selectedOutlineColor, const Color(0xFFF97316));
    expect(lightTargetShape.selectedOutlineHaloColor, const Color(0xB8000000));
    workspaceController.deleteSelectedColumnLink();
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('run-sqlite')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(NodeQlSurfaceStyle.neoBrutalism.radiusMedium),
      ),
    );

    expect(find.text('No Alias'), findsOneWidget);
    await tester.tap(find.text('No Alias'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('table-alias-submit')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(NodeQlSurfaceStyle.neoBrutalism.radiusMedium),
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('settings-manage-plugins')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(NodeQlSurfaceStyle.neoBrutalism.radiusMedium),
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('settings-manage-plugins')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('settings-languages')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(NodeQlSurfaceStyle.neoBrutalism.radiusMedium),
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('settings-languages')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Manage Plugins'));
    await tester.pumpAndSettle();
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('install-plugin-manifest')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(NodeQlSurfaceStyle.neoBrutalism.radiusMedium),
      ),
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About NodeQL and licenses'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/appicon/iconv4dark.png',
      ),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('settings-tutorial')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(NodeQlSurfaceStyle.neoBrutalism.radiusMedium),
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('settings-tutorial')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Start interactive tutorial'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TutorialDialog), findsOneWidget);
  });

  testWidgets('deletes a workspace tab after confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationControllerProvider.overrideWith(
            (_) => _ReadyTranslationController(),
          ),
          pluginPaletteProvider.overrideWith(
            (_) => _ReadyPluginPaletteController(),
          ),
        ],
        child: const NodeQlApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkbenchPage)),
    );
    final tabs = container.read(workspaceTabsProvider.notifier);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('workspace-tab-delete-query_1')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey<String>('workspace-tab-add')));
    await tester.pumpAndSettle();
    final disposableId = tabs.state.activeTabId;
    expect(tabs.state.tabs, hasLength(2));
    expect(
      tester
          .widget<IconButton>(
            find.byKey(ValueKey<String>('workspace-tab-delete-$disposableId')),
          )
          .onPressed,
      isNotNull,
    );
    final deleteButton = find.byKey(
      ValueKey<String>('workspace-tab-delete-$disposableId'),
    );
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete workspace?'), findsOneWidget);
    expect(
      find.text(
        'The workspace "Query 2" and all of its contents will be permanently deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('workspace-tab-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(tabs.state.tabs, hasLength(1));
    expect(tabs.state.activeTabId, 'query_1');
    expect(
      find.byKey(ValueKey<String>('workspace-tab-$disposableId')),
      findsNothing,
    );
  });
}

class _ReadyPluginPaletteController extends PluginPaletteController {
  _ReadyPluginPaletteController()
    : super(httpClient: MockClient((_) async => http.Response('', 200)));

  @override
  Future<void> reload() async {
    state = const PluginPaletteState();
  }
}

class _ReadyTranslationController extends TranslationController {
  _ReadyTranslationController()
    : super(
        _WidgetTestTranslationRepository(),
        appVersion: () async => '1.0.0',
      ) {
    const messages = {
      'app.name': 'NodeQL',
      'toolbar.mountDatabase': 'Mount .db',
      'toolbar.runSql': 'Run SQLite',
      'toolbar.connectColumns': 'Connect column sources',
      'toolbar.simple': 'Simple',
      'toolbar.advanced': 'Advanced',
      'toolbar.settings': 'Settings',
      'workspace.rope.title': 'Selected rope',
      'workspace.rope.source': 'Source',
      'workspace.rope.target': 'Target',
      'workspace.rope.delete': 'Delete rope',
      'settings.title': 'Settings',
      'settings.plugins': 'Manage Plugins',
      'settings.languages': 'Manage Languages',
      'settings.tutorial': 'Start interactive tutorial',
      'settings.about': 'About NodeQL and licenses',
      'plugins.title': 'Plugins',
      'plugins.installedTab': 'Installed',
      'plugins.repositoriesTab': 'Repositories',
      'plugins.reload': 'Reload',
      'plugins.install': 'Install',
      'common.close': 'Close',
      'tabs.add': 'Create query tab',
      'tabs.executionOrder': 'Query execution order',
      'tabs.dragToReorder': 'Drag to change execution order',
      'tabs.defaultName': 'Query {number}',
      'tabs.rename': 'Rename tab',
      'tabs.renameTitle': 'Rename query tab',
      'tabs.name': 'Tab name',
      'tabs.delete': 'Delete workspace',
      'tabs.deleteTitle': 'Delete workspace?',
      'tabs.deleteMessage':
          'The workspace "{name}" and all of its contents will be permanently deleted.',
      'tabs.deleteLastDisabled': 'The last workspace cannot be deleted.',
      'common.cancel': 'Cancel',
      'common.delete': 'Delete',
      'palette.search': 'Search command',
      'palette.category.dql': 'Query data',
      'palette.category.queryLanguage': 'Query Language',
      'palette.category.dataTypes': 'SQLite data types',
      'palette.rail.queryLanguage': 'Query Language',
      'palette.rail.dataTypes': 'SQLite data types',
      'runtime.sqlOutput': '-- SQLite output --',
      'runtime.sqlCommandOutput': 'SQLite-Command Output',
      'runtime.customSql': 'Custom SQLite',
      'runtime.customSqlHint': 'Write SQLite directly',
      'runtime.localCompletion': 'Local smart completion',
      'runtime.ideTitle': 'SQLite editor',
      'runtime.ideSubtitle': 'Write and run SQLite with schema completion',
      'runtime.outputPreview': 'Output preview',
      'runtime.showNodeWorkspace': 'Show visual node workspace',
      'runtime.showGeneratedSql': 'Show generated SQLite',
      'runtime.runCustomSql': 'Run custom SQLite',
      'runtime.copySql': 'Copy SQLite',
      'runtime.noResults': 'No results',
    };
    state = const TranslationState(
      loading: false,
      catalog: TranslationCatalog(
        locale: 'en',
        messages: messages,
        englishMessages: messages,
      ),
    );
  }

  @override
  Future<void> initialize() async {}
}

class _WidgetTestTranslationRepository implements TranslationRepository {
  @override
  Future<TranslationManifest> fetchManifest() async => TranslationManifest(
    generatedAt: DateTime.utc(2026, 6, 14),
    minimumAppVersion: '0.1.0',
    languages: const [],
  );

  @override
  Future<TranslationPackage> install(TranslationLanguage language) {
    throw UnimplementedError();
  }

  @override
  Future<List<TranslationPackage>> loadCachedPackages() async => const [];

  @override
  Future<Map<String, String>> loadEnglishMessages() async => const {};

  @override
  Future<void> remove(String locale) async {}
}
