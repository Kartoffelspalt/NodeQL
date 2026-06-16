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
    'tutorial.title': 'NodeQL lernen',
    'tutorial.progress': 'Schritt {current} von {total}',
    'tutorial.skip': 'Einführung überspringen',
    'tutorial.back': 'Zurück',
    'tutorial.next': 'Weiter',
    'tutorial.finish': 'Jetzt loslegen',
    'tutorial.solveFirst': 'Löse zuerst die kurze Aufgabe.',
    'tutorial.answer.correct': 'Richtig. Du kannst fortfahren.',
    'tutorial.answer.retry': 'Noch nicht ganz. Probiere eine andere Antwort.',
    'tutorial.mode.beginner': 'Einsteiger',
    'tutorial.mode.beginnerSyntax': 'Nodes & Syntax',
    'tutorial.mode.intermediate': 'Mittlere Kenntnisse',
    'tutorial.mode.expert': 'Viele Kenntnisse',
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
    'tutorial.visual.sql': 'SQL-Vorschau',
    'tutorial.visual.errorHint':
        'Syntaxfehler nahe COUNT: Prüfe die ausgewählten Spalten.',
    'tutorial.visual.contract': 'Erweiterungsvertrag',
    'tutorial.visual.datasource': 'Datenquelle',
    'tutorial.visual.review': 'Integritätsprüfung',
    'tutorial.visual.syntaxStarter': 'Starter-Node',
    'tutorial.visual.syntaxStatement': 'Anweisungs-Node',
    'tutorial.visual.syntaxValue': 'Wert-Node',
    'tutorial.visual.syntaxReady':
        'Du weißt jetzt, wie NodeQL-Nodes SQL-Syntax abbilden.',
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
    'tutorial.syntax.step.1.nav': 'Node-Typen',
    'tutorial.syntax.step.1.eyebrow': 'NODE-SYNTAX',
    'tutorial.syntax.step.1.title':
        'Jeder Node hat eine Aufgabe in der Abfrage',
    'tutorial.syntax.step.1.body':
        'NodeQL nutzt Starter-Nodes, Anweisungs-Nodes und Wert-Nodes. Starter-Nodes beginnen die Ausführung, Anweisungs-Nodes bilden die SQL-Kette und Wert-Nodes füllen Eingaben in anderen Nodes.',
    'tutorial.syntax.step.2.nav': 'Ketten',
    'tutorial.syntax.step.2.eyebrow': 'ANWEISUNGEN',
    'tutorial.syntax.step.2.title':
        'Anweisungs-Nodes lesen sich wie SQL-Klauseln',
    'tutorial.syntax.step.2.body':
        'Blöcke, die vertikal andocken, werden zur Anweisungskette. Lies sie von oben nach unten: SELECT beschreibt die Ausgabe, FROM wählt die Tabelle und spätere Klauseln verfeinern das Ergebnis.',
    'tutorial.syntax.step.2.question':
        'Wie liest du eine Anweisungskette in NodeQL?',
    'tutorial.syntax.step.2.answer.1': 'Von unten nach oben',
    'tutorial.syntax.step.2.answer.2': 'Von oben nach unten',
    'tutorial.syntax.step.2.answer.3': 'Nur anhand der Blockfarbe',
    'tutorial.syntax.step.3.nav': 'Slots',
    'tutorial.syntax.step.3.eyebrow': 'EINGABEN',
    'tutorial.syntax.step.3.title':
        'Slots sind die bearbeitbaren Teile der Syntax',
    'tutorial.syntax.step.3.body':
        'Ein Slot ist ein Platzhalter innerhalb eines Nodes. Er kann eine Spalte, einen Textwert, eine Zahl, einen Tabellennamen oder einen Reporter-Node aufnehmen, abhängig davon, was die SQL-Klausel erwartet.',
    'tutorial.syntax.step.3.question':
        'Was stellt ein Slot innerhalb eines Nodes dar?',
    'tutorial.syntax.step.3.answer.1': 'Einen Ort zum Speichern von Dateien',
    'tutorial.syntax.step.3.answer.2': 'Die App-Einstellungen',
    'tutorial.syntax.step.3.answer.3':
        'Einen bearbeitbaren Wert in der SQL-Syntax',
    'tutorial.syntax.step.4.nav': 'Reporter',
    'tutorial.syntax.step.4.eyebrow': 'WERTE',
    'tutorial.syntax.step.4.title': 'Reporter-Nodes geben einen Wert zurück',
    'tutorial.syntax.step.4.body':
        'Reporterartige Nodes passen in Wert-Slots. Beispiele sind COUNT(*), UPPER(name), Textwerte und Datumsfunktionen. Sie laufen nicht allein, sondern werden Teil einer größeren Klausel.',
    'tutorial.syntax.step.4.question': 'Wohin gehört ein Reporter-Node?',
    'tutorial.syntax.step.4.answer.1': 'In einen passenden Wert-Slot',
    'tutorial.syntax.step.4.answer.2': 'Als einziger Starter-Node',
    'tutorial.syntax.step.4.answer.3': 'Außerhalb der Arbeitsfläche',
    'tutorial.syntax.step.5.nav': 'Reihenfolge',
    'tutorial.syntax.step.5.eyebrow': 'KLAUSELREIHENFOLGE',
    'tutorial.syntax.step.5.title':
        'NodeQL schützt die Reihenfolge der SQL-Klauseln',
    'tutorial.syntax.step.5.body':
        'SQL hat eine logische Klauselreihenfolge. NodeQL hilft, sie einzuhalten: SELECT, FROM, JOIN, WHERE und GROUP BY erscheinen an den Stellen, an denen die Datenbank sie erwartet.',
    'tutorial.syntax.step.5.question':
        'Welche Klausel wählt normalerweise die Tabellenquelle?',
    'tutorial.syntax.step.5.answer.1': 'WHERE',
    'tutorial.syntax.step.5.answer.2': 'FROM',
    'tutorial.syntax.step.5.answer.3': 'COUNT',
    'tutorial.syntax.step.6.nav': 'Plugin-Syntax',
    'tutorial.syntax.step.6.eyebrow': 'ERWEITERUNGEN',
    'tutorial.syntax.step.6.title':
        'Plugin-Nodes folgen denselben Syntaxregeln',
    'tutorial.syntax.step.6.body':
        'Plugin-Nodes können Anweisungen, Werte oder Container sein. Ihre Form zeigt, wie sie verbunden werden, und ihre deklarierten Eingaben zeigen, welche Werte erforderlich sind.',
    'tutorial.syntax.step.6.question':
        'Woran erkennst du, wie ein Plugin-Node verbunden wird?',
    'tutorial.syntax.step.6.answer.1':
        'An seiner Form und den deklarierten Eingaben',
    'tutorial.syntax.step.6.answer.2': 'An der Monitorgröße',
    'tutorial.syntax.step.6.answer.3': 'Am Dateinamen des Projekts',
    'tutorial.syntax.step.7.nav': 'Bereit',
    'tutorial.syntax.step.7.eyebrow': 'NÄCHSTER SCHRITT',
    'tutorial.syntax.step.7.title': 'Nutze Nodes als lesbare SQL-Bausteine',
    'tutorial.syntax.step.7.body':
        'Wenn du einen Node hinzufügst, frage nach seiner Syntaxrolle: Starter, Anweisung, Slot-Wert, Reporter oder Container. Diese Gewohnheit macht NodeQL leichter lernbar und leichter debugbar.',
    'tutorial.intermediate.step.1.nav': 'Abfragekette',
    'tutorial.intermediate.step.1.eyebrow': 'STRUKTUR',
    'tutorial.intermediate.step.1.title':
        'Baue eine vollständige lesbare Abfrage',
    'tutorial.intermediate.step.1.body':
        'Nutze den Pfad für mittlere Kenntnisse, wenn SELECT, FROM und WHERE bereits Sinn ergeben. Du verbindest Filter, Joins, Gruppierung und Ausführungsprüfung zu einem Ablauf.',
    'tutorial.intermediate.step.2.nav': 'Joins',
    'tutorial.intermediate.step.2.eyebrow': 'BEZIEHUNGEN',
    'tutorial.intermediate.step.2.title':
        'Verbinde Tabellen über passende Schlüssel',
    'tutorial.intermediate.step.2.body':
        'Ein JOIN ergänzt Zeilen aus einer weiteren Tabelle. Halte die Quelltabelle klar, verbinde dann den Join-Block und definiere die Spalten, die passende Datensätze erkennen.',
    'tutorial.intermediate.step.2.question':
        'Was braucht ein JOIN, um zwei Tabellen zuverlässig zu verbinden?',
    'tutorial.intermediate.step.2.answer.1': 'Einen zufälligen Spaltennamen',
    'tutorial.intermediate.step.2.answer.2': 'Nur einen ORDER BY-Block',
    'tutorial.intermediate.step.2.answer.3':
        'Einen passenden Schlüssel oder eine Bedingung',
    'tutorial.intermediate.step.3.nav': 'Gruppen',
    'tutorial.intermediate.step.3.eyebrow': 'AGGREGATION',
    'tutorial.intermediate.step.3.title': 'Fasse Zeilen mit GROUP BY zusammen',
    'tutorial.intermediate.step.3.body':
        'Aggregatfunktionen wie COUNT, SUM und AVG fassen Zeilen zusammen. GROUP BY entscheidet, welche Zeilen vor der Ausgabe zusammengehören.',
    'tutorial.intermediate.step.3.question':
        'Welcher Teil bildet die Gruppen für ein aggregiertes Ergebnis?',
    'tutorial.intermediate.step.3.answer.1': 'Der Dateiname der Datenbank',
    'tutorial.intermediate.step.3.answer.2': 'GROUP BY',
    'tutorial.intermediate.step.3.answer.3': 'Die Sprachauswahl',
    'tutorial.intermediate.step.4.nav': 'Parameter',
    'tutorial.intermediate.step.4.eyebrow': 'EINGABEN',
    'tutorial.intermediate.step.4.title':
        'Halte wiederverwendbare Werte getrennt',
    'tutorial.intermediate.step.4.body':
        'Parameterartige Werte machen eine Abfrage leichter prüfbar und wiederverwendbar. Lege veränderliche Werte in sichtbare Wert-Slots statt in langen SQL-Text.',
    'tutorial.intermediate.step.4.question':
        'Warum sollten veränderliche Werte in sichtbaren Wert-Slots bleiben?',
    'tutorial.intermediate.step.4.answer.1':
        'Sie sind leichter zu prüfen und zu ersetzen',
    'tutorial.intermediate.step.4.answer.2': 'Sie löschen die Datenbank',
    'tutorial.intermediate.step.4.answer.3': 'Sie verwandeln SQL in Bilder',
    'tutorial.intermediate.step.5.nav': 'Prüfen',
    'tutorial.intermediate.step.5.eyebrow': 'QUALITÄTSPRÜFUNG',
    'tutorial.intermediate.step.5.title':
        'Lies das SQL, bevor du ihm vertraust',
    'tutorial.intermediate.step.5.body':
        'Scanne vor einer größeren Abfrage die SQL-Ausgabe. Prüfe Tabellennamen, Join-Bedingungen, Filter und Gruppierung, bevor du das Ergebnis nutzt.',
    'tutorial.intermediate.step.5.question':
        'Was solltest du vor einer größeren Abfrage prüfen?',
    'tutorial.intermediate.step.5.answer.1': 'Nur das App-Symbol',
    'tutorial.intermediate.step.5.answer.2':
        'Tabellen, Joins, Filter und Gruppierung',
    'tutorial.intermediate.step.5.answer.3': 'Die Fensterposition',
    'tutorial.intermediate.step.6.nav': 'Plugins',
    'tutorial.intermediate.step.6.eyebrow': 'ERWEITERN',
    'tutorial.intermediate.step.6.title':
        'Nutze Plugin-Blöcke anhand ihrer Form',
    'tutorial.intermediate.step.6.body':
        'Plugin-Blöcke folgen denselben Verbindungsregeln wie eingebaute Blöcke. Ihre Form zeigt, ob sie in eine Anweisungskette, einen Wert-Slot oder einen Container gehören.',
    'tutorial.intermediate.step.6.question': 'Wohin gehört ein Wert-Plugin?',
    'tutorial.intermediate.step.6.answer.1': 'Zwischen unabhängige Fenster',
    'tutorial.intermediate.step.6.answer.2': 'Auf die Titelleiste',
    'tutorial.intermediate.step.6.answer.3': 'In einen passenden Wert-Slot',
    'tutorial.intermediate.step.7.nav': 'Nächster Bau',
    'tutorial.intermediate.step.7.eyebrow': 'ÜBUNG',
    'tutorial.intermediate.step.7.title':
        'Baue einen Bericht in kleinen Prüfungen nach',
    'tutorial.intermediate.step.7.body':
        'Wähle einen Bericht, den du verstehst, baue ihn als Blöcke nach und vergleiche nach jedem Teil die SQL-Ausgabe. So bleiben Fehler sichtbar, während die Abfrage wächst.',
    'tutorial.expert.step.1.nav': 'Architektur',
    'tutorial.expert.step.1.eyebrow': 'SYSTEMBLICK',
    'tutorial.expert.step.1.title':
        'Betrachte NodeQL als visuelle Abfrageschicht',
    'tutorial.expert.step.1.body':
        'Der Pfad für viele Kenntnisse zeigt, wie Blöcke, erzeugtes SQL, Plugin-Manifeste und Datenquellen-Grenzen zusammenpassen. Nutze ihn, wenn du SQL-Konzepte bereits kennst.',
    'tutorial.expert.step.2.nav': 'Join-Strategie',
    'tutorial.expert.step.2.eyebrow': 'ABFRAGEDESIGN',
    'tutorial.expert.step.2.title':
        'Wähle Joins nach Absicht, nicht aus Gewohnheit',
    'tutorial.expert.step.2.body':
        'INNER, LEFT und andere Join-Typen drücken unterschiedliche Ergebnisgarantien aus. Wähle den Join, der zur Frage passt, bevor du Spalten oder Filter optimierst.',
    'tutorial.expert.step.2.question':
        'Was sollte den gewählten Join-Typ bestimmen?',
    'tutorial.expert.step.2.answer.1': 'Nur die Blockfarbe',
    'tutorial.expert.step.2.answer.2': 'Die gewünschte Ergebnisgarantie',
    'tutorial.expert.step.2.answer.3': 'Die aktuelle Sprache',
    'tutorial.expert.step.3.nav': 'Aggregation',
    'tutorial.expert.step.3.eyebrow': 'ERGEBNISFORM',
    'tutorial.expert.step.3.title': 'Trenne Zeilenfilter von Gruppenfiltern',
    'tutorial.expert.step.3.body':
        'WHERE filtert Zeilen vor der Gruppierung. HAVING filtert gruppierte Ergebnisse nach der Aggregation. Diese Rollen sauber zu trennen verhindert subtile Berichtsfehler.',
    'tutorial.expert.step.3.question':
        'Welche Klausel filtert aggregierte Gruppen?',
    'tutorial.expert.step.3.answer.1': 'FROM',
    'tutorial.expert.step.3.answer.2': 'Nur WHERE',
    'tutorial.expert.step.3.answer.3': 'HAVING',
    'tutorial.expert.step.4.nav': 'Debugging',
    'tutorial.expert.step.4.eyebrow': 'DIAGNOSE',
    'tutorial.expert.step.4.title': 'Nutze erzeugtes SQL als Debugging-Vertrag',
    'tutorial.expert.step.4.body':
        'Wenn ein Ergebnis falsch wirkt, prüfe zuerst das SQL. Die erzeugte Anweisung ist der gemeinsame Vertrag zwischen visueller Arbeitsfläche, Runtime und Datenbank.',
    'tutorial.expert.step.4.question':
        'Welches Artefakt prüfst du zuerst, wenn eine komplexe Abfrage fehlschlägt?',
    'tutorial.expert.step.4.answer.1': 'Das erzeugte SQL',
    'tutorial.expert.step.4.answer.2': 'Den Lizenztext der App',
    'tutorial.expert.step.4.answer.3': 'Die Monitorhelligkeit',
    'tutorial.expert.step.5.nav': 'Plugin-Vertrag',
    'tutorial.expert.step.5.eyebrow': 'ERWEITERUNGEN',
    'tutorial.expert.step.5.title': 'Respektiere Plugin-Grenzen',
    'tutorial.expert.step.5.body':
        'Ein Plugin deklariert Blockform, Eingaben, Datenzugriff und Host-Anforderungen. Prüfe diese Grenzen, bevor du Plugin-Verhalten in einen Abfrageablauf mischst.',
    'tutorial.expert.step.5.question':
        'Was sollte ein Plugin deklarieren, bevor es in einem Ablauf vertrauenswürdig ist?',
    'tutorial.expert.step.5.answer.1': 'Nur eine Anzeigefarbe',
    'tutorial.expert.step.5.answer.2':
        'Form, Eingaben und Datenzugriffs-Anforderungen',
    'tutorial.expert.step.5.answer.3': 'Die Bildschirmgröße des Nutzers',
    'tutorial.expert.step.6.nav': 'Wiederverwendbare Eingaben',
    'tutorial.expert.step.6.eyebrow': 'WARTBARKEIT',
    'tutorial.expert.step.6.title':
        'Gestalte Abfragen so, dass Annahmen sichtbar bleiben',
    'tutorial.expert.step.6.body':
        'Lege Schwellenwerte, Datumswerte und Filter als explizite Werte offen. Das erleichtert Reviews und reduziert versehentliche Änderungen in langen Anweisungen.',
    'tutorial.expert.step.6.question':
        'Welche Werte sollten für Reviews sichtbar bleiben?',
    'tutorial.expert.step.6.answer.1': 'Nur Symbolgrößen',
    'tutorial.expert.step.6.answer.2': 'Ungenutzte Tabellennamen',
    'tutorial.expert.step.6.answer.3': 'Schwellenwerte, Datumswerte und Filter',
    'tutorial.expert.step.7.nav': 'Meisterschleife',
    'tutorial.expert.step.7.eyebrow': 'NÄCHSTER SCHRITT',
    'tutorial.expert.step.7.title':
        'Vermittle den Ablauf, indem du Absicht sichtbar machst',
    'tutorial.expert.step.7.body':
        'Halte bei fortgeschrittener Arbeit jede Blockkette erklärbar: Quelle, Beziehung, Filter, Gruppierung, Ausgabe und Erweiterungsgrenze. Diese Disziplin macht Projekte leichter lernbar.',
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
