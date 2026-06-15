import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/plugins/plugin_repository.dart';

void main() {
  test('parses a SHA-256 protected plugin repository catalog', () {
    final catalog = PluginRepositoryCatalog.fromBytes(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'name': 'Community',
          'plugins': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'org.example.mongo',
              'name': 'MongoDB Bridge',
              'version': '2.0.0',
              'description': 'Community adapter',
              'manifestUrl': 'plugins/mongo.json',
              'sha256': 'a' * 64,
            },
          ],
        }),
      ),
      repositoryUrl: Uri.parse('https://plugins.example.org/catalog.json'),
    );

    expect(catalog.name, 'Community');
    expect(
      catalog.entries.single.manifestUrl.toString(),
      'https://plugins.example.org/plugins/mongo.json',
    );
  });

  test('rejects insecure remote repositories and invalid hashes', () {
    expect(
      () => validatePluginRepositoryUrl('http://plugins.example.org/list.json'),
      throwsFormatException,
    );
    expect(
      validatePluginRepositoryUrl('http://localhost:8080/list.json').host,
      'localhost',
    );
    expect(
      () => PluginRepositoryCatalog.fromBytes(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'schemaVersion': 1,
            'name': 'Broken',
            'plugins': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'org.example.broken',
                'name': 'Broken',
                'version': '1.0.0',
                'manifestUrl': 'https://example.org/plugin.json',
                'sha256': 'invalid',
              },
            ],
          }),
        ),
        repositoryUrl: Uri.parse('https://example.org/catalog.json'),
      ),
      throwsFormatException,
    );
  });

  test('repository documentation example is parseable', () {
    final file = File('docs/plugins/examples/repository.catalog.json');
    final catalog = PluginRepositoryCatalog.fromBytes(
      file.readAsBytesSync(),
      repositoryUrl: Uri.parse(
        'https://plugins.example.org/repository.catalog.json',
      ),
    );

    expect(catalog.entries.single.id, 'org.example.external-data');
    expect(catalog.entries.single.sha256, hasLength(64));
  });
}
