import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:nodeql/localization/translation_language_metadata.dart';
import 'src/ai_translation_generator.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 2) {
    throw const FormatException(
      'Usage: build_translation_site.dart [source-directory] [site-directory]',
    );
  }
  final source = Directory(arguments.isEmpty ? 'translations' : arguments[0]);
  final site = Directory(
    arguments.length < 2 ? 'build/translation-site' : arguments[1],
  );
  final output = Directory('${site.path}/translations');
  if (await output.exists()) {
    await output.delete(recursive: true);
  }
  await output.create(recursive: true);

  final english = readTranslationPackage(File('assets/translations/en.json'));
  final englishMessages = english.messages;
  final baseUrl = Uri.parse(
    Platform.environment['NODEQL_TRANSLATION_BASE_URL'] ??
        'https://kartoffelspalt.github.io/NodeQL/translations/',
  );
  if (baseUrl.scheme != 'https' || !baseUrl.path.endsWith('/')) {
    throw const FormatException(
      'NODEQL_TRANSLATION_BASE_URL must be HTTPS and end with /.',
    );
  }
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
      final package = readTranslationPackage(file, english: englishMessages);
      final locale = package.locale;
      if (file.uri.pathSegments.last != '$locale.json') {
        throw FormatException('${file.path}: locale must match filename.');
      }
      final messages = package.messages;
      final destination = File('${output.path}/$locale.json');
      await destination.writeAsBytes(bytes, flush: true);
      languages.add({
        'locale': locale,
        'nativeName': translationNativeName(locale),
        'direction': isRtlTranslation(locale) ? 'rtl' : 'ltr',
        'revision': package.revision,
        'completion': englishMessages.isEmpty
            ? 100
            : ((messages.length / englishMessages.length) * 100).floor(),
        'downloadUrl': baseUrl.resolve('$locale.json').toString(),
        'sha256': sha256.convert(bytes).toString(),
        'size': bytes.length,
      });
    }
  }

  final manifest = {
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'minimumAppVersion':
        Platform.environment['NODEQL_TRANSLATION_MINIMUM_APP_VERSION'] ??
        '0.1.0',
    'languages': languages,
  };
  await File(
    '${output.path}/translation-manifest.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  await File(
    '${site.path}/index.html',
  ).writeAsString('<h1>NodeQL translation packages</h1>\n');
}
