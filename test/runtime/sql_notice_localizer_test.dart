import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_notice_localizer.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_controller.dart';

void main() {
  final english = _englishMessages();
  final englishCatalog = TranslationCatalog(
    locale: 'en',
    messages: english,
    englishMessages: english,
  );
  final germanCatalog = TranslationCatalog(
    locale: 'de',
    messages: builtInMessages['de']!,
    englishMessages: english,
  );

  test('English mode localizes friendly SQLite errors in English', () {
    expect(
      localizedSimpleRuntimeError(
        englishCatalog,
        'SqliteException(1): no such table: customers',
      ),
      'This table was not found in the connected database. '
      'Check the table slot.',
    );
    expect(
      localizedSimpleRuntimeError(
        englishCatalog,
        'SqliteException(19): UNIQUE constraint failed: customers.email',
      ),
      'This value may occur only once in the table. Choose another value.',
    );
  });

  test('compile notices follow the active catalog', () {
    const warning = 'Block "select" is not executable';

    expect(
      localizedSimpleCompileWarning(englishCatalog, warning),
      'This block is not connected to RUN QUERY.',
    );
    expect(
      localizedSimpleCompileWarning(germanCatalog, warning),
      'Dieser Block ist nicht mit ABFRAGE AUSFÜHREN verbunden.',
    );
  });

  test('unknown errors use the localized fallback', () {
    const technicalMessage = 'SqliteException: unexpected native failure';

    expect(
      localizedSimpleRuntimeError(englishCatalog, technicalMessage),
      startsWith('Check this node'),
    );
    expect(
      localizedSimpleRuntimeError(germanCatalog, technicalMessage),
      startsWith('Prüfe diesen Node'),
    );
  });
}

Map<String, String> _englishMessages() {
  final decoded =
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
  return (decoded['messages'] as Map<String, dynamic>).map(
    (key, value) => MapEntry(key, value as String),
  );
}
