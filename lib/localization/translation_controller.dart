import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supported_languages.dart';
import 'translation_catalog.dart';
import 'translation_models.dart';
import 'translation_repository.dart';

const translationContributionUrl = String.fromEnvironment(
  'NODEQL_TRANSLATION_CONTRIBUTION_URL',
  defaultValue:
      'https://github.com/Kartoffelspalt/NodeQL/blob/master/docs/localization/README.md',
);

class TranslationState {
  const TranslationState({
    this.locale = fallbackLocale,
    this.catalog = const TranslationCatalog(
      locale: 'en',
      messages: {},
      englishMessages: {},
    ),
    this.installed = const {},
    this.available = const [],
    this.loading = true,
    this.syncing = false,
    this.error,
  });

  final Locale locale;
  final TranslationCatalog catalog;
  final Map<String, TranslationPackage> installed;
  final List<TranslationLanguage> available;
  final bool loading;
  final bool syncing;
  final String? error;

  TranslationState copyWith({
    Locale? locale,
    TranslationCatalog? catalog,
    Map<String, TranslationPackage>? installed,
    List<TranslationLanguage>? available,
    bool? loading,
    bool? syncing,
    String? error,
    bool clearError = false,
  }) {
    return TranslationState(
      locale: locale ?? this.locale,
      catalog: catalog ?? this.catalog,
      installed: installed ?? this.installed,
      available: available ?? this.available,
      loading: loading ?? this.loading,
      syncing: syncing ?? this.syncing,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final translationRepositoryProvider = Provider<TranslationRepository>(
  (_) => FileTranslationRepository(),
);

final translationControllerProvider =
    StateNotifierProvider<TranslationController, TranslationState>(
      (ref) => TranslationController(ref.read(translationRepositoryProvider)),
    );

TranslationCatalog translationCatalogOf(BuildContext context) {
  return ProviderScope.containerOf(
    context,
    listen: false,
  ).read(translationControllerProvider).catalog;
}

class TranslationController extends StateNotifier<TranslationState> {
  TranslationController(
    this._repository, {
    Future<File> Function()? settingsFile,
    Future<String> Function()? appVersion,
  }) : _settingsFile = settingsFile ?? _defaultSettingsFile,
       _appVersion =
           appVersion ??
           (() async => (await PackageInfo.fromPlatform()).version),
       super(const TranslationState()) {
    initialize();
  }

  final TranslationRepository _repository;
  final Future<File> Function() _settingsFile;
  final Future<String> Function() _appVersion;
  Map<String, String> _english = const {};

  Future<void> initialize() async {
    try {
      _english = await _repository.loadEnglishMessages();
      final packages = await _repository.loadCachedPackages();
      final installed = {
        for (final package in packages) package.locale: package,
      };
      final locale = await _loadSelectedLocale();
      state = state.copyWith(
        installed: installed,
        locale: locale,
        catalog: _catalogFor(locale, installed),
        loading: false,
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(
        catalog: TranslationCatalog(
          locale: 'en',
          messages: _english,
          englishMessages: _english,
        ),
        loading: false,
        error: '$error',
      );
    }
  }

  Future<void> setLocaleTag(String localeTag) async {
    final normalized = normalizeLocaleTag(localeTag);
    final locale = _localeFromTag(normalized);
    state = state.copyWith(
      locale: locale,
      catalog: _catalogFor(locale, state.installed),
      clearError: true,
    );
    await _persistSelectedLocale(normalized);
  }

  Future<void> refreshManifest() async {
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final manifest = await _repository.fetchManifest();
      final currentVersion = await _appVersion();
      if (!versionAtLeast(currentVersion, manifest.minimumAppVersion)) {
        throw StateError(
          'Language catalog requires NodeQL '
          '${manifest.minimumAppVersion} or newer.',
        );
      }
      state = state.copyWith(
        available: manifest.languages,
        syncing: false,
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(syncing: false, error: '$error');
    }
  }

  Future<void> install(TranslationLanguage language) async {
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final package = await _repository.install(language);
      final installed = {...state.installed, package.locale: package};
      state = state.copyWith(
        installed: installed,
        catalog: _catalogFor(state.locale, installed),
        syncing: false,
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(syncing: false, error: '$error');
    }
  }

  Future<void> remove(String locale) async {
    await _repository.remove(locale);
    final installed = {...state.installed}..remove(normalizeLocaleTag(locale));
    var nextLocale = state.locale;
    if (_localeTag(state.locale) == normalizeLocaleTag(locale)) {
      nextLocale = fallbackLocale;
      await _persistSelectedLocale('en');
    }
    state = state.copyWith(
      installed: installed,
      locale: nextLocale,
      catalog: _catalogFor(nextLocale, installed),
      clearError: true,
    );
  }

  Future<void> openContributionGuide() async {
    final uri = Uri.parse(translationContributionUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  TranslationCatalog _catalogFor(
    Locale locale,
    Map<String, TranslationPackage> installed,
  ) {
    final exact = installed[_localeTag(locale)];
    final language = installed[locale.languageCode];
    final package = exact ?? language;
    final builtIn = builtInMessages[locale.languageCode] ?? const {};
    final messages = <String, String>{...builtIn, ...?package?.messages};
    return TranslationCatalog(
      locale: package?.locale ?? locale.languageCode,
      messages: messages,
      englishMessages: _english,
      direction: package == null
          ? (locale.languageCode == 'ar'
                ? TranslationDirection.rtl
                : TranslationDirection.ltr)
          : state.available
                    .where((item) => item.locale == package.locale)
                    .firstOrNull
                    ?.direction ??
                (locale.languageCode == 'ar'
                    ? TranslationDirection.rtl
                    : TranslationDirection.ltr),
    );
  }

  Future<Locale> _loadSelectedLocale() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return fallbackLocale;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return fallbackLocale;
      return _localeFromTag(normalizeLocaleTag('${decoded['locale']}'));
    } catch (_) {
      return fallbackLocale;
    }
  }

  Future<void> _persistSelectedLocale(String locale) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'locale': locale,
          'savedAt': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {}
  }

  static Future<File> _defaultSettingsFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'nodeql_locale.json'));
  }
}

