import 'package:flutter/material.dart';

class SupportedLanguage {
  const SupportedLanguage(this.code, this.nativeName);

  final String code;
  final String nativeName;
}

const supportedLanguages = <SupportedLanguage>[
  SupportedLanguage('en', 'English'),
  SupportedLanguage('de', 'Deutsch'),
];

Locale toLocale(SupportedLanguage language) => Locale(language.code);

const fallbackLocale = Locale('en');
