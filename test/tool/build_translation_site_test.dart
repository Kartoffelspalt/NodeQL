import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/localization/translation_models.dart';

import '../../tool/build_translation_site.dart' as builder;

void main() {
  test(
    'publishes packages with exact hashes, native names, RTL and revisions',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'nodeql-translation-site-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final source = Directory('${temp.path}/packages');
      final site = Directory('${temp.path}/site');
      await source.create();
      final bytes = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'locale': 'he',
          'revision': 12,
          'messages': {'app.name': 'NodeQL'},
        }),
      );
      await File('${source.path}/he.json').writeAsBytes(bytes);
      await builder.main([source.path, site.path]);
      final manifest = TranslationManifest.fromBytes(
        await File(
          '${site.path}/translations/translation-manifest.json',
        ).readAsBytes(),
      );
      final language = manifest.languages.single;
      expect(language.locale, 'he');
      expect(language.nativeName, 'עברית');
      expect(language.direction, TranslationDirection.rtl);
      expect(language.revision, 12);
      expect(language.size, bytes.length);
      expect(language.sha256, sha256.convert(bytes).toString());
      expect(
        await File('${site.path}/translations/he.json').readAsBytes(),
        bytes,
      );
    },
  );
}
