import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/app/nodeql_app.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/features/workbench/presentation/workbench_page.dart';
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
        ],
        child: const NodeQlApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));

    expect(find.byType(WorkbenchPage), findsOneWidget);
    expect(find.text('NodeQL'), findsOneWidget);
    expect(find.text('SQLite-Command Output'), findsOneWidget);

    final connectionTool = find.byKey(const ValueKey('column-link-tool'));
    expect(connectionTool, findsOneWidget);
    expect(tester.widget<IconButton>(connectionTool).isSelected, isFalse);
    await tester.tap(connectionTool);
    await tester.pump();
    expect(tester.widget<IconButton>(connectionTool).isSelected, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkbenchPage)),
    );
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
  });
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
      'palette.search': 'Search command',
      'palette.category.dql': 'Query data',
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