Locale _localeFromTag(String tag) {
  final parts = tag.split('-');
  return parts.length == 1
      ? Locale(parts.first)
      : Locale(parts.first, parts.last);
}

String _localeTag(Locale locale) => locale.countryCode == null
    ? locale.languageCode
    : '${locale.languageCode}-${locale.countryCode}';

const builtInMessages = <String, Map<String, String>>{
  'de': {
    'app.name': 'NodeQL',
    'toolbar.mountDatabase': 'DB laden',
    'toolbar.runSql': 'SQL ausführen',
    'toolbar.simple': 'Einfach',
    'toolbar.advanced': 'Erweitert',
    'settings.title': 'Einstellungen',
    'settings.languages': 'Sprachen verwalten',
    'settings.about': 'Über NodeQL und Lizenzen',
    'common.close': 'Schließen',
    'common.yes': 'Ja',
    'common.no': 'Nein',
    'common.cancel': 'Abbrechen',
    'common.delete': 'Löschen',
    'palette.search': 'Befehl suchen',
    'palette.searchResults': 'Suchergebnisse',
    'runtime.copySql': 'SQL kopieren',
    'runtime.copied': 'SQL in Zwischenablage kopiert',
    'runtime.noResults': 'Keine Ergebnisse',
    'update.title': 'Update verfügbar',
    'update.message':
        'Version {latestVersion} ist verfügbar. Installiert ist Version {currentVersion}.\n\nDownload: {assetName}',
    'update.later': 'Später',
    'update.details': 'Details',
    'update.download': 'Update laden',
  },
};

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
