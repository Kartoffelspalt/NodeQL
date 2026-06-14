import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/localization/translation_models.dart';

void main() {
  const english = <String, String>{'plain': 'Hello', 'welcome': 'Hello {name}'};

  test('parses a valid package and ignores unknown keys', () {
    final package = TranslationPackage.fromBytes(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'locale': 'de-DE',
          'revision': 3,
          'messages': {
            'plain': 'Hallo',
            'welcome': 'Hallo {name}',
            'unknown': 'ignored',
          },
        }),
      ),
      knownKeys: english.keys.toSet(),
      englishMessages: english,
    );

    expect(package.locale, 'de-DE');
    expect(package.revision, 3);
    expect(package.messages, {'plain': 'Hallo', 'welcome': 'Hallo {name}'});
  });

  test('rejects incompatible placeholders', () {
    expect(
      () => TranslationPackage.fromBytes(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'locale': 'de',
            'revision': 1,
            'messages': {'welcome': 'Hallo {person}'},
          }),
        ),
        knownKeys: english.keys.toSet(),
        englishMessages: english,
      ),
      throwsFormatException,
    );
  });

  test('rejects unknown schemas and oversized packages', () {
    expect(
      () => TranslationPackage.fromBytes(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 2,
            'locale': 'de',
            'revision': 1,
            'messages': const <String, String>{},
          }),
        ),
        knownKeys: english.keys.toSet(),
        englishMessages: english,
      ),
      throwsFormatException,
    );
    expect(
      () => TranslationPackage.fromBytes(
        List<int>.filled(maxTranslationPackageBytes + 1, 0),
        knownKeys: english.keys.toSet(),
        englishMessages: english,
      ),
      throwsFormatException,
    );
  });

  test('compares compatible application versions', () {
    expect(versionAtLeast('0.2.0', '0.2.0'), isTrue);
    expect(versionAtLeast('0.2.1+4', '0.2.0'), isTrue);
    expect(versionAtLeast('0.1.33', '0.2.0'), isFalse);
  });
}
