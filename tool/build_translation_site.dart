import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _nativeNames = <String, String>{
  'ar': 'العربية',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'it': 'Italiano',
  'ja': '日本語',
  'ko': '한국어',
  'pt': 'Português',
  'tr': 'Türkçe',
  'zh': '中文',
};

Future<void> main() async {
  final source = Directory('translations');
  final output = Directory('build/translation-site/translations');
  if (await output.exists()) {
    await output.delete(recursive: true);
  }
  await output.create(recursive: true);

  final english = _readJson(File('assets/translations/en.json'));
  final englishMessages = Map<String, dynamic>.from(english['messages'] as Map);
  final languages = <Map<String, Object?>>[];

  if (await source.exists()) {
    final files = await source
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));

    for (final file in files) {
      final bytes = await file.readAsBytes();
      final package = _readJson(file);
      final locale = package['locale'] as String;
      final messages = Map<String, dynamic>.from(package['messages'] as Map);
      final destination = File('${output.path}/$locale.json');
      await destination.writeAsBytes(bytes, flush: true);
      languages.add({
        'locale': locale,
        'nativeName': _nativeNames[locale] ?? locale,
        'direction': locale == 'ar' ? 'rtl' : 'ltr',
        'revision': package['revision'],
        'completion': englishMessages.isEmpty
            ? 100
            : ((messages.length / englishMessages.length) * 100).floor(),
        'downloadUrl':
            'https://kartoffelspalt.github.io/NodeQL/translations/$locale.json',
        'sha256': sha256.convert(bytes).toString(),
        'size': bytes.length,
      });
    }
  }

  final manifest = {
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'minimumAppVersion': '0.1.0',
    'languages': languages,
  };
  await File(
    '${output.path}/translation-manifest.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  await File(
    'build/translation-site/index.html',
  ).writeAsString('<h1>NodeQL translation packages</h1>\n');
}

Map<String, dynamic> _readJson(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map) {
    throw FormatException('${file.path} must contain a JSON object.');
  }
  return Map<String, dynamic>.from(value);
}
