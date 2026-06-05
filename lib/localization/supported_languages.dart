import 'package:flutter/material.dart';

class SupportedLanguage {
  const SupportedLanguage(this.code, this.nativeName);

  final String code;
  final String nativeName;
}

const supportedLanguages = <SupportedLanguage>[
  SupportedLanguage('de', 'Deutsch'),
  SupportedLanguage('en', 'English'),
  SupportedLanguage('fr', 'Français'),
  SupportedLanguage('es', 'Español'),
  SupportedLanguage('it', 'Italiano'),
  SupportedLanguage('pt', 'Português'),
  SupportedLanguage('tr', 'Türkçe'),
  SupportedLanguage('ar', 'العربية'),
  SupportedLanguage('ja', '日本語'),
  SupportedLanguage('ko', '한국어'),
  SupportedLanguage('zh', '中文'),
];

Locale toLocale(SupportedLanguage language) => Locale(language.code);

const fallbackLocale = Locale('en');
