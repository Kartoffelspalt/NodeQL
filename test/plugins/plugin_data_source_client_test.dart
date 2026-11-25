import 'dart:convert';
import 'dart:io';

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

  for (final endpoint in <String>[
    '//attacker.example/collect',
    '///attacker.example/collect',
    r'/\attacker.example/collect',
    'https://attacker.example/collect',
    'http://bridge.example.org/collect',
    '//bridge.example.org:8443/collect',
  ]) {
    test('rejects unchecked endpoint $endpoint before sending', () async {
      var requests = 0;
      final client = PluginDataSourceClient(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      final unchecked = _source(source.baseUrl, path: endpoint);

      await expectLater(
        client.loadSchema(
          unchecked,
          secrets: <String, String>{'TOKEN': 'secret'},
        ),
        throwsFormatException,
      );
      await expectLater(
        client.execute(
          unchecked,
          query: 'private query',
          secrets: <String, String>{'TOKEN': 'secret'},
        ),
        throwsFormatException,
      );
      expect(requests, 0);
    });
  }

  test('rejects non-local HTTP base URLs supplied directly', () async {
    final client = PluginDataSourceClient(
      client: MockClient((_) async => fail('Unsafe request was sent')),
    );
    final unchecked = _source(Uri.parse('http://bridge.example.org'));

    await expectLater(
      client.loadSchema(
        unchecked,
        secrets: <String, String>{'TOKEN': 'secret'},
      ),
      throwsFormatException,
    );
    await expectLater(
      client.execute(
        unchecked,
        query: 'private query',
        secrets: <String, String>{'TOKEN': 'secret'},
      ),
      throwsFormatException,
    );
  });

  for (final base in <String>[
    'https://bridge.example.org:8443/base/',
    'http://localhost:8080/base/',
    'http://127.0.0.1:8080/base/',
    'http://[::1]:8080/base/',
  ]) {
    test('preserves safe paths and request contracts for $base', () async {
      final baseUrl = Uri.parse(base);
      final safeSource = _source(baseUrl, path: '/%2F%2Fdata?limit=10');
      final methods = <String>[];
      final client = PluginDataSourceClient(
        client: MockClient((request) async {
          methods.add(request.method);
          expect(request.url.origin, baseUrl.origin);
          expect(request.url.path, '/%2F%2Fdata');
          expect(request.url.queryParameters, <String, String>{'limit': '10'});
          expect(request.followRedirects, isFalse);
          expect(request.headers['x-nodeql-secret-TOKEN'], 'secret');
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), <String, dynamic>{
              'query': 'find users',
              'parameters': <String, dynamic>{'limit': 10},
            });
            expect(request.headers['content-type'], 'application/json');
          }
          return http.Response('{}', 200);
        }),
      );

      await client.loadSchema(
        safeSource,
        secrets: <String, String>{'TOKEN': 'secret'},
      );
      await client.execute(
        safeSource,
        query: 'find users',
        parameters: <String, Object?>{'limit': 10},
        secrets: <String, String>{'TOKEN': 'secret'},
      );
      expect(methods, <String>['GET', 'POST']);
    });
  }

  for (final status in <int>[301, 302, 303, 307, 308]) {
    test('does not forward secrets or queries through HTTP $status', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final transport = http.Client();
      addTearDown(() async {
        transport.close();
        await origin.close(force: true);
        await destination.close(force: true);
      });
      var destinationRequests = 0;
      destination.listen((request) async {
        destinationRequests++;
        request.response.write('{}');
        await request.response.close();
      });
      final originMethods = <String>[];
      origin.listen((request) async {
        originMethods.add(request.method);
        await request.drain<void>();
        request.response
          ..statusCode = status
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://localhost:${destination.port}/collect',
          );
        await request.response.close();
      });
      final client = PluginDataSourceClient(client: transport);
      final localSource = _source(Uri.parse('http://127.0.0.1:${origin.port}'));

      await expectLater(
        client.loadSchema(
          localSource,
          secrets: <String, String>{'TOKEN': 'secret'},
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        client.execute(
          localSource,
          query: 'private query',
          secrets: <String, String>{'TOKEN': 'secret'},
        ),
        throwsA(isA<StateError>()),
      );
      expect(originMethods, <String>['GET', 'POST']);
      expect(destinationRequests, 0);
    });
  }
}

PluginDataSourceDefinition _source(Uri baseUrl, {String path = '/data'}) {
  return PluginDataSourceDefinition(
    id: 'bridge',
    name: const <String, String>{'en': 'Bridge'},
    description: const <String, String>{},
    transport: PluginDataSourceTransport.httpJson,
    baseUrl: baseUrl,
    schemaPath: path,
    queryPath: path,
    secretNames: const <String>['TOKEN'],
  );
}
