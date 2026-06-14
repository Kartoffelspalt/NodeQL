import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:nodeql/localization/translation_models.dart';
import 'package:nodeql/localization/translation_repository.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nodeql-locale-controller-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'loads cached locale, falls back to English, and persists selection',
    () async {
      final repository = _FakeTranslationRepository(
        cached: const [
          TranslationPackage(
            locale: 'de',
            revision: 1,
            messages: {'plain': 'Hallo'},
          ),
        ],
      );
      final settings = File('${temp.path}/locale.json');
      final controller = TranslationController(
        repository,
        settingsFile: () async => settings,
        appVersion: () async => '1.0.0',
      );
      await _waitUntilReady(controller);

      await controller.setLocaleTag('de');
      expect(controller.state.catalog.text('plain'), 'Hallo');
      expect(controller.state.catalog.text('missing'), 'missing');
      expect(await settings.readAsString(), contains('"locale":"de"'));

      await controller.remove('de');
      expect(controller.state.locale.languageCode, 'en');
      expect(controller.state.catalog.text('plain'), 'Hello');
    },
  );

  test('keeps cached state when manifest refresh fails', () async {
    final repository = _FakeTranslationRepository(
      fetchError: StateError('offline'),
    );
    final controller = TranslationController(
      repository,
      settingsFile: () async => File('${temp.path}/locale.json'),
      appVersion: () async => '1.0.0',
    );
    await _waitUntilReady(controller);

    await controller.refreshManifest();

    expect(controller.state.catalog.text('plain'), 'Hello');
    expect(controller.state.error, contains('offline'));
  });

  test('rejects a manifest requiring a newer app', () async {
    final repository = _FakeTranslationRepository(
      manifest: TranslationManifest(
        generatedAt: DateTime.utc(2026, 6, 14),
        minimumAppVersion: '2.0.0',
        languages: const [],
      ),
    );
    final controller = TranslationController(
      repository,
      settingsFile: () async => File('${temp.path}/locale.json'),
      appVersion: () async => '1.0.0',
    );
    await _waitUntilReady(controller);

    await controller.refreshManifest();

    expect(controller.state.available, isEmpty);
    expect(controller.state.error, contains('2.0.0'));
  });
}

Future<void> _waitUntilReady(TranslationController controller) async {
  for (var attempt = 0; attempt < 100 && controller.state.loading; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(controller.state.loading, isFalse);
}

class _FakeTranslationRepository implements TranslationRepository {
  _FakeTranslationRepository({
    this.cached = const [],
    this.manifest,
    this.fetchError,
  });

  final List<TranslationPackage> cached;
  final TranslationManifest? manifest;
  final Object? fetchError;

  @override
  Future<TranslationManifest> fetchManifest() async {
    if (fetchError != null) throw fetchError!;
    return manifest ??
        TranslationManifest(
          generatedAt: DateTime.utc(2026, 6, 14),
          minimumAppVersion: '0.1.0',
          languages: const [],
        );
  }

  @override
  Future<TranslationPackage> install(TranslationLanguage language) {
    throw UnimplementedError();
  }

  @override
  Future<List<TranslationPackage>> loadCachedPackages() async => cached;

  @override
  Future<Map<String, String>> loadEnglishMessages() async => const {
    'plain': 'Hello',
  };

  @override
  Future<void> remove(String locale) async {}
}
