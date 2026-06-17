import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/app/nodeql_app.dart';
import 'package:nodeql/features/workbench/presentation/workbench_page.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_models.dart';
import 'package:nodeql/localization/translation_repository.dart';
import 'package:nodeql/localization/translation_controller.dart';

void main() {
  testWidgets('renders localized workspace shell', (tester) async {
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
    expect(find.text('SQL-Command Output'), findsOneWidget);
  });

  testWidgets('opens block snap diagnostics from the top bar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 800));
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

    await tester.tap(find.byKey(const ValueKey('open-block-tests')));
    await tester.pumpAndSettle();

    expect(find.text('Block-Tests'), findsOneWidget);
    expect(find.textContaining('Geprüft:'), findsOneWidget);
    expect(find.text('Erlaubte Snap-Konstellationen'), findsOneWidget);
    expect(find.text('Live-Test starten'), findsOneWidget);
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
      'toolbar.runSql': 'Run SQL',
      'toolbar.simple': 'Simple',
      'toolbar.advanced': 'Advanced',
      'toolbar.settings': 'Settings',
      'palette.search': 'Search command',
      'palette.category.dql': 'Query data',
      'runtime.sqlOutput': '-- SQL output --',
      'runtime.sqlCommandOutput': 'SQL-Command Output',
      'runtime.copySql': 'Copy SQL',
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
