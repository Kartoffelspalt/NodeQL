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
    'toolbar.tutorial': 'Tutorial öffnen',
    'settings.title': 'Einstellungen',
    'settings.languages': 'Sprachen verwalten',
    'settings.tutorial': 'Interaktives Tutorial starten',
    'settings.about': 'Über NodeQL und Lizenzen',
    'plugins.installedTab': 'Installiert',
    'plugins.repositoriesTab': 'Repositories',
    'plugins.dataSources': '{count} Datenquelle(n)',
    'plugins.networkHosts': 'Netzwerk-Hosts',
    'plugins.repository.add': 'Repository hinzufügen',
    'plugins.repository.url': 'URL des Repository-Katalogs',
    'plugins.repository.hint':
        'Füge vertrauenswürdige Community-Kataloge hinzu. Manifeste werden vor der Installation per SHA-256 geprüft.',
    'plugins.repository.none':
        'Keine eigenen Plugin-Repositories eingerichtet.',
    'plugins.repository.refresh': 'Repositories aktualisieren',
    'plugins.repository.remove': 'Repository entfernen',
    'plugins.repository.failed':
        'Repository konnte nicht hinzugefügt werden: {error}',
    'project.untitled': 'Unbenannt',
    'project.new.title': 'Neues Projekt',
    'project.new.reset': 'Aktuelle Arbeitsfläche zurücksetzen?',
    'project.new.projectName': 'Projektname',
    'project.new.directoryDialog': 'Projektordner auswählen',
    'project.new.createDatabase': 'Leere SQLite-DB erstellen',
    'project.new.databaseName': 'Datenbankname',
    'project.createDatabaseFailed': 'DB konnte nicht erstellt werden: {error}',
    'project.saveDialog': 'NodeQL-Projekt speichern',
    'project.openDialog': 'NodeQL-Projekt öffnen',
    'tutorial.title': 'NodeQL lernen',
    'tutorial.progress': 'Schritt {current} von {total}',
    'tutorial.skip': 'Einführung überspringen',
    'tutorial.back': 'Zurück',
    'tutorial.next': 'Weiter',
    'tutorial.finish': 'Jetzt loslegen',
    'tutorial.solveFirst': 'Löse zuerst die kurze Aufgabe.',
    'tutorial.answer.correct': 'Richtig. Du kannst fortfahren.',
    'tutorial.answer.retry': 'Noch nicht ganz. Probiere eine andere Antwort.',
    'tutorial.visual.blocks': 'Visuelle SQL-Blöcke',
    'tutorial.visual.database': 'Lokale Datenbanken',
    'tutorial.visual.learn': 'Lernen durch Ausprobieren',
    'tutorial.visual.palette': 'Blockpalette',
    'tutorial.visual.workspace': 'Arbeitsbereich',
    'tutorial.visual.output': 'SQL und Ergebnisse',
    'tutorial.visual.execute': 'ABFRAGE AUSFÜHREN',
    'tutorial.visual.runHint':
        'NodeQL übersetzt deine verbundenen Blöcke in SQL.',
    'tutorial.visual.pluginStatement': 'Plugin-Aktion',
    'tutorial.visual.pluginValue': 'Plugin-Wert',
    'tutorial.visual.pluginContainer': 'Plugin-Container',
    'tutorial.visual.ready': 'Du bist bereit für deine erste visuelle Abfrage.',
    'tutorial.step.1.nav': 'Willkommen',
    'tutorial.step.1.eyebrow': 'WILLKOMMEN',
    'tutorial.step.1.title': 'SQL bauen, ohne SQL aus den Augen zu verlieren',
    'tutorial.step.1.body':
        'NodeQL verbindet visuelle Blöcke mit echter SQL-Ausgabe. Du lernst Abfragestrukturen, experimentierst lokal und kannst jede erzeugte Anweisung prüfen.',
    'tutorial.step.2.nav': 'Die Oberfläche',
    'tutorial.step.2.eyebrow': 'ORIENTIERUNG',
    'tutorial.step.2.title': 'Drei Bereiche, ein Arbeitsablauf',
    'tutorial.step.2.body':
        'Links wählst du Blöcke, in der Mitte setzt du sie zusammen und rechts prüfst du SQL sowie Datenbankergebnisse.',
    'tutorial.step.2.question': 'Wo setzt du eine Abfrage zusammen?',
    'tutorial.step.2.answer.1': 'In der Ergebnistabelle',
    'tutorial.step.2.answer.2': 'Im Arbeitsbereich',
    'tutorial.step.2.answer.3': 'In den Spracheinstellungen',
    'tutorial.step.3.nav': 'Erste Abfrage',
    'tutorial.step.3.eyebrow': 'ABFRAGESTRUKTUR',
    'tutorial.step.3.title': 'Lies die Blöcke von oben nach unten',
    'tutorial.step.3.body':
        'Eine Abfrage beginnt unter ABFRAGE AUSFÜHREN. SELECT wählt Daten, FROM ihre Quelle und WHERE filtert die Zeilen.',
    'tutorial.step.3.question': 'Welcher Block wählt die Tabelle?',
    'tutorial.step.3.answer.1': 'FROM',
    'tutorial.step.3.answer.2': 'WHERE',
    'tutorial.step.3.answer.3': 'SELECT',
    'tutorial.step.4.nav': 'Blöcke verbinden',
    'tutorial.step.4.eyebrow': 'ANDOCKEN',
    'tutorial.step.4.title': 'Formen zeigen gültige Verbindungen',
    'tutorial.step.4.body':
        'Ziehe einen Block an einen passenden Anschluss. NodeQL hebt gültige Ziele hervor und erhält die logische SQL-Reihenfolge.',
    'tutorial.step.4.question':
        'Was solltest du tun, wenn kein Anschluss hervorgehoben wird?',
    'tutorial.step.4.answer.1': 'Den Block irgendwo loslassen',
    'tutorial.step.4.answer.2': 'Das Projekt löschen',
    'tutorial.step.4.answer.3': 'Ihn an eine passende Position bewegen',
    'tutorial.step.5.nav': 'Ausführen',
    'tutorial.step.5.eyebrow': 'AUSFÜHRUNG',
    'tutorial.step.5.title': 'Sieh das SQL vor der Ausführung',
    'tutorial.step.5.body':
        'Lade eine lokale SQLite-Datenbank, prüfe das erzeugte SQL und wähle SQL ausführen. Ergebnisse und verständliche Fehler erscheinen im unteren Ausgabebereich.',
    'tutorial.step.5.question':
        'Wo kannst du die erzeugte Anweisung überprüfen?',
    'tutorial.step.5.answer.1': 'Erst nach dem Schließen von NodeQL',
    'tutorial.step.5.answer.2': 'In der SQL-Ausgabe rechts',
    'tutorial.step.5.answer.3': 'In der Sprachverwaltung',
    'tutorial.step.6.nav': 'Plugin-Nodes',
    'tutorial.step.6.eyebrow': 'ERWEITERUNGEN',
    'tutorial.step.6.title': 'Plugin-Formen zeigen ihre Aufgabe',
    'tutorial.step.6.body':
        'Anweisungs-Plugins verbinden sich mit einer Kette, Wert-Plugins passen in Wertepositionen und Container-Plugins nehmen verschachtelte Blöcke auf.',
    'tutorial.step.6.question':
        'Welche Plugin-Form steht für einen wiederverwendbaren Wert?',
    'tutorial.step.6.answer.1': 'Die facettierte Wertform',
    'tutorial.step.6.answer.2': 'Der Startblock',
    'tutorial.step.6.answer.3': 'Die Ergebnistabelle',
    'tutorial.step.7.nav': 'Bereit',
    'tutorial.step.7.eyebrow': 'NÄCHSTER SCHRITT',
    'tutorial.step.7.title': 'Starte klein und prüfe regelmäßig',
    'tutorial.step.7.body':
        'Beginne mit SELECT und FROM, verbinde eine Datenbank und erweitere die Abfrage Block für Block. Über das Schul-Symbol oder die Einstellungen kannst du dieses Tutorial jederzeit neu öffnen.',
    'common.close': 'Schließen',
    'common.yes': 'Ja',
    'common.no': 'Nein',
    'common.cancel': 'Abbrechen',
    'common.delete': 'Löschen',
    'palette.search': 'Befehl suchen',
    'palette.searchResults': 'Suchergebnisse',
    'editor.chooseColumn': 'Spalte aus {table} auswählen',
    'editor.textValue': 'Textwert',
    'editor.removeReporter': 'Reporter entfernen',
    'runtime.copySql': 'SQL kopieren',
    'runtime.sqlCommandOutput': 'SQL-Command Output',
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
