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
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/features/workbench/presentation/workbench_page.dart';
import 'package:nodeql/features/workbench/presentation/widgets/block_shape_painter.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_models.dart';
import 'package:nodeql/localization/translation_repository.dart';
import 'package:nodeql/localization/translation_controller.dart';

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
      findsNothing,
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
      isA<StadiumBorder>(),
    );
    expect(
      tester
          .widget<ClipRRect>(
            find.ancestor(
              of: find.byKey(const ValueKey<String>('settings-manage-plugins')),
              matching: find.byType(ClipRRect),
            ),
          )
          .borderRadius,
      BorderRadius.circular(999),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('settings-languages')),
          )
          .style
          ?.shape
          ?.resolve(<WidgetState>{}),
      isA<StadiumBorder>(),
    );
    expect(
      tester
          .widget<ClipRRect>(
            find.ancestor(
              of: find.byKey(const ValueKey<String>('settings-languages')),
              matching: find.byType(ClipRRect),
            ),
          )
          .borderRadius,
      BorderRadius.circular(999),
    );
    await tester.tap(find.text('Manage Plugins'));
    await tester.pumpAndSettle();
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
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
      isA<StadiumBorder>(),
    );
    expect(
      tester
          .widget<ClipRRect>(
            find.ancestor(
              of: find.byKey(const ValueKey<String>('settings-tutorial')),
              matching: find.byType(ClipRRect),
            ),
          )
          .borderRadius,
      BorderRadius.circular(999),
    );
    await tester.tap(find.text('Start interactive tutorial'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TutorialDialog), findsOneWidget);
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
      'palette.search': 'Search command',
      'palette.category.dql': 'Query data',
      'palette.category.queryLanguage': 'Query Language',
      'palette.category.dataTypes': 'SQLite data types',
      'palette.rail.queryLanguage': 'Query Language',
      'palette.rail.dataTypes': 'SQLite data types',
      'runtime.sqlOutput': '-- SQLite output --',
      'runtime.sqlCommandOutput': 'SQLite-Command Output',
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
