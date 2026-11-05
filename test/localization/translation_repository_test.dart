import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nodeql/localization/translation_models.dart';
import 'package:nodeql/localization/translation_repository.dart';

void main() {
  late Directory support;
  late List<int> packageBytes;
  late String englishAsset;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('nodeql-translations-');
    englishAsset = jsonEncode({
      'schemaVersion': 1,
      'locale': 'en',
      'revision': 1,
      'messages': {'plain': 'Hello', 'welcome': 'Hello {name}'},
    });
    packageBytes = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'locale': 'de',
        'revision': 2,
        'messages': {'plain': 'Hallo', 'welcome': 'Hallo {name}'},
      }),
    );
  });

  tearDown(() async {
    if (await support.exists()) await support.delete(recursive: true);
  });

  test(
    'loads bundled release languages offline before a cache exists',
    () async {
      final assets = bundledAssets(englishAsset, {'de': packageBytes});
      final repository = FileTranslationRepository(
        client: MockClient((_) async => throw StateError('Must work offline')),
        supportDirectory: () async => support,
        assetLoader: (key) async => assets[key]!,
      );
      final packages = await repository.loadCachedPackages();
      expect(packages.single.locale, 'de');
      expect(packages.single.messages['welcome'], 'Hallo {name}');
      expect(packages.single.isBundled, isTrue);
    },
  );

  test(
    'newer bundles replace stale cached translations, newer downloads win',
    () async {
      final assets = bundledAssets(englishAsset, {'de': packageBytes});
      final cache = File('${support.path}/nodeql_translations/de.json');
      await cache.parent.create(recursive: true);
      Future<void> cachedRevision(int revision) => cache.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'locale': 'de',
          'revision': revision,
          'messages': {'plain': 'Cached'},
        }),
      );
      final repository = FileTranslationRepository(
        supportDirectory: () async => support,
        assetLoader: (key) async => assets[key]!,
      );
      await cachedRevision(1);
      expect(
        (await repository.loadCachedPackages()).single.messages['plain'],
        'Hallo',
      );
      await cachedRevision(3);
      final newer = (await repository.loadCachedPackages()).single;
      expect(newer.messages['plain'], 'Cached');
      expect(newer.isBundled, isTrue);
    },
  );

  test(
    'one missing bundled package does not hide the remaining packages',
    () async {
      final french = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'locale': 'fr',
          'revision': 2,
          'messages': {'plain': 'Bonjour'},
        }),
      );
      final assets = bundledAssets(englishAsset, {
        'de': packageBytes,
        'fr': french,
      });
      assets.remove('assets/translations/de.json');
      final repository = FileTranslationRepository(
        supportDirectory: () async => support,
        assetLoader: (key) async => assets[key]!,
      );
      expect((await repository.loadCachedPackages()).single.locale, 'fr');
    },
  );

  test('downloads, verifies, caches, and reloads a language package', () async {
    final hash = sha256.convert(packageBytes).toString();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('manifest.json')) {
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'generatedAt': '2026-06-14T12:00:00Z',
            'minimumAppVersion': '0.1.0',
            'languages': [
              {
                'locale': 'de',
                'nativeName': 'Deutsch',
                'direction': 'ltr',
                'revision': 2,
                'completion': 100,
                'downloadUrl': 'https://translations.example.com/de.json',
                'sha256': hash,
                'size': packageBytes.length,
              },
            ],
          }),
          200,
        );
      }
      return http.Response.bytes(packageBytes, 200);
    });
    final repository = FileTranslationRepository(
      client: client,
      manifestUri: Uri.parse('https://translations.example.com/manifest.json'),
      allowedHosts: const {'translations.example.com'},
      supportDirectory: () async => support,
      assetLoader: (_) async => englishAsset,
    );

    final manifest = await repository.fetchManifest();
    final installed = await repository.install(manifest.languages.single);
    final cached = await repository.loadCachedPackages();

    expect(installed.revision, 2);
    expect(cached.single.messages['plain'], 'Hallo');
  });

  test('rejects non-HTTPS and unapproved hosts', () async {
    final repository = FileTranslationRepository(
      client: MockClient((_) async => http.Response('{}', 200)),
      manifestUri: Uri.parse('http://translations.example.com/manifest.json'),
      allowedHosts: const {'translations.example.com'},
      supportDirectory: () async => support,
      assetLoader: (_) async => englishAsset,
    );
    expect(repository.fetchManifest, throwsFormatException);

    final wrongHost = FileTranslationRepository(
      client: MockClient((_) async => http.Response('{}', 200)),
      manifestUri: Uri.parse('https://example.com/manifest.json'),
      supportDirectory: () async => support,
      assetLoader: (_) async => englishAsset,
    );
    expect(wrongHost.fetchManifest, throwsFormatException);
  });

  test('rejects a package with a mismatched hash', () async {
    final repository = FileTranslationRepository(
      client: MockClient((_) async => http.Response.bytes(packageBytes, 200)),
      allowedHosts: const {'translations.example.com'},
      supportDirectory: () async => support,
      assetLoader: (_) async => englishAsset,
    );
    final language = (TranslationManifest.fromBytes(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'generatedAt': '2026-06-14T12:00:00Z',
          'minimumAppVersion': '0.1.0',
          'languages': [
            {
              'locale': 'de',
              'nativeName': 'Deutsch',
              'direction': 'ltr',
              'revision': 2,
              'completion': 100,
              'downloadUrl': 'https://translations.example.com/de.json',
              'sha256': List.filled(64, '0').join(),
              'size': packageBytes.length,
            },
          ],
        }),
      ),
    )).languages.single;

    expect(() => repository.install(language), throwsFormatException);
  });
}

Map<String, String> bundledAssets(
  String english,
  Map<String, List<int>> packages,
) => {
  'assets/translations/en.json': english,
  for (final entry in packages.entries)
    'assets/translations/${entry.key}.json': utf8.decode(entry.value),
  'assets/translations/translation-manifest.json': jsonEncode({
    'schemaVersion': 1,
    'generatedAt': '2026-11-05T12:00:00Z',
    'minimumAppVersion': '0.1.0',
    'languages': [
      for (final entry in packages.entries)
        {
          'locale': entry.key,
          'nativeName': entry.key,
          'direction': 'ltr',
          'revision': 2,
          'completion': 100,
          'downloadUrl':
              'https://kartoffelspalt.github.io/NodeQL/translations/${entry.key}.json',
          'sha256': sha256.convert(entry.value).toString(),
          'size': entry.value.length,
        },
    ],
  }),
};
