import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nodeql/engine/plugins/plugin_manifest.dart';

class PluginDataSourceClient {
  PluginDataSourceClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> loadSchema(
    PluginDataSourceDefinition source, {
    Map<String, String> secrets = const <String, String>{},
  }) async {
    final request =
        http.Request('GET', source.resolveEndpoint(source.schemaPath))
          ..followRedirects = false
          ..headers.addAll(_headers(source, secrets));
    final response = await _send(request).timeout(const Duration(seconds: 20));
    return _decodeResponse(response, operation: 'schema');
  }

  Future<Map<String, dynamic>> execute(
    PluginDataSourceDefinition source, {
    required String query,
    Map<String, Object?> parameters = const <String, Object?>{},
    Map<String, String> secrets = const <String, String>{},
  }) async {
    final request =
        http.Request('POST', source.resolveEndpoint(source.queryPath))
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            ..._headers(source, secrets),
            'content-type': 'application/json',
          })
          ..body = jsonEncode(<String, Object?>{
            'query': query,
            'parameters': parameters,
          });
    final response = await _send(request).timeout(const Duration(seconds: 30));
    return _decodeResponse(response, operation: 'query');
  }

  Future<http.Response> _send(http.Request request) async {
    return http.Response.fromStream(await _client.send(request));
  }

  Map<String, String> _headers(
    PluginDataSourceDefinition source,
    Map<String, String> secrets,
  ) {
    final missing = source.secretNames.where(
      (name) => (secrets[name] ?? '').isEmpty,
    );
    if (missing.isNotEmpty) {
      throw StateError('Missing plugin secret(s): ${missing.join(', ')}.');
    }
    return <String, String>{
      'accept': 'application/json',
      for (final name in source.secretNames)
        'x-nodeql-secret-$name': secrets[name]!,
    };
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    required String operation,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Plugin data-source $operation failed with HTTP '
        '${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Plugin data-source response exceeds 4 MiB.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException(
        'Plugin data-source response must be a JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }
}
