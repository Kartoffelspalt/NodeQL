import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nodeql/engine/plugins/plugin_data_source_client.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';

void main() {
  final source = PluginDataSourceDefinition.fromJson(
    <String, dynamic>{
      'id': 'bridge',
      'name': 'Bridge',
      'transport': 'http-json',
      'baseUrl': 'https://bridge.example.org',
      'schemaPath': '/schema',
      'queryPath': '/query',
      'secrets': <String>['TOKEN'],
    },
    allowedHosts: <String>{'bridge.example.org'},
    declaredSecrets: <String>{'TOKEN'},
  );

  test('sends the stable JSON bridge query contract', () async {
    final client = PluginDataSourceClient(
      client: MockClient((request) async {
        expect(request.url.path, '/query');
        expect(request.headers['x-nodeql-secret-TOKEN'], 'secret');
        expect(jsonDecode(request.body), <String, dynamic>{
          'query': 'find users',
          'parameters': <String, dynamic>{'limit': 10},
        });
        return http.Response(
          jsonEncode(<String, dynamic>{
            'rows': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'Ada'},
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.execute(
      source,
      query: 'find users',
      parameters: <String, Object?>{'limit': 10},
      secrets: <String, String>{'TOKEN': 'secret'},
    );

    expect(response['rows'], isNotEmpty);
  });

  test('requires every declared secret', () {
    final client = PluginDataSourceClient(
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(() => client.loadSchema(source), throwsA(isA<StateError>()));
  });
}
