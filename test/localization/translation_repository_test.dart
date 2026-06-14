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
