import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final englishFile = File('assets/translations/en.json');
  if (!await englishFile.exists()) {
    stderr.writeln('Missing ${englishFile.path}.');
    exitCode = 1;
    return;
  }

  final english = _readPackage(englishFile);
  final englishMessages = _messages(english, englishFile.path);
  final expectedKeys = englishMessages.keys.toSet();

  final directories = arguments.isEmpty
      ? <Directory>[Directory('translations')]
      : arguments.map(Directory.new).toList(growable: false);
  var failed = false;
  for (final directory in directories) {
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith('translation-manifest.json')) continue;
      try {
        final package = _readPackage(entity);
        final messages = _messages(package, entity.path);
        final unknown = messages.keys.toSet().difference(expectedKeys);
        final missing = expectedKeys.difference(messages.keys.toSet());
        if (unknown.isNotEmpty) {
          throw FormatException('unknown keys: ${unknown.join(', ')}');
        }
        for (final key in messages.keys) {
          final expected = _placeholders(englishMessages[key]!);
          final actual = _placeholders(messages[key]!);
          if (expected.length != actual.length ||
              !expected.containsAll(actual)) {
            throw FormatException('placeholder mismatch for "$key"');
          }
        }
        stdout.writeln(
          '${entity.path}: ${messages.length}/${expectedKeys.length} keys, '
          'sha256=${sha256.convert(await entity.readAsBytes())}',
        );
        if (missing.isNotEmpty) {
          stdout.writeln(
            '${entity.path}: ${missing.length} keys use English fallback.',
          );
        }
      } on Object catch (error) {
        failed = true;
        stderr.writeln('${entity.path}: $error');
      }
    }
  }
  if (failed) exitCode = 1;
}

Map<String, dynamic> _readPackage(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    throw const FormatException('package must be a JSON object');
  }
  final json = Map<String, dynamic>.from(decoded);
  if (json['schemaVersion'] != 1) {
    throw FormatException('unsupported schema ${json['schemaVersion']}');
  }
  if (json['locale'] is! String || json['revision'] is! int) {
    throw const FormatException('locale and revision are required');
  }
  return json;
}

Map<String, String> _messages(Map<String, dynamic> json, String path) {
  final raw = json['messages'];
  if (raw is! Map) throw FormatException('$path has no messages object');
  return raw.map((key, value) {
    if (value is! String || value.isEmpty) {
      throw FormatException('$path: "$key" must be a non-empty string');
    }
    return MapEntry('$key', value);
  });
}

Set<String> _placeholders(String value) => RegExp(
  r'\{([A-Za-z_][A-Za-z0-9_]*)\}',
).allMatches(value).map((match) => match.group(1)!).toSet();
