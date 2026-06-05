import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scratchql_creater/localization/supported_languages.dart';

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) {
      return LocaleController();
    });

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(fallbackLocale);

  void setLocale(Locale locale) => state = locale;

  void setLanguageCode(String languageCode) {
    state = Locale(languageCode);
  }
}

Locale resolveLocale(Locale? locale, Iterable<Locale> supportedLocales) {
  if (locale == null) return fallbackLocale;

  final supportedByCode = <String, Locale>{
    for (final supported in supportedLocales) supported.languageCode: supported,
  };

  for (final supported in supportedLocales) {
    if (supported.languageCode == locale.languageCode) {
      return supported;
    }
  }

  if (locale.languageCode == 'de' && supportedByCode.containsKey('de')) {
    return supportedByCode['de']!;
  }
  if (supportedByCode.containsKey('en')) {
    return supportedByCode['en']!;
  }

  return fallbackLocale;
}
