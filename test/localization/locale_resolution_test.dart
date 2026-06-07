import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/localization/locale_controller.dart';
import 'package:nodeql/localization/supported_languages.dart';

void main() {
  test('resolves exact locale and falls back to english', () {
    const supported = <Locale>[Locale('en'), Locale('de'), Locale('ar')];

    expect(resolveLocale(const Locale('de'), supported), const Locale('de'));
    expect(resolveLocale(const Locale('pl'), supported), fallbackLocale);
    expect(resolveLocale(null, supported), fallbackLocale);
  });
}
