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
    'toolbar.browseDatabase': 'Tabellenbrowser',
    'toolbar.runSql': 'SQLite ausführen',
    'toolbar.connectColumns': 'Spaltenquellen verbinden',
    'toolbar.simple': 'Einfach',
    'toolbar.advanced': 'Erweitert',
    'toolbar.tutorial': 'Workshop öffnen',
    'toolbar.workshop': 'Workshop',
    'workspace.disconnectColumns': 'Spaltenverbindung entfernen',
    'workspace.rope.title': 'Ausgewählte Rope',
    'workspace.rope.source': 'Quelle',
    'workspace.rope.target': 'Ziel',
    'workspace.rope.delete': 'Rope löschen',
    'tabs.add': 'Neue Abfrage erstellen',
    'tabs.executionOrder': 'Ausführungsreihenfolge der Abfragen',
    'tabs.dragToReorder': 'Ziehen, um die Ausführungsreihenfolge zu ändern',
    'tabs.defaultName': 'Abfrage {number}',
    'tabs.rename': 'Tab umbenennen',
    'tabs.renameTitle': 'Abfrage-Tab umbenennen',
    'tabs.name': 'Tab-Name',
    'tabs.delete': 'Workspace löschen',
    'tabs.deleteTitle': 'Workspace löschen?',
    'tabs.deleteMessage':
        'Der Workspace „{name}“ und sein gesamter Inhalt werden dauerhaft gelöscht.',
    'tabs.deleteLastDisabled':
        'Der letzte Workspace kann nicht gelöscht werden.',
    'settings.title': 'Einstellungen',
    'settings.languages': 'Sprachen verwalten',
    'settings.tutorial': 'NodeQL-Workshop öffnen',
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
    'palette.rail.dql': 'Query Language',
    'palette.rail.queryLanguage': 'Query Language',
    'palette.rail.dataTypes': 'SQLite-Datentypen',
    'palette.rail.dml': 'Änderungen',
    'palette.rail.ddl': 'Struktur',
    'palette.rail.dcl': 'Berechtigungen',
    'palette.rail.txn': 'Transaktionen',
    'palette.rail.database': 'Datenbankwerkzeuge',
    'palette.rail.plugins': 'Erweiterungen',
    'palette.category.queryLanguage': 'Query Language',
    'palette.category.dataTypes': 'SQLite-Datentypen',
    'palette.category.database': 'Datenbank & Diagnose',
    'project.untitled': 'Unbenannt',
    'project.new.title': 'Neues Projekt',
    'project.new.reset': 'Aktuelle Arbeitsfläche zurücksetzen?',
    'project.new.projectName': 'Projektname',
    'project.new.directoryDialog': 'Projektordner auswählen',
    'project.new.createDatabase': 'Leere SQLite-DB erstellen',
    'project.new.databaseName': 'Datenbankname',
    'project.new.autosave': 'Autosave für dieses Projekt aktivieren',
    'project.createDatabaseFailed': 'DB konnte nicht erstellt werden: {error}',
    'project.saveDialog': 'NodeQL-Projekt speichern',
    'project.openDialog': 'NodeQL-Projekt öffnen',
    'project.upgrade.title': 'Projekt-Upgrade verfügbar',
    'project.upgrade.message':
        'Dieses Projekt verwendet das alte Format "{format}". NodeQL erstellt zuerst eine Sicherung und aktualisiert dann die Datei auf das aktuelle Format.',
    'project.upgrade.cancel': 'Abbrechen',
    'project.upgrade.confirm': 'Projekt aktualisieren',
    'project.upgrade.completed': 'Projekt aktualisiert. Sicherung: {path}',
    'project.upgrade.failed':
        'Projekt konnte nicht aktualisiert werden: {error}',
    'project.upgrade.unsupportedTitle': 'Projekt kann nicht geöffnet werden',
    'project.upgrade.unsupportedMessage':
        'Diese Projektdatei wird von dieser NodeQL-Version nicht unterstützt: {error}',
    'project.upgrade.close': 'Schließen',
    'tutorial.title': 'NodeQL-Workshop',
    'tutorial.window.title': 'NodeQL-Workshop',
    'tutorial.window.subtitle':
        'Abgekoppelter Lernbereich · echte Nodes · Live-SQLite',
    'tutorial.window.paths': 'Lernpfade',
    'tutorial.window.close': 'Workshop verlassen',
    'tutorial.window.emptyTitle': 'Wähle zum Start einen Lernpfad',
    'tutorial.window.emptyBody':
        'Dieser Lernbereich ist von deinen Projekten getrennt. Alle hier erstellten Nodes gehören nur zur aktuellen Workshop-Sitzung.',
    'tutorial.window.guide.pick': '1 · Lernpfad wählen',
    'tutorial.window.guide.build': '2 · Nodes ziehen und verbinden',
    'tutorial.window.guide.check': '3 · Lösung prüfen',
    'tutorial.progress': 'Schritt {current} von {total}',
    'tutorial.skip': 'Einführung überspringen',
    'tutorial.close': 'Workshop schließen',
    'tutorial.lessons': 'Alle Lektionen',
    'tutorial.overview.eyebrow': 'NODEQL-WORKSHOP',
    'tutorial.overview.title': 'Wähle einen praktischen Lernpfad',
    'tutorial.overview.body':
        'Vier praktische Lernpfade, {missions} Workspace-Missionen und eine eigene SQLite-Übungsdatenbank. Baue jede Lösung mit echten Nodes, führe sie mit Beispieldaten aus und löse eigenständige Projekte – ohne Quizfragen.',
    'tutorial.overview.datasetTitle': 'Deine private Übungsdatenbank',
    'tutorial.overview.datasetBody':
        'customers, orders und archived_customers enthalten Beispieldaten für Filter, JOINs, Aggregate und Mengenoperationen. Sie sind schreibgeschützt, von deinen Projekten getrennt und werden beim Verlassen zurückgesetzt.',
    'tutorial.overview.curriculum': 'Wähle einen Lernpfad',
    'tutorial.overview.datasetRows': '{count} Beispielzeilen',
    'tutorial.overview.progress':
        '{completed} von {total} Lektionen abgeschlossen',
    'tutorial.overview.saved': 'Dein Fortschritt wird automatisch gespeichert.',
    'tutorial.overview.allDone':
        'Workshop abgeschlossen – du kannst jede Lektion jederzeit wiederholen.',
    'tutorial.lesson.exercises': '{solved} von {total} Workspace-Missionen',
    'tutorial.lesson.duration': 'Ca. {minutes} Min.',
    'tutorial.lesson.start': 'Im Workspace starten',
    'tutorial.lesson.resume': 'Im Workspace fortsetzen',
    'tutorial.lesson.repeat': 'Im Workspace wiederholen',
    'tutorial.lesson.finish': 'Lektion abschließen',
    'tutorial.lesson.completed': 'Abgeschlossen',
    'tutorial.lesson.recommended': 'Empfohlen',
    'tutorial.lesson.practiceDone': 'Workspace-Aufgabe gelöst',
    'tutorial.lesson.beginner.description':
        'Ein geführter 15-Minuten-Kurs im Simple Mode: Node-Formen, Labels, Wert-Reporter und eine vollständige SELECT-Abfrage verstehen.',
    'tutorial.lesson.beginnerSyntax.description':
        'Baue SQLite Klausel für Klausel: FROM, WHERE, AND, OR, ORDER BY und LIMIT. Löse danach eine neue Abfrage selbstständig.',
    'tutorial.lesson.intermediate.description':
        'Verknüpfe Tabellen, gruppiere Daten, nutze COUNT, filtere Gruppen und erstelle einen funktionsfähigen Bericht.',
    'tutorial.lesson.expert.description':
        'Erkunde UNION, INTERSECT, EXCEPT und UNION ALL und entwirf danach eine eigene Mengenabfrage.',
    'tutorial.practice.start': 'Mit echten Nodes üben',
    'tutorial.practice.success':
        'Gelöst – dieser Arbeitsbereich enthält die benötigten verbundenen Nodes.',
    'tutorial.practice.otherTab':
        'Die Übung befindet sich in einem anderen Abfrage-Tab.',
    'tutorial.practice.incomplete':
        'Die Node-Kette ist noch nicht vollständig. Nutze die Checkliste oder blende einen Hinweis ein.',
    'tutorial.practice.resume': 'Übungs-Tab öffnen',
    'tutorial.practice.hint': 'Hinweis zeigen',
    'tutorial.practice.check': 'Nodes prüfen',
    'tutorial.practice.close': 'Übungsbegleitung schließen',
    'tutorial.practice.beginner.title': 'Praxis: Erste Abfrage bauen',
    'tutorial.practice.beginner.instruction':
        'Ziehe einen SELECT-Node unter ABFRAGE AUSFÜHREN. Stelle Spalten und Tabelle direkt im Node ein.',
    'tutorial.practice.beginner.hint':
        'Du findest SELECT links in der Palette unter Query Language. Ziehe ihn an den hervorgehobenen Anschluss unter dem Starter-Node.',
    'tutorial.practice.beginner.tab': 'Workshop · Erste Abfrage',
    'tutorial.practice.beginner.check.selectConnected': 'SELECT ist verbunden',
    'tutorial.practice.beginnerSyntax.title': 'Praxis: Zeilen filtern',
    'tutorial.practice.beginnerSyntax.instruction':
        'Erweitere die vorbereitete SELECT-Abfrage um einen WHERE-Node und stelle Spalte, Operator und Wert ein.',
    'tutorial.practice.beginnerSyntax.hint':
        'Setze WHERE unter SELECT. Eine einfache Bedingung wie id = 1 reicht aus.',
    'tutorial.practice.beginnerSyntax.tab': 'Workshop · Abfragesyntax',
    'tutorial.practice.beginnerSyntax.check.whereConnected':
        'WHERE ist verbunden',
    'tutorial.practice.beginnerSyntax.check.whereConfigured':
        'Bedingung ist eingestellt',
    'tutorial.practice.intermediate.title': 'Praxis: Zwei Tabellen verbinden',
    'tutorial.practice.intermediate.instruction':
        'Setze nach FROM einen JOIN ein und stelle die zweite Tabelle sowie ihre Schlüsselbeziehung ein.',
    'tutorial.practice.intermediate.hint':
        'Nutze INNER JOIN. Verbinde customers.id mit orders.customer_id oder stelle eine andere vollständige ON-Bedingung ein.',
    'tutorial.practice.intermediate.tab': 'Workshop · JOIN & Berichte',
    'tutorial.practice.intermediate.check.joinConnected': 'JOIN ist verbunden',
    'tutorial.practice.intermediate.check.joinConfigured':
        'Tabelle und Schlüssel sind eingestellt',
    'tutorial.practice.expert.title': 'Praxis: Aggregierte Gruppen filtern',
    'tutorial.practice.expert.instruction':
        'Erweitere die vorbereitete Abfrage zuerst um GROUP BY und danach um HAVING.',
    'tutorial.practice.expert.hint':
        'Gruppiere zuerst nach customer_id. Ergänze dann HAVING mit einer Aggregatbedingung wie COUNT(*) > 0.',
    'tutorial.practice.expert.tab': 'Workshop · Mengenoperationen',
    'tutorial.practice.expert.check.groupByConnected': 'GROUP BY ist verbunden',
    'tutorial.practice.expert.check.havingConnected': 'HAVING ist verbunden',
    'tutorial.practice.expert.check.groupBeforeHaving':
        'Klauselreihenfolge stimmt',
    'tutorial.practice.mode.simple': 'Simple Mode',
    'tutorial.practice.mode.advanced': 'Advanced Mode',
    'tutorial.practice.modeHelp.simple':
        'Im Simple Mode tragen die Nodes verständliche Bezeichnungen. Beobachte die Live-SQL-Vorschau, um die Syntax dahinter zu lernen.',
    'tutorial.practice.modeHelp.advanced':
        'Im Advanced Mode entsprechen die Node-Beschriftungen direkt den SQLite-Schlüsselwörtern und zeigen alle wichtigen Felder.',
    'tutorial.practice.stepProgress': 'Mission {current} von {total}',
    'tutorial.practice.syntaxGoal': 'Zielsyntax',
    'tutorial.practice.syntaxLive': 'Live erzeugt',
    'tutorial.practice.syntaxEmpty':
        'Verbinde einen Node, um SQLite zu erzeugen …',
    'tutorial.practice.checkNodes': 'Lösung prüfen',
    'tutorial.practice.requirements':
        '{done} von {total} Anforderungen erfüllt',
    'tutorial.practice.nextRequirement': 'Als Nächstes: {requirement}',
    'tutorial.practice.estimatedTime': 'ca. {minutes} Min.',
    'tutorial.practice.runHint':
        'Abschlussprojekt: Klicke oben auf Run SQLite. Die Mission zählt erst, wenn genau diese Abfrage auf der Übungsdatenbank erfolgreich ausgeführt wurde.',
    'tutorial.practice.nodeFocus': 'Diese Nodes verstehen',
    'tutorial.practice.label.simple': 'Simple-Mode-Label',
    'tutorial.practice.label.advanced': 'SQLite-Label',
    'tutorial.practice.nextMission': 'Nächste Mission',
    'tutorial.practice.finish': 'Lernpfad abschließen',
    'tutorial.practice.check.selectConnected':
        'SELECT ist mit ABFRAGE AUSFÜHREN verbunden',
    'tutorial.practice.check.selectConfigured':
        'Spalten und Tabelle sind eingestellt',
    'tutorial.practice.check.fromConnected': 'FROM ist verbunden',
    'tutorial.practice.check.fromConfigured': 'Quelltabelle ist eingestellt',
    'tutorial.practice.check.selectBeforeFrom': 'SELECT steht vor FROM',
    'tutorial.practice.check.whereConnected': 'WHERE ist verbunden',
    'tutorial.practice.check.whereConfigured':
        'Filterbedingung ist eingestellt',
    'tutorial.practice.check.andConnected': 'AND ist verbunden',
    'tutorial.practice.check.andConfigured': 'Zweite Bedingung ist eingestellt',
    'tutorial.practice.check.whereBeforeAnd': 'WHERE steht vor AND',
    'tutorial.practice.check.joinConnected': 'JOIN ist verbunden',
    'tutorial.practice.check.joinConfigured':
        'Verknüpfte Tabelle und Schlüssel sind eingestellt',
    'tutorial.practice.check.groupByConnected': 'GROUP BY ist verbunden',
    'tutorial.practice.check.groupByConfigured':
        'Gruppierungsspalte ist eingestellt',
    'tutorial.practice.check.havingConnected': 'HAVING ist verbunden',
    'tutorial.practice.check.havingConfigured':
        'Aggregatfilter ist eingestellt',
    'tutorial.practice.check.groupBeforeHaving': 'GROUP BY steht vor HAVING',
    'tutorial.practice.check.unionConnected': 'UNION ist verbunden',
    'tutorial.practice.check.unionConfigured': 'Zweite Abfrage ist eingestellt',
    'tutorial.practice.check.unionBeforeOrder': 'UNION steht vor ORDER BY',
    'tutorial.practice.check.orderByConnected': 'ORDER BY ist verbunden',
    'tutorial.practice.check.orderByConfigured':
        'Sortierspalte ist eingestellt',
    'tutorial.practice.check.limitConnected': 'LIMIT ist verbunden',
    'tutorial.practice.check.limitConfigured': 'Zeilenlimit ist eingestellt',
    'tutorial.practice.check.orderBeforeLimit': 'ORDER BY steht vor LIMIT',
    'tutorial.practice.check.selectColumnReporter':
        'Ein SPALTE-Wert-Node steckt in SELECT',
    'tutorial.practice.check.whereTextReporter':
        'Ein TEXT-Wert-Node liefert den Filterwert',
    'tutorial.practice.check.orConnected': 'OR ist verbunden',
    'tutorial.practice.check.orConfigured':
        'Alternative Bedingung ist eingestellt',
    'tutorial.practice.check.whereBeforeOr': 'WHERE steht vor OR',
    'tutorial.practice.check.selectDistinct': 'SELECT entfernt doppelte Zeilen',
    'tutorial.practice.check.selectAggregateReporter':
        'Ein Aggregat-Wert-Node steckt in SELECT',
    'tutorial.practice.check.selectAliasReporter':
        'Ein ALIAS-Wert-Node steckt in SELECT',
    'tutorial.practice.check.intersectConnected': 'INTERSECT ist verbunden',
    'tutorial.practice.check.intersectConfigured':
        'Zweite SELECT-Abfrage für INTERSECT ist eingestellt',
    'tutorial.practice.check.exceptConnected': 'EXCEPT ist verbunden',
    'tutorial.practice.check.exceptConfigured':
        'Zweite SELECT-Abfrage für EXCEPT ist eingestellt',
    'tutorial.practice.check.unionAllConfigured':
        'UNION ALL behält doppelte Zeilen',
    'tutorial.practice.check.queryExecuted':
        'Genau diese Abfrage wurde auf der Übungsdatenbank erfolgreich ausgeführt',
    'tutorial.practice.node.eventGreenFlag.title':
        'ABFRAGE AUSFÜHREN · Start-Node',
    'tutorial.practice.node.eventGreenFlag.body':
        'Dieser hutförmige Node ist die Wurzel. Nur darunter eingerastete Nodes gehören zur ausführbaren Abfrage und zählen für die Mission.',
    'tutorial.practice.node.sqlSelect.title':
        'SELECT · Ergebnisspalten auswählen',
    'tutorial.practice.node.sqlSelect.body':
        'SELECT bestimmt, was das Ergebnis enthält. Im kompakten Einsteiger-Node kann außerdem direkt die Quelltabelle stehen.',
    'tutorial.practice.node.sqlColumn.title': 'SPALTE · Wert-Reporter',
    'tutorial.practice.node.sqlColumn.body':
        'Runde Wert-Nodes verlängern nicht die senkrechte Abfragekette. Sie werden in ein passendes Eingabefeld gesteckt und liefern einen Spaltenausdruck.',
    'tutorial.practice.node.sqlWhere.title': 'WHERE · Zeilen filtern',
    'tutorial.practice.node.sqlWhere.body':
        'WHERE behält nur Zeilen, die eine Bedingung aus Spalte, Vergleichsoperator und Wert erfüllen.',
    'tutorial.practice.node.sqlText.title': 'TEXT · sicherer Textwert',
    'tutorial.practice.node.sqlText.body':
        'TEXT ist ein runder Wert-Node. In einem Wertefeld stellt NodeQL Text getrennt von der Bedingung dar und setzt ihn korrekt in Anführungszeichen.',
    'tutorial.practice.node.sqlAnd.title':
        'AND · eine weitere Bedingung verlangen',
    'tutorial.practice.node.sqlAnd.body':
        'AND erweitert einen vorhandenen WHERE-Filter. Eine Zeile bleibt nur erhalten, wenn die erste und die zusätzliche Bedingung wahr sind.',
    'tutorial.practice.node.sqlOrderBy.title': 'ORDER BY · Ergebnis sortieren',
    'tutorial.practice.node.sqlOrderBy.body':
        'ORDER BY wählt die Sortierspalte. ASC sortiert aufsteigend, DESC kehrt die Reihenfolge um.',
    'tutorial.practice.node.sqlLimit.title':
        'LIMIT · Ergebnisgröße kontrollieren',
    'tutorial.practice.node.sqlLimit.body':
        'LIMIT steht nahe dem Ende einer Abfrage und gibt höchstens eine positive Anzahl von Zeilen zurück.',
    'tutorial.practice.node.sqlFrom.title': 'FROM · Quelltabelle auswählen',
    'tutorial.practice.node.sqlFrom.body':
        'FROM benennt die Tabelle, aus der Zeilen kommen. Im Advanced Mode steht es als eigene Klausel unter SELECT; im Simple Mode kann die Quelle auch direkt in SELECT stehen.',
    'tutorial.practice.node.sqlOr.title': 'OR · Alternative zulassen',
    'tutorial.practice.node.sqlOr.body':
        'OR behält eine Zeile, wenn mindestens eine Bedingung wahr ist. Ohne Klammern wertet SQLite AND vor OR aus – kontrolliere deshalb das Ergebnis.',
    'tutorial.practice.node.sqlInnerJoin.title':
        'INNER JOIN · Tabellen verknüpfen',
    'tutorial.practice.node.sqlInnerJoin.body':
        'Ein INNER JOIN verbindet passende Zeilen über Schlüsselfelder, etwa customers.id und orders.customer_id. Zeilen ohne Partner fallen heraus.',
    'tutorial.practice.node.sqlJoin.title': 'JOIN · Tabellen verknüpfen',
    'tutorial.practice.node.sqlJoin.body':
        'Wähle einen JOIN-Typ und verbinde passende Schlüsselfelder wie customers.id und orders.customer_id. INNER JOIN liefert Zeilen mit Partnern in beiden Tabellen.',
    'tutorial.practice.node.sqlGroupBy.title': 'GROUP BY · Gruppen bilden',
    'tutorial.practice.node.sqlGroupBy.body':
        'GROUP BY fasst Zeilen anhand einer Spalte zu Gruppen zusammen. Mit einem Aggregat wie COUNT kannst du jede Gruppe auswerten.',
    'tutorial.practice.node.sqlHaving.title': 'HAVING · Gruppen filtern',
    'tutorial.practice.node.sqlHaving.body':
        'WHERE filtert einzelne Zeilen vor dem Gruppieren; HAVING filtert anschließend Gruppen anhand einer Aggregatbedingung.',
    'tutorial.practice.node.sqlCount.title': 'COUNT · passende Zeilen zählen',
    'tutorial.practice.node.sqlCount.body':
        'COUNT ist ein Wert-Reporter. Stecke ihn in SELECT und nutze *, um Zeilen pro Gruppe zu zählen. Er verlängert nicht die senkrechte Klauselkette.',
    'tutorial.practice.node.sqlUnion.title': 'UNION · Ergebnismengen vereinen',
    'tutorial.practice.node.sqlUnion.body':
        'UNION vereint kompatible SELECT-Ergebnisse und entfernt Duplikate. Beide Seiten müssen gleich viele Spalten liefern.',
    'tutorial.practice.node.sqlIntersect.title':
        'INTERSECT · gemeinsame Zeilen finden',
    'tutorial.practice.node.sqlIntersect.body':
        'INTERSECT liefert nur Zeilen, die in beiden SELECT-Ergebnissen vorkommen. Spaltenzahl und Werte müssen zusammenpassen.',
    'tutorial.practice.node.sqlExcept.title': 'EXCEPT · Zeilen abziehen',
    'tutorial.practice.node.sqlExcept.body':
        'EXCEPT behält Zeilen aus dem ersten SELECT, die im zweiten Ergebnis fehlen.',
    'tutorial.practice.node.sqlAlias.title': 'ALIAS · Ausdruck benennen',
    'tutorial.practice.node.sqlAlias.body':
        'ALIAS umhüllt einen anderen Wert-Reporter wie SPALTE und gibt der Ergebnisspalte mit AS einen verständlichen Namen.',
    'tutorial.practice.beginner.step.1.title': 'Verbinde dein erstes SELECT',
    'tutorial.practice.beginner.step.1.instruction':
        'Ziehe einen SELECT-Node aus Query Language an den Anschluss unter ABFRAGE AUSFÜHREN. Stelle customers als Tabelle ein.',
    'tutorial.practice.beginner.step.1.hint':
        'Die obere Kerbe von SELECT muss am unteren Anschluss von ABFRAGE AUSFÜHREN einrasten. Ein frei liegender Node zählt nicht.',
    'tutorial.practice.beginner.step.1.example': 'SELECT * FROM customers;',
    'tutorial.practice.beginner.step.1.concept':
        'Eine Abfrage ist ein verbundener Graph, kein Haufen Nodes. Der Start-Node markiert die ausführbare Wurzel; SELECT ist die erste Anweisung dieses Lernpfads.',
    'tutorial.practice.beginner.step.2.title':
        'Stecke einen SPALTE-Wert-Node ein',
    'tutorial.practice.beginner.step.2.instruction':
        'Ziehe SPALTE in das runde Spaltenfeld des vorbereiteten SELECT und wähle name.',
    'tutorial.practice.beginner.step.2.hint':
        'SPALTE ist ein runder Reporter. Lege ihn in das Spaltenfeld von SELECT statt unter die Abfragekette.',
    'tutorial.practice.beginner.step.2.example': 'SELECT name FROM customers;',
    'tutorial.practice.beginner.step.2.concept':
        'Anweisungs-Nodes bilden die senkrechte Abfrage. Runde Reporter-Nodes liefern Werte innerhalb dieser Anweisungen. Dieser Unterschied ist zentral für NodeQL.',
    'tutorial.practice.beginner.step.3.title': 'Filtere Zeilen mit WHERE',
    'tutorial.practice.beginner.step.3.instruction':
        'Raste WHERE unter SELECT ein. Wähle city, den Gleichheitsoperator und Berlin als Vergleichswert.',
    'tutorial.practice.beginner.step.3.hint':
        'WHERE gehört hinter SELECT. Alle drei Teile – Spalte, Operator und Wert – müssen eine vollständige Bedingung bilden.',
    'tutorial.practice.beginner.step.3.example':
        "SELECT name FROM customers WHERE city = 'Berlin';",
    'tutorial.practice.beginner.step.3.concept':
        'SQLite verarbeitet WHERE als Zeilenfilter. Zeilen, für die die Bedingung nicht wahr ist, verschwinden vor der Ausgabe.',
    'tutorial.practice.beginner.step.4.title':
        'Nutze TEXT als eingesteckten Wert',
    'tutorial.practice.beginner.step.4.instruction':
        'Ersetze den direkten WHERE-Wert durch einen TEXT-Reporter und trage Berlin in diesem Node ein.',
    'tutorial.practice.beginner.step.4.hint':
        'Ziehe TEXT aus SQLite-Datentypen in das runde Wertefeld von WHERE. Der Reporter muss nicht leeren Text enthalten.',
    'tutorial.practice.beginner.step.4.example': "… WHERE city = 'Berlin';",
    'tutorial.practice.beginner.step.4.concept':
        'Ein eigener Literal-Node macht den Datentyp sichtbar. NodeQL kann Text korrekt darstellen, während WHERE die Vergleichsstruktur behält.',
    'tutorial.practice.beginner.step.5.title':
        'Ergänze mit AND eine zweite Regel',
    'tutorial.practice.beginner.step.5.instruction':
        'Raste AND unter WHERE ein und konfiguriere eine weitere vollständige Bedingung, zum Beispiel active = 1.',
    'tutorial.practice.beginner.step.5.hint':
        'AND kann keinen Filter beginnen. Es erweitert die WHERE-Bedingung und gehört deshalb darunter.',
    'tutorial.practice.beginner.step.5.example':
        "… WHERE city = 'Berlin' AND active = 1;",
    'tutorial.practice.beginner.step.5.concept':
        'AND verbindet Bedingungen streng: Beide müssen wahr sein. Bei OR würde dagegen eine der beiden Bedingungen genügen.',
    'tutorial.practice.beginner.step.6.title': 'Sortiere die passenden Zeilen',
    'tutorial.practice.beginner.step.6.instruction':
        'Verbinde ORDER BY nach den Filtern. Wähle name und eine gültige auf- oder absteigende Richtung.',
    'tutorial.practice.beginner.step.6.hint':
        'Nutze name mit ASC für eine alphabetische Sortierung von A bis Z. ORDER BY gehört hinter WHERE und AND.',
    'tutorial.practice.beginner.step.6.example': '… ORDER BY name ASC;',
    'tutorial.practice.beginner.step.6.concept':
        'Eine Datenbank verspricht keine natürliche Zeilenreihenfolge. ORDER BY macht das Ergebnis für Menschen und weitere Verarbeitung eindeutig.',
    'tutorial.practice.beginner.step.7.title': 'Schließe mit LIMIT ab',
    'tutorial.practice.beginner.step.7.instruction':
        'Raste LIMIT unter ORDER BY ein und trage eine positive Zeilenanzahl wie 5 ein.',
    'tutorial.practice.beginner.step.7.hint':
        'LIMIT ist der letzte Node dieser Abfrage. Null und negative Werte erfüllen die Mission nicht.',
    'tutorial.practice.beginner.step.7.example': '… ORDER BY name ASC LIMIT 5;',
    'tutorial.practice.beginner.step.7.concept':
        'LIMIT verringert, wie viele sortierte Zeilen SQLite zurückgibt. Das ist praktisch für Vorschauen, Seiten und große Ergebnismengen.',
    'tutorial.practice.beginnerSyntax.step.1.title':
        'Baue SELECT und FROM als einzelne Nodes',
    'tutorial.practice.beginnerSyntax.step.1.instruction':
        'Ein SELECT-Node ist vorbereitet. Verbinde FROM darunter und wähle customers als Quelltabelle.',
    'tutorial.practice.beginnerSyntax.step.1.hint':
        'FROM gehört direkt hinter SELECT, wenn die Quelle als eigener Node dargestellt wird.',
    'tutorial.practice.beginnerSyntax.step.1.example':
        'SELECT name, city FROM customers;',
    'tutorial.practice.beginnerSyntax.step.2.title':
        'Hänge ein vollständiges Prädikat an',
    'tutorial.practice.beginnerSyntax.step.2.instruction':
        'Verbinde WHERE nach FROM und stelle Spalte, Vergleichsoperator und Wert ein.',
    'tutorial.practice.beginnerSyntax.step.2.hint':
        'Nutze country = DE. Die Live-Vorschau zeigt, wie NodeQL Text für SQLite maskiert.',
    'tutorial.practice.beginnerSyntax.step.2.example':
        "… FROM customers WHERE country = 'DE';",
    'tutorial.practice.beginnerSyntax.step.3.title':
        'Kombiniere Bedingungen mit AND',
    'tutorial.practice.beginnerSyntax.step.3.instruction':
        'Ergänze nach WHERE einen AND-Node und stelle selbst eine zweite Bedingung ein.',
    'tutorial.practice.beginnerSyntax.step.3.hint':
        'WHERE beginnt den Filter; AND kann ihn erst danach erweitern. Probiere city = Berlin.',
    'tutorial.practice.beginnerSyntax.step.3.example':
        "… WHERE country = 'DE' AND city = 'Berlin';",
    'tutorial.practice.intermediate.step.1.title':
        'Verbinde customers und orders',
    'tutorial.practice.intermediate.step.1.instruction':
        'Verbinde einen JOIN nach FROM. Stelle die zweite Tabelle ein und verknüpfe customers.id mit orders.customer_id.',
    'tutorial.practice.intermediate.step.1.hint':
        'INNER JOIN ist ein guter Standard. Die verknüpfte Tabelle und beide Schlüsselfelder müssen eingestellt sein.',
    'tutorial.practice.intermediate.step.1.example':
        '… FROM customers INNER JOIN orders ON customers.id = orders.customer_id;',
    'tutorial.practice.intermediate.step.2.title':
        'Gruppiere die verknüpften Zeilen',
    'tutorial.practice.intermediate.step.2.instruction':
        'Ergänze GROUP BY nach dem JOIN und wähle die Spalte, die eine Gruppe definiert.',
    'tutorial.practice.intermediate.step.2.hint':
        'Gruppiere nach customers.name, damit pro Kunde eine Ergebnisgruppe entsteht.',
    'tutorial.practice.intermediate.step.2.example':
        '… GROUP BY customers.name;',
    'tutorial.practice.intermediate.step.3.title':
        'Filtere aggregierte Gruppen',
    'tutorial.practice.intermediate.step.3.instruction':
        'Verbinde HAVING nach GROUP BY und stelle eine Aggregatbedingung ein.',
    'tutorial.practice.intermediate.step.3.hint':
        'HAVING filtert Gruppen statt einzelner Zeilen. COUNT(*) > 0 ist ein gültiges Beispiel.',
    'tutorial.practice.intermediate.step.3.example':
        '… GROUP BY customers.name HAVING COUNT(*) > 0;',
    'tutorial.practice.expert.step.1.title': 'Kombiniere zwei Ergebnismengen',
    'tutorial.practice.expert.step.1.instruction':
        'Verbinde UNION mit dem vorbereiteten SELECT und trage eine kompatible zweite SELECT-Abfrage ein.',
    'tutorial.practice.expert.step.1.hint':
        'Beide SELECT-Abfragen sollten gleich viele Spalten liefern, zum Beispiel id und name.',
    'tutorial.practice.expert.step.1.example':
        'SELECT id, name FROM customers UNION SELECT id, name FROM archived_customers;',
    'tutorial.practice.expert.step.2.title':
        'Sortiere das kombinierte Ergebnis',
    'tutorial.practice.expert.step.2.instruction':
        'Verbinde ORDER BY nach UNION und wähle Ergebnisspalte und Richtung.',
    'tutorial.practice.expert.step.2.hint':
        'Die Sortierung gehört hinter die Mengenoperation. Probiere name aufsteigend.',
    'tutorial.practice.expert.step.2.example': '… UNION … ORDER BY name ASC;',
    'tutorial.practice.expert.step.3.title':
        'Begrenze die finale Ergebnismenge',
    'tutorial.practice.expert.step.3.instruction':
        'Schließe die Kette mit LIMIT ab und stelle ein, wie viele kombinierte Zeilen SQLite liefern soll.',
    'tutorial.practice.expert.step.3.hint':
        'LIMIT ist die letzte Klausel. Verbinde sie unter ORDER BY und trage eine positive Zeilenzahl ein.',
    'tutorial.practice.expert.step.3.example':
        '… UNION … ORDER BY name ASC LIMIT 10;',
    'tutorial.practice.beginnerSyntax.step.1.concept':
        'SELECT bestimmt die Spalten, FROM nennt die Quelltabelle. Die senkrechte Verbindung entspricht der Reihenfolge einer geschriebenen SQLite-Abfrage.',
    'tutorial.practice.beginnerSyntax.step.2.concept':
        'Ein Prädikat vergleicht eine Spalte mit einem Wert. NodeQL setzt Textwerte im erzeugten SQL korrekt in Anführungszeichen.',
    'tutorial.practice.beginnerSyntax.step.3.concept':
        'AND schränkt das Ergebnis ein: Beide Bedingungen müssen wahr sein. Vergleiche Node-Reihenfolge und Live-SQL.',
    'tutorial.practice.beginnerSyntax.step.4.title':
        'Ergänze eine Alternative mit OR',
    'tutorial.practice.beginnerSyntax.step.4.instruction':
        'Verbinde OR nach dem Filter und stelle eine weitere vollständige Bedingung ein, etwa city = Berlin. Führe die Abfrage aus und beobachte das größere Ergebnis.',
    'tutorial.practice.beginnerSyntax.step.4.hint':
        'OR liegt in Query Language. Es braucht Spalte, Operator und Wert und muss hinter WHERE verbunden sein.',
    'tutorial.practice.beginnerSyntax.step.4.example':
        "… WHERE country = 'DE' AND active = 1 OR city = 'Berlin';",
    'tutorial.practice.beginnerSyntax.step.4.concept':
        'OR lässt eine Zeile zu, wenn eine Seite wahr ist. SQLite wertet AND vor OR aus; für eine andere Gruppierung brauchst du Klammern.',
    'tutorial.practice.beginnerSyntax.step.5.title':
        'Lege die Ergebnisreihenfolge fest',
    'tutorial.practice.beginnerSyntax.step.5.instruction':
        'Ergänze ORDER BY nach den Filtern. Sortiere nach name mit ASC oder DESC und vergleiche das Ergebnis mit der unsortierten Ausgabe.',
    'tutorial.practice.beginnerSyntax.step.5.hint':
        'ORDER BY steht unter der WHERE/AND/OR-Kette. Wähle eine echte Ergebnisspalte und ASC oder DESC.',
    'tutorial.practice.beginnerSyntax.step.5.example': '… ORDER BY name ASC;',
    'tutorial.practice.beginnerSyntax.step.5.concept':
        'Ohne ORDER BY garantiert SQLite keine Zeilenreihenfolge. Die Sortierrichtung macht das Ergebnis vorhersagbar.',
    'tutorial.practice.beginnerSyntax.step.6.title':
        'Gib nur wenige Zeilen zurück',
    'tutorial.practice.beginnerSyntax.step.6.instruction':
        'Verbinde LIMIT nach ORDER BY und wähle eine positive Zeilenzahl. Führe die Abfrage aus und beobachte die kürzere Vorschau.',
    'tutorial.practice.beginnerSyntax.step.6.hint':
        'LIMIT steht am Schluss. Trage eine ganze Zahl größer als null ein, zum Beispiel 5.',
    'tutorial.practice.beginnerSyntax.step.6.example':
        '… ORDER BY name ASC LIMIT 5;',
    'tutorial.practice.beginnerSyntax.step.6.concept':
        'LIMIT wirkt nach der Sortierung. Wenn du zuerst sortierst, weißt du genau, welche Zeilen in der Vorschau landen.',
    'tutorial.practice.beginnerSyntax.step.7.title':
        'Projekt: Baue eine Kundensuche',
    'tutorial.practice.beginnerSyntax.step.7.instruction':
        'Verbinde auf einem frischen Canvas SELECT → FROM → WHERE → ORDER BY → LIMIT. Nutze customers, stelle alle Klauseln ein und führe das SQL erfolgreich aus.',
    'tutorial.practice.beginnerSyntax.step.7.hint':
        'Beginne mit SELECT und FROM. Nutze etwa active = 1 als WHERE-Bedingung, sortiere nach name und begrenze auf 5 Zeilen.',
    'tutorial.practice.beginnerSyntax.step.7.example':
        'SELECT name FROM customers WHERE active = 1 ORDER BY name ASC LIMIT 5;',
    'tutorial.practice.beginnerSyntax.step.7.concept':
        'Dieses eigenständige Projekt prüft den ganzen Abfragefluss. Ein Node-Graph ist erst dann nützlich, wenn das erzeugte SQLite auch auf echten Daten läuft.',
    'tutorial.practice.intermediate.step.1.concept':
        'Ein JOIN verbindet Zeilen über passende Schlüssel. customers.id identifiziert die Person; orders.customer_id verweist auf sie.',
    'tutorial.practice.intermediate.step.2.concept':
        'GROUP BY bildet eine Gruppe pro Kunde. Mit einem Aggregat in SELECT wird die Zusammenfassung im nächsten Schritt sichtbar.',
    'tutorial.practice.intermediate.step.3.concept':
        'WHERE filtert vor dem Gruppieren, HAVING danach. COUNT(*) > 0 behält Gruppen mit mindestens einer Bestellung.',
    'tutorial.practice.intermediate.step.4.title':
        'Zähle Bestellungen pro Kunde',
    'tutorial.practice.intermediate.step.4.instruction':
        'Stecke einen COUNT-Wert-Reporter in das Spaltenfeld von SELECT und stelle ihn auf Zeilen zählen. JOIN und GROUP BY bleiben verbunden.',
    'tutorial.practice.intermediate.step.4.hint':
        'COUNT ist rund: Lege ihn in SELECT ab, nicht unter HAVING. Mit * zählst du alle Zeilen pro Gruppe.',
    'tutorial.practice.intermediate.step.4.example':
        'SELECT COUNT(*) FROM customers INNER JOIN orders ON customers.id = orders.customer_id GROUP BY customers.name;',
    'tutorial.practice.intermediate.step.4.concept':
        'Ein Aggregat-Reporter macht aus jeder Gruppe einen Kennwert. COUNT(*) zählt verknüpfte Zeilen; mehr Bestellungen ergeben höhere Werte.',
    'tutorial.practice.intermediate.step.5.title':
        'Sortiere den Gruppenbericht',
    'tutorial.practice.intermediate.step.5.instruction':
        'Setze ORDER BY nach HAVING und wähle eine gültige Spalte und Richtung. Führe den Bericht aus und prüfe die Sortierung.',
    'tutorial.practice.intermediate.step.5.hint':
        'Für einen alphabetischen Bericht nutze customers.name ASC. ORDER BY folgt auf HAVING.',
    'tutorial.practice.intermediate.step.5.example':
        '… GROUP BY customers.name HAVING COUNT(*) > 0 ORDER BY customers.name ASC;',
    'tutorial.practice.intermediate.step.5.concept':
        'Die Sortierung macht gruppierte Ergebnisse reproduzierbar. Sie findet nach dem Gruppenfilter statt.',
    'tutorial.practice.intermediate.step.6.title':
        'Zeige nur den Anfang des Berichts',
    'tutorial.practice.intermediate.step.6.instruction':
        'Ergänze LIMIT unter ORDER BY und trage eine positive Anzahl ein. Vergleiche die Ausgabe vor und nach dem Ausführen.',
    'tutorial.practice.intermediate.step.6.hint':
        'LIMIT muss hinter ORDER BY stehen und eine Zahl größer als null enthalten.',
    'tutorial.practice.intermediate.step.6.example':
        '… ORDER BY customers.name ASC LIMIT 5;',
    'tutorial.practice.intermediate.step.6.concept':
        'Ein Bericht braucht oft nur die ersten Zeilen. Kombiniere LIMIT mit ORDER BY, wenn die Auswahl wichtig ist.',
    'tutorial.practice.intermediate.step.7.title':
        'Projekt: Liefere einen Bestellbericht',
    'tutorial.practice.intermediate.step.7.instruction':
        'Ergänze nach SELECT und FROM einen JOIN, GROUP BY, HAVING, ORDER BY und LIMIT. Stecke einen Aggregat-Reporter in SELECT und führe das fertige SQL aus.',
    'tutorial.practice.intermediate.step.7.hint':
        'Verbinde customers.id mit orders.customer_id, gruppiere nach customers.name, nutze COUNT(*) in SELECT und HAVING COUNT(*) > 0. Sortiere und begrenze danach.',
    'tutorial.practice.intermediate.step.7.example':
        'SELECT COUNT(*) FROM customers INNER JOIN orders ON customers.id = orders.customer_id GROUP BY customers.name HAVING COUNT(*) > 0 ORDER BY customers.name ASC LIMIT 5;',
    'tutorial.practice.intermediate.step.7.concept':
        'Dieses Projekt vereint Beziehungen, Aggregation und Darstellung. Geprüft werden der verbundene Graph und die ausführbare SQLite-Abfrage.',
    'tutorial.practice.expert.step.1.concept':
        'UNION vereint zwei SELECT-Ergebnisse und entfernt Duplikate. Anzahl und Bedeutung der Spalten müssen zusammenpassen.',
    'tutorial.practice.expert.step.2.concept':
        'Eine Sortierung nach einer Mengenoperation gehört hinter das zweite SELECT. Sie ordnet das kombinierte Ergebnis.',
    'tutorial.practice.expert.step.3.concept':
        'LIMIT nach UNION und ORDER BY begrenzt die gesamte kombinierte Menge. Eine andere Reihenfolge würde eine andere Frage beantworten.',
    'tutorial.practice.expert.step.4.title': 'Finde Zeilen in beiden Mengen',
    'tutorial.practice.expert.step.4.instruction':
        'Verbinde INTERSECT mit dem frischen SELECT und trage SELECT id, name FROM archived_customers als zweite Abfrage ein. Führe sie aus und finde den gemeinsamen Datensatz.',
    'tutorial.practice.expert.step.4.hint':
        'INTERSECT braucht ein vollständiges zweites SELECT. Ada steht in beiden Beispieltabellen.',
    'tutorial.practice.expert.step.4.example':
        'SELECT id, name FROM customers INTERSECT SELECT id, name FROM archived_customers;',
    'tutorial.practice.expert.step.4.concept':
        'INTERSECT bildet die Schnittmenge. Beide Seiten brauchen kompatible Spalten; ausgegeben werden nur gemeinsame Zeilen.',
    'tutorial.practice.expert.step.5.title': 'Ziehe archivierte Datensätze ab',
    'tutorial.practice.expert.step.5.instruction':
        'Verbinde auf einem frischen SELECT den EXCEPT-Node und trage ein vollständiges SELECT auf archived_customers ein. Führe es aus und prüfe die übrigen Zeilen.',
    'tutorial.practice.expert.step.5.hint':
        'Nutze SELECT id, name FROM archived_customers im EXCEPT-Feld. Vergleiche das Ergebnis mit INTERSECT.',
    'tutorial.practice.expert.step.5.example':
        'SELECT id, name FROM customers EXCEPT SELECT id, name FROM archived_customers;',
    'tutorial.practice.expert.step.5.concept':
        'EXCEPT zieht die zweite Menge von der ersten ab. Damit findest du Datensätze, die in einem Vergleichsbestand fehlen.',
    'tutorial.practice.expert.step.6.title': 'Behalte Duplikate mit UNION ALL',
    'tutorial.practice.expert.step.6.instruction':
        'Verbinde UNION mit dem frischen SELECT, stelle ein zweites SELECT ein und aktiviere ALL. Führe die Abfrage aus und vergleiche Duplikate mit einfachem UNION.',
    'tutorial.practice.expert.step.6.hint':
        'Nutze archived_customers als zweite Tabelle und aktiviere ALL im UNION-Node. Ada sollte zweimal erscheinen.',
    'tutorial.practice.expert.step.6.example':
        'SELECT id, name FROM customers UNION ALL SELECT id, name FROM archived_customers;',
    'tutorial.practice.expert.step.6.concept':
        'UNION entfernt Duplikate, UNION ALL behält sie. ALL ist oft schneller, wenn keine Duplikatprüfung nötig ist.',
    'tutorial.practice.expert.step.7.title':
        'Wähle eindeutige Werte mit DISTINCT',
    'tutorial.practice.expert.step.7.instruction':
        'Stelle SELECT auf dem frischen Canvas auf DISTINCT. Führe die Abfrage aus und vergleiche die eindeutigen Werte mit den ursprünglichen Zeilen.',
    'tutorial.practice.expert.step.7.hint':
        'Der SELECT-Node hat eine ALL/DISTINCT-Auswahl. Stelle DISTINCT ein; country ist eine gute Ergebnisspalte.',
    'tutorial.practice.expert.step.7.example':
        'SELECT DISTINCT country FROM customers;',
    'tutorial.practice.expert.step.7.concept':
        'DISTINCT entfernt doppelte Ergebniszeilen innerhalb eines SELECT. Anders als UNION verbindet es keine zwei Abfragen.',
    'tutorial.practice.expert.step.8.title': 'Benenne ein Ergebnis mit ALIAS',
    'tutorial.practice.expert.step.8.instruction':
        'Stecke einen ALIAS-Reporter in das Spaltenfeld von SELECT. Gib ihm einen echten Wert, etwa SPALTE mit country, und einen lesbaren Alias.',
    'tutorial.practice.expert.step.8.hint':
        'ALIAS ist ein runder Wert-Node. Stecke SPALTE in sein Wertefeld und trage zum Beispiel region als Alias ein.',
    'tutorial.practice.expert.step.8.example':
        'SELECT DISTINCT country AS region FROM customers;',
    'tutorial.practice.expert.step.8.concept':
        'AS ändert den angezeigten Spaltennamen, nicht die Quelldaten. ALIAS kann einen anderen Reporter umhüllen und zeigt verschachtelte Node-Komposition.',
    'tutorial.practice.expert.step.9.title':
        'Projekt: Veröffentliche ein kombiniertes Ergebnis',
    'tutorial.practice.expert.step.9.instruction':
        'Baue aus einer frischen Wurzel SELECT, UNION, ORDER BY und LIMIT. Stelle ein kompatibles zweites SELECT ein, führe SQLite aus und prüfe die kombinierten Zeilen.',
    'tutorial.practice.expert.step.9.hint':
        'Nutze SELECT id, name FROM customers, UNION SELECT id, name FROM archived_customers, dann ORDER BY name ASC und LIMIT 10.',
    'tutorial.practice.expert.step.9.example':
        'SELECT id, name FROM customers UNION SELECT id, name FROM archived_customers ORDER BY name ASC LIMIT 10;',
    'tutorial.practice.expert.step.9.concept':
        'Das Abschlussprojekt prüft kompatible Mengen, Klauselreihenfolge und erfolgreiche Ausführung. Ein gutes Ergebnis ist reproduzierbar und leicht zu prüfen.',
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
    'tutorial.visual.blocks': 'Visuelle SQLite-Blöcke',
    'tutorial.visual.database': 'Lokale Datenbanken',
    'tutorial.visual.learn': 'Lernen durch Ausprobieren',
    'tutorial.visual.palette': 'Blockpalette',
    'tutorial.visual.workspace': 'Arbeitsbereich',
    'tutorial.visual.output': 'SQLite und Ergebnisse',
    'tutorial.visual.execute': 'ABFRAGE AUSFÜHREN',
    'tutorial.visual.runHint':
        'NodeQL übersetzt deine verbundenen Blöcke in SQLite.',
    'tutorial.visual.pluginStatement': 'Plugin-Aktion',
    'tutorial.visual.pluginValue': 'Plugin-Wert',
    'tutorial.visual.pluginContainer': 'Plugin-Container',
    'tutorial.visual.sql': 'SQLite-Vorschau',
    'tutorial.visual.errorHint':
        'Syntaxfehler nahe COUNT: Prüfe die ausgewählten Spalten.',
    'tutorial.visual.contract': 'Erweiterungsvertrag',
    'tutorial.visual.datasource': 'Datenquelle',
    'tutorial.visual.review': 'Integritätsprüfung',
    'tutorial.visual.syntaxStarter': 'Starter-Node',
    'tutorial.visual.syntaxStatement': 'Anweisungs-Node',
    'tutorial.visual.syntaxValue': 'Wert-Node',
    'tutorial.visual.syntaxReady':
        'Du weißt jetzt, wie NodeQL-Nodes SQLite-Syntax abbilden.',
    'tutorial.visual.ready': 'Du bist bereit für deine erste visuelle Abfrage.',
    'tutorial.step.1.nav': 'Willkommen',
    'tutorial.step.1.eyebrow': 'WILLKOMMEN',
    'tutorial.step.1.title':
        'SQLite bauen, ohne SQLite aus den Augen zu verlieren',
    'tutorial.step.1.body':
        'NodeQL verbindet visuelle Blöcke mit echter SQLite-Ausgabe. Du lernst Abfragestrukturen, experimentierst lokal und kannst jede erzeugte Anweisung prüfen.',
    'tutorial.step.2.nav': 'Die Oberfläche',
    'tutorial.step.2.eyebrow': 'ORIENTIERUNG',
    'tutorial.step.2.title': 'Drei Bereiche, ein Arbeitsablauf',
    'tutorial.step.2.body':
        'Links wählst du Blöcke, in der Mitte setzt du sie zusammen und rechts prüfst du SQLite sowie Datenbankergebnisse.',
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
        'Ziehe einen Block an einen passenden Anschluss. NodeQL hebt gültige Ziele hervor und erhält die logische SQLite-Reihenfolge.',
    'tutorial.step.4.question':
        'Was solltest du tun, wenn kein Anschluss hervorgehoben wird?',
    'tutorial.step.4.answer.1': 'Den Block irgendwo loslassen',
    'tutorial.step.4.answer.2': 'Das Projekt löschen',
    'tutorial.step.4.answer.3': 'Ihn an eine passende Position bewegen',
    'tutorial.step.5.nav': 'Ausführen',
    'tutorial.step.5.eyebrow': 'AUSFÜHRUNG',
    'tutorial.step.5.title': 'Sieh das SQLite vor der Ausführung',
    'tutorial.step.5.body':
        'Lade eine lokale SQLite-Datenbank, prüfe das erzeugte SQLite und wähle SQLite ausführen. Ergebnisse und verständliche Fehler erscheinen im unteren Ausgabebereich.',
    'tutorial.step.5.question':
        'Wo kannst du die erzeugte Anweisung überprüfen?',
    'tutorial.step.5.answer.1': 'Erst nach dem Schließen von NodeQL',
    'tutorial.step.5.answer.2': 'In der SQLite-Ausgabe rechts',
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
    'tutorial.step.7.nav': 'Datenbank laden',
    'tutorial.step.7.eyebrow': 'DATENQUELLE',
    'tutorial.step.7.title': 'Eine Abfrage braucht eine SQLite-Datenbank',
    'tutorial.step.7.body':
        'NodeQL arbeitet lokal mit SQLite-Dateien. Über DB laden wählst du eine .db-Datei aus. Danach kennt NodeQL Tabellen und Spalten und kann Dropdowns mit echten Namen anbieten.',
    'tutorial.step.7.question': 'Warum lädst du zuerst eine .db-Datei?',
    'tutorial.step.7.answer.1': 'Damit die App ihre Farbe ändert',
    'tutorial.step.7.answer.2':
        'Damit Tabellen und Spalten aus der Datenbank bekannt sind',
    'tutorial.step.7.answer.3': 'Damit alle Blöcke gelöscht werden',
    'tutorial.step.8.nav': 'Spalten wählen',
    'tutorial.step.8.eyebrow': 'AUSGABE',
    'tutorial.step.8.title': 'SELECT entscheidet, welche Spalten du siehst',
    'tutorial.step.8.body':
        'Im SELECT-Block wählst du eine oder mehrere Spalten. Alles bedeutet: Zeige jede Spalte der gewählten Tabelle. Für Lernzwecke ist Alles praktisch, später sind einzelne Spalten übersichtlicher.',
    'tutorial.step.8.question': 'Welche Aufgabe hat SELECT?',
    'tutorial.step.8.answer.1': 'Es bestimmt die sichtbaren Spalten',
    'tutorial.step.8.answer.2': 'Es verbindet zwei Tabellen',
    'tutorial.step.8.answer.3': 'Es speichert das Projekt',
    'tutorial.step.9.nav': 'Filtern',
    'tutorial.step.9.eyebrow': 'BEDINGUNGEN',
    'tutorial.step.9.title': 'WHERE zeigt nur passende Zeilen',
    'tutorial.step.9.body':
        'Ein WHERE-Block besteht aus Spalte, Operator und Wert. Beispiel: film_id = 350. Die Datenbank prüft jede Zeile und lässt nur Zeilen übrig, bei denen die Bedingung stimmt.',
    'tutorial.step.9.question':
        'Welche drei Teile hat ein einfacher WHERE-Filter?',
    'tutorial.step.9.answer.1': 'Farbe, Breite und Höhe',
    'tutorial.step.9.answer.2': 'Dateiname, Ordner und Sprache',
    'tutorial.step.9.answer.3': 'Spalte, Operator und Wert',
    'tutorial.step.10.nav': 'SQLite lesen',
    'tutorial.step.10.eyebrow': 'ÜBERSETZUNG',
    'tutorial.step.10.title': 'NodeQL erklärt jeden Block als SQLite',
    'tutorial.step.10.body':
        'Rechts siehst du die SQLite-Ausgabe. Lies sie wie einen Kontrollzettel: Stimmen Tabelle, Spalten und Filter? Wenn ja, kannst du SQLite ausführen. Wenn nicht, änderst du die Blöcke.',
    'tutorial.step.10.question':
        'Warum lohnt sich der Blick auf die SQLite-Ausgabe?',
    'tutorial.step.10.answer.1': 'Sie ersetzt die Datenbankdatei',
    'tutorial.step.10.answer.2':
        'Du erkennst vor dem Ausführen, was die Blöcke bedeuten',
    'tutorial.step.10.answer.3': 'Sie schaltet den Expertenmodus aus',
    'tutorial.step.11.nav': 'Fehler verstehen',
    'tutorial.step.11.eyebrow': 'FEHLERKULTUR',
    'tutorial.step.11.title': 'Fehler sind Hinweise, keine Sackgasse',
    'tutorial.step.11.body':
        'Wenn ein SQLite-Fehler erscheint, prüfe zuerst die letzte Änderung. Häufig fehlen Tabellen, Spaltennamen sind falsch oder ein Wert braucht Anführungszeichen. Ändere einen Block und teste erneut.',
    'tutorial.step.12.nav': 'Weiterlernen',
    'tutorial.step.12.eyebrow': 'NÄCHSTER SCHRITT',
    'tutorial.step.12.title': 'Jetzt folgt das Node- und Syntax-Tutorial',
    'tutorial.step.12.body':
        'Du kennst nun Oberfläche, Datenbank, SELECT, FROM, WHERE und SQLite-Ausgabe. Im nächsten Tutorial lernst du genauer, welche Node-Arten es gibt und wie Slots, Reporter, Joins, GROUP BY und HAVING funktionieren.',
    'tutorial.syntax.step.1.nav': 'Node-Typen',
    'tutorial.syntax.step.1.eyebrow': 'NODE-SYNTAX',
    'tutorial.syntax.step.1.title':
        'Jeder Node hat eine Aufgabe in der Abfrage',
    'tutorial.syntax.step.1.body':
        'NodeQL nutzt Starter-Nodes, Anweisungs-Nodes und Wert-Nodes. Starter-Nodes beginnen die Ausführung, Anweisungs-Nodes bilden die SQLite-Kette und Wert-Nodes füllen Eingaben in anderen Nodes.',
    'tutorial.syntax.step.2.nav': 'Ketten',
    'tutorial.syntax.step.2.eyebrow': 'ANWEISUNGEN',
    'tutorial.syntax.step.2.title':
        'Anweisungs-Nodes lesen sich wie SQLite-Klauseln',
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
        'Ein Slot ist ein Platzhalter innerhalb eines Nodes. Er kann eine Spalte, einen Textwert, eine Zahl, einen Tabellennamen oder einen Reporter-Node aufnehmen, abhängig davon, was die SQLite-Klausel erwartet.',
    'tutorial.syntax.step.3.question':
        'Was stellt ein Slot innerhalb eines Nodes dar?',
    'tutorial.syntax.step.3.answer.1': 'Einen Ort zum Speichern von Dateien',
    'tutorial.syntax.step.3.answer.2': 'Die App-Einstellungen',
    'tutorial.syntax.step.3.answer.3':
        'Einen bearbeitbaren Wert in der SQLite-Syntax',
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
        'NodeQL schützt die Reihenfolge der SQLite-Klauseln',
    'tutorial.syntax.step.5.body':
        'SQLite hat eine logische Klauselreihenfolge. NodeQL hilft, sie einzuhalten: SELECT, FROM, JOIN, WHERE und GROUP BY erscheinen an den Stellen, an denen die Datenbank sie erwartet.',
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
    'tutorial.syntax.step.7.nav': 'SELECT & FROM',
    'tutorial.syntax.step.7.eyebrow': 'GRUNDGERÜST',
    'tutorial.syntax.step.7.title':
        'SELECT und FROM bilden die kleinste Abfrage',
    'tutorial.syntax.step.7.body':
        'SELECT beschreibt die Ausgabe, FROM beschreibt die Quelle. In NodeQL kannst du beides sichtbar als Blöcke lesen. Erst wenn beide Informationen stimmen, weiß die Datenbank, was sie anzeigen soll.',
    'tutorial.syntax.step.7.question':
        'Welche beiden Teile braucht eine einfache Tabellenabfrage meistens?',
    'tutorial.syntax.step.7.answer.1': 'HAVING und Plugin',
    'tutorial.syntax.step.7.answer.2': 'SELECT und FROM',
    'tutorial.syntax.step.7.answer.3': 'Nur ORDER BY',
    'tutorial.syntax.step.8.nav': 'WHERE',
    'tutorial.syntax.step.8.eyebrow': 'ZEILENFILTER',
    'tutorial.syntax.step.8.title': 'WHERE filtert Zeilen vor der Ausgabe',
    'tutorial.syntax.step.8.body':
        'WHERE arbeitet vor GROUP BY und vor der endgültigen Ausgabe. In NodeQL ist die Bedingung bewusst aufgeteilt: Spalte auswählen, Operator wählen, Wert eintragen. So sieht man sofort, was geprüft wird.',
    'tutorial.syntax.step.8.question': 'Wann wirkt WHERE?',
    'tutorial.syntax.step.8.answer.1':
        'Erst nachdem die Ergebnisse angezeigt wurden',
    'tutorial.syntax.step.8.answer.2': 'Nur beim Speichern eines Projekts',
    'tutorial.syntax.step.8.answer.3':
        'Beim Filtern einzelner Zeilen vor der Ausgabe',
    'tutorial.syntax.step.9.nav': 'JOIN',
    'tutorial.syntax.step.9.eyebrow': 'TABELLEN VERBINDEN',
    'tutorial.syntax.step.9.title':
        'JOIN verbindet Tabellen über passende Spalten',
    'tutorial.syntax.step.9.body':
        'Ein JOIN braucht eine zweite Tabelle und zwei Spalten, die zusammengehören. In NodeQL sieht man das als linke Spalte = rechte Spalte. So wird aus zwei Tabellen ein gemeinsamer Ergebnisraum.',
    'tutorial.syntax.step.9.question': 'Was beschreibt die JOIN-Bedingung?',
    'tutorial.syntax.step.9.answer.1': 'Welche zwei Spalten zusammenpassen',
    'tutorial.syntax.step.9.answer.2': 'Welche Farbe ein Block hat',
    'tutorial.syntax.step.9.answer.3': 'Wie groß das Fenster ist',
    'tutorial.syntax.step.10.nav': 'GROUP BY & HAVING',
    'tutorial.syntax.step.10.eyebrow': 'GRUPPEN',
    'tutorial.syntax.step.10.title':
        'GROUP BY bildet Gruppen, HAVING filtert Gruppen',
    'tutorial.syntax.step.10.body':
        'GROUP BY fasst Zeilen nach einer Spalte zusammen. COUNT, SUM, AVG, MIN und MAX berechnen Werte über diese Gruppen. HAVING prüft anschließend Bedingungen wie SUM(film_id) = 350.',
    'tutorial.syntax.step.10.question': 'Was filtert HAVING?',
    'tutorial.syntax.step.10.answer.1': 'Einzelne Zeilen vor der Gruppierung',
    'tutorial.syntax.step.10.answer.2':
        'Berechnete Gruppen nach der Aggregation',
    'tutorial.syntax.step.10.answer.3': 'Die Liste der Projekte',
    'tutorial.syntax.step.11.nav': 'ORDER BY',
    'tutorial.syntax.step.11.eyebrow': 'SORTIERUNG',
    'tutorial.syntax.step.11.title': 'ORDER BY sortiert das fertige Ergebnis',
    'tutorial.syntax.step.11.body':
        'ORDER BY ändert nicht, welche Zeilen vorhanden sind. Es ändert nur ihre Reihenfolge. Aufsteigend bedeutet klein nach groß oder A nach Z. Absteigend bedeutet umgekehrt.',
    'tutorial.syntax.step.11.question': 'Was verändert ORDER BY?',
    'tutorial.syntax.step.11.answer.1': 'Die Reihenfolge der Ergebniszeilen',
    'tutorial.syntax.step.11.answer.2': 'Den Namen der Datenbankdatei',
    'tutorial.syntax.step.11.answer.3': 'Die Anzahl der gespeicherten Projekte',
    'tutorial.syntax.step.12.nav': 'Bereit',
    'tutorial.syntax.step.12.eyebrow': 'NÄCHSTER SCHRITT',
    'tutorial.syntax.step.12.title': 'Nutze Nodes als lesbare SQLite-Bausteine',
    'tutorial.syntax.step.12.body':
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
        'Parameterartige Werte machen eine Abfrage leichter prüfbar und wiederverwendbar. Lege veränderliche Werte in sichtbare Wert-Slots statt in langen SQLite-Text.',
    'tutorial.intermediate.step.4.question':
        'Warum sollten veränderliche Werte in sichtbaren Wert-Slots bleiben?',
    'tutorial.intermediate.step.4.answer.1':
        'Sie sind leichter zu prüfen und zu ersetzen',
    'tutorial.intermediate.step.4.answer.2': 'Sie löschen die Datenbank',
    'tutorial.intermediate.step.4.answer.3': 'Sie verwandeln SQLite in Bilder',
    'tutorial.intermediate.step.5.nav': 'Prüfen',
    'tutorial.intermediate.step.5.eyebrow': 'QUALITÄTSPRÜFUNG',
    'tutorial.intermediate.step.5.title':
        'Lies das SQLite, bevor du ihm vertraust',
    'tutorial.intermediate.step.5.body':
        'Scanne vor einer größeren Abfrage die SQLite-Ausgabe. Prüfe Tabellennamen, Join-Bedingungen, Filter und Gruppierung, bevor du das Ergebnis nutzt.',
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
    'tutorial.intermediate.step.7.nav': 'Fehler lesen',
    'tutorial.intermediate.step.7.eyebrow': 'DEBUGGING',
    'tutorial.intermediate.step.7.title': 'Nutze Fehlermeldungen als Wegweiser',
    'tutorial.intermediate.step.7.body':
        'Wenn eine Abfrage fehlschlägt, vergleiche die Fehlermeldung mit der SQLite-Ausgabe. Suche nach falsch geschriebenen Spalten, fehlenden Tabellen, ungültigen Join-Bedingungen oder Werten ohne passende Anführungszeichen.',
    'tutorial.intermediate.step.7.question':
        'Was prüfst du bei einer fehlerhaften Abfrage zuerst?',
    'tutorial.intermediate.step.7.answer.1': 'Nur die Farbe des Blocks',
    'tutorial.intermediate.step.7.answer.2':
        'Fehlermeldung und erzeugtes SQLite',
    'tutorial.intermediate.step.7.answer.3': 'Die Größe der App',
    'tutorial.intermediate.step.8.nav': 'HAVING sicher nutzen',
    'tutorial.intermediate.step.8.eyebrow': 'GRUPPENFILTER',
    'tutorial.intermediate.step.8.title':
        'Prüfe Aggregat, Spalte, Operator und Wert getrennt',
    'tutorial.intermediate.step.8.body':
        'HAVING wird klarer, wenn du die Teile einzeln denkst: Welche Funktion? Welche Spalte? Welcher Vergleich? Welcher Grenzwert? Beispiel: SUM(film_id) = 350.',
    'tutorial.intermediate.step.8.question':
        'Welche Teile braucht ein übersichtlicher HAVING-Block?',
    'tutorial.intermediate.step.8.answer.1': 'Nur einen Tabellennamen',
    'tutorial.intermediate.step.8.answer.2': 'Nur eine Sortierung',
    'tutorial.intermediate.step.8.answer.3':
        'Aggregat, Spalte, Operator und Wert',
    'tutorial.intermediate.step.9.nav': 'Erweiterungen prüfen',
    'tutorial.intermediate.step.9.eyebrow': 'PLUGINS',
    'tutorial.intermediate.step.9.title': 'Prüfe Plugin-Blöcke vor dem Einsatz',
    'tutorial.intermediate.step.9.body':
        'Bevor du Plugins in eine Abfrage einbaust, lies ihre Form, Eingaben und Beschreibung. Ein Wert-Plugin gehört in einen Slot, ein Anweisungs-Plugin in die Kette und ein Container-Plugin um andere Blöcke.',
    'tutorial.intermediate.step.9.question':
        'Was zeigt dir, wohin ein Plugin gehört?',
    'tutorial.intermediate.step.9.answer.1': 'Form, Eingaben und Beschreibung',
    'tutorial.intermediate.step.9.answer.2': 'Nur die Uhrzeit',
    'tutorial.intermediate.step.9.answer.3': 'Nur die Dateigröße',
    'tutorial.intermediate.step.10.nav': 'Nächster Bau',
    'tutorial.intermediate.step.10.eyebrow': 'ÜBUNG',
    'tutorial.intermediate.step.10.title':
        'Baue einen Bericht in kleinen Prüfungen nach',
    'tutorial.intermediate.step.10.body':
        'Wähle einen Bericht, den du verstehst, baue ihn als Blöcke nach und vergleiche nach jedem Teil die SQLite-Ausgabe. So bleiben Fehler sichtbar, während die Abfrage wächst.',
    'tutorial.expert.step.1.nav': 'Architektur',
    'tutorial.expert.step.1.eyebrow': 'SYSTEMBLICK',
    'tutorial.expert.step.1.title':
        'Betrachte NodeQL als visuelle Abfrageschicht',
    'tutorial.expert.step.1.body':
        'Der Pfad für viele Kenntnisse zeigt, wie Blöcke, erzeugtes SQLite, Plugin-Manifeste und Datenquellen-Grenzen zusammenpassen. Nutze ihn, wenn du SQLite-Konzepte bereits kennst.',
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
    'tutorial.expert.step.4.title':
        'Nutze erzeugtes SQLite als Debugging-Vertrag',
    'tutorial.expert.step.4.body':
        'Wenn ein Ergebnis falsch wirkt, prüfe zuerst das SQLite. Die erzeugte Anweisung ist der gemeinsame Vertrag zwischen visueller Arbeitsfläche, Runtime und Datenbank.',
    'tutorial.expert.step.4.question':
        'Welches Artefakt prüfst du zuerst, wenn eine komplexe Abfrage fehlschlägt?',
    'tutorial.expert.step.4.answer.1': 'Das erzeugte SQLite',
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
    'tutorial.expert.step.7.nav': 'Review-Schleife',
    'tutorial.expert.step.7.eyebrow': 'QUALITÄT',
    'tutorial.expert.step.7.title': 'Prüfe Abfragen wie kleine Programme',
    'tutorial.expert.step.7.body':
        'Komplexe Blockketten brauchen Reviews: Ist die Datenquelle korrekt? Sind Joins absichtlich gewählt? Werden Zeilen und Gruppen an der richtigen Stelle gefiltert? Ist das Ergebnis reproduzierbar?',
    'tutorial.expert.step.7.question':
        'Welche Frage gehört in ein Query-Review?',
    'tutorial.expert.step.7.answer.1':
        'Sind Quelle, Joins, Filter und Ergebnisabsicht klar?',
    'tutorial.expert.step.7.answer.2': 'Ist die Fensterdekoration hell genug?',
    'tutorial.expert.step.7.answer.3': 'Ist der Projektname besonders lang?',
    'tutorial.expert.step.8.nav': 'Plugin-Sicherheit',
    'tutorial.expert.step.8.eyebrow': 'GRENZEN',
    'tutorial.expert.step.8.title':
        'Trenne lokale SQLite-Logik von Plugin-Verhalten',
    'tutorial.expert.step.8.body':
        'Plugins erweitern NodeQL, aber sie bleiben externe Verträge. Prüfe Host-Anforderungen, Datenzugriff und erwartete Eingaben, bevor du Plugin-Ergebnisse als Teil einer wichtigen Abfrage behandelst.',
    'tutorial.expert.step.8.question':
        'Warum müssen Plugin-Grenzen sichtbar bleiben?',
    'tutorial.expert.step.8.answer.1': 'Damit Blöcke größer gezeichnet werden',
    'tutorial.expert.step.8.answer.2':
        'Damit Datenzugriff und Eingaben nachvollziehbar bleiben',
    'tutorial.expert.step.8.answer.3':
        'Damit ORDER BY automatisch verschwindet',
    'tutorial.expert.step.9.nav': 'Wartbarkeit',
    'tutorial.expert.step.9.eyebrow': 'LANGLEBIGKEIT',
    'tutorial.expert.step.9.title': 'Halte Annahmen änderbar und sichtbar',
    'tutorial.expert.step.9.body':
        'Gute NodeQL-Projekte erklären sich selbst: feste Grenzwerte stehen in Wert-Slots, wichtige Filter sind benannt, und die SQLite-Ausgabe bleibt lesbar genug, um sie mit anderen zu besprechen.',
    'tutorial.expert.step.9.question': 'Was macht eine Abfrage wartbarer?',
    'tutorial.expert.step.9.answer.1': 'Versteckte Werte in langen Texten',
    'tutorial.expert.step.9.answer.2': 'Unbenannte Tabellen',
    'tutorial.expert.step.9.answer.3':
        'Sichtbare Werte, klare Filter und lesbares SQLite',
    'tutorial.expert.step.10.nav': 'Meisterschleife',
    'tutorial.expert.step.10.eyebrow': 'NÄCHSTER SCHRITT',
    'tutorial.expert.step.10.title':
        'Vermittle den Ablauf, indem du Absicht sichtbar machst',
    'tutorial.expert.step.10.body':
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
    'editor.value': 'Wert',
    'editor.removeReporter': 'Reporter entfernen',
    'runtime.copySql': 'SQLite kopieren',
    'runtime.sqlCommandOutput': 'SQLite-Command Output',
    'runtime.customSql': 'Eigenes SQLite',
    'runtime.customSqlHint':
        'SQLite direkt schreiben, zum Beispiel:\nSELECT * FROM tabellenname LIMIT 100;',
    'runtime.localCompletion': 'Lokale intelligente Vervollständigung',
    'runtime.ideTitle': 'SQLite-Editor',
    'runtime.ideSubtitle':
        'SQLite mit lokaler Schema-Vervollständigung schreiben und ausführen',
    'runtime.outputPreview': 'Ausgabevorschau',
    'runtime.showNodeWorkspace': 'Visuelle Node-Arbeitsfläche anzeigen',
    'runtime.showGeneratedSql': 'Generiertes SQLite anzeigen',
    'runtime.runCustomSql': 'Eigenes SQLite ausführen',
    'runtime.copied': 'SQLite in Zwischenablage kopiert',
    'databaseBrowser.title': 'SQLite-Tabellenbrowser',
    'databaseBrowser.refresh': 'Datenbank neu einlesen',
    'databaseBrowser.backToDatabase': 'Zurück zur Datenbank',
    'databaseBrowser.objectCount': '{count} Objekt(e)',
    'databaseBrowser.objects': 'Datenbankobjekte',
    'databaseBrowser.search': 'Tabelle oder View suchen',
    'databaseBrowser.clearSearch': 'Suche löschen',
    'databaseBrowser.noMatches': 'Keine passenden Objekte gefunden.',
    'databaseBrowser.tables': 'Tabellen',
    'databaseBrowser.views': 'Views',
    'databaseBrowser.table': 'Tabelle',
    'databaseBrowser.view': 'View',
    'databaseBrowser.noObjects': 'Keine Tabellen oder Views vorhanden.',
    'databaseBrowser.databaseInfo': 'Datenbankinformationen',
    'databaseBrowser.encoding': 'Kodierung',
    'databaseBrowser.size': 'Dateigröße',
    'databaseBrowser.content': 'Inhalt',
    'databaseBrowser.structure': 'Aufbau',
    'databaseBrowser.rows': '{count} Zeile(n)',
    'databaseBrowser.columnsCount': '{count} Spalte(n)',
    'databaseBrowser.rowRange': 'Zeilen {start}–{end} von {count}',
    'databaseBrowser.page': 'Seite {current} von {total}',
    'databaseBrowser.previous': 'Vorherige Seite',
    'databaseBrowser.next': 'Nächste Seite',
    'databaseBrowser.noRows': 'Keine Datensätze vorhanden.',
    'databaseBrowser.columns': 'Spalten',
    'databaseBrowser.column': 'Spalte',
    'databaseBrowser.type': 'Typ',
    'databaseBrowser.hidden': 'Hidden / Generiert',
    'databaseBrowser.notNull': 'NOT NULL',
    'databaseBrowser.defaultValue': 'DEFAULT',
    'databaseBrowser.primaryKey': 'PRIMARY KEY',
    'databaseBrowser.foreignKeys': 'Fremdschlüssel',
    'databaseBrowser.indexes': 'Indizes',
    'databaseBrowser.createSql': 'Originales CREATE-SQL',
    'databaseBrowser.copyCreateSql': 'CREATE-SQL kopieren',
    'databaseBrowser.createSqlCopied': 'CREATE-SQL wurde kopiert',
    'databaseBrowser.newTable': 'Neue Tabelle',
    'databaseBrowser.createTable': 'Tabelle erstellen',
    'databaseBrowser.createTableHelp':
        'Bearbeite den SQLite-CREATE-Befehl und führe ihn in dieser Datenbank aus.',
    'databaseBrowser.createCommand': 'SQLite-CREATE-Befehl',
    'databaseBrowser.simple.newTable': 'Neue Tabelle',
    'databaseBrowser.simple.createTable': 'Tabelle erstellen',
    'databaseBrowser.simple.createTableHelp':
        'Benenne die Tabelle, füge Spalten hinzu und wähle ihre Eigenschaften.',
    'databaseBrowser.simple.tableName': 'Tabellenname',
    'databaseBrowser.simple.defineColumns': 'Spalten',
    'databaseBrowser.simple.addColumn': 'Spalte hinzufügen',
    'databaseBrowser.simple.columnName': 'Spaltenname',
    'databaseBrowser.simple.columnNumber': 'Spalte {number}',
    'databaseBrowser.simple.removeColumn': 'Spalte entfernen',
    'databaseBrowser.simple.primaryKeyOption': 'Primärschlüssel',
    'databaseBrowser.simple.notNullOption': 'Pflichtfeld',
    'databaseBrowser.simple.uniqueOption': 'Eindeutig',
    'databaseBrowser.simple.preview': 'SQLite-Vorschau',
    'databaseBrowser.simple.createTableAction': 'Tabelle erstellen',
    'databaseBrowser.simple.tableNameRequired': 'Gib einen Tabellennamen ein.',
    'databaseBrowser.simple.columnRequired':
        'Jede Tabelle benötigt mindestens eine benannte Spalte.',
    'databaseBrowser.simple.duplicateColumn':
        'Der Spaltenname „{name}“ wird mehrfach verwendet.',
    'databaseBrowser.executeSql': 'SQLite ausführen',
    'databaseBrowser.sqlSuccess': 'SQLite-Befehl wurde erfolgreich ausgeführt.',
    'databaseBrowser.value': 'Vollständiger Wert',
    'databaseBrowser.openValue': 'Vollständigen Wert öffnen',
    'databaseBrowser.simple.title': 'Entdecke deine Daten',
    'databaseBrowser.simple.search': 'Tabelle suchen',
    'databaseBrowser.simple.clearSearch': 'Suche leeren',
    'databaseBrowser.simple.tables': 'Tabellen',
    'databaseBrowser.simple.views': 'Ansichten',
    'databaseBrowser.simple.noObjects':
        'Diese Datenbank enthält keine Tabellen.',
    'databaseBrowser.simple.emptyTitle': 'Platz für deine Daten',
    'databaseBrowser.simple.emptyHelp':
        'Erstelle deine erste Tabelle und ordne Informationen in Zeilen und Spalten.',
    'databaseBrowser.simple.noMatches': 'Keine passende Tabelle gefunden.',
    'databaseBrowser.simple.databaseInfo': 'Dateiinformationen',
    'databaseBrowser.simple.encoding': 'Textformat',
    'databaseBrowser.simple.size': 'Speichergröße',
    'databaseBrowser.simple.table': 'Tabelle',
    'databaseBrowser.simple.view': 'Ansicht',
    'databaseBrowser.simple.columnsCount': 'Spalten: {count}',
    'databaseBrowser.simple.rows': 'Einträge: {count}',
    'databaseBrowser.simple.content': 'Daten',
    'databaseBrowser.simple.structure': 'Spalten & Details',
    'databaseBrowser.simple.noRows': 'Diese Tabelle ist leer.',
    'databaseBrowser.simple.rowRange': 'Einträge {start}–{end} von {count}',
    'databaseBrowser.simple.page': 'Seite {current} von {total}',
    'databaseBrowser.simple.previous': 'Zurück',
    'databaseBrowser.simple.next': 'Weiter',
    'databaseBrowser.simple.columns': 'Tabellenspalten',
    'databaseBrowser.simple.columnsHelp':
        'Jede Spalte speichert eine Art von Information für jeden Eintrag.',
    'databaseBrowser.simple.anyType': 'Beliebiger Wert',
    'databaseBrowser.simple.moreDetails': 'Weitere Details',
    'databaseBrowser.simple.column': 'Name',
    'databaseBrowser.simple.type': 'Datentyp',
    'databaseBrowser.simple.required': 'Pflichtfeld',
    'databaseBrowser.simple.defaultValue': 'Standardwert',
    'databaseBrowser.simple.primaryKey': 'Hauptschlüssel',
    'databaseBrowser.simple.hidden': 'Weitere Eigenschaft',
    'databaseBrowser.simple.foreignKeys': 'Verknüpfungen',
    'databaseBrowser.simple.indexes': 'Suchindizes',
    'databaseBrowser.simple.createSql': 'SQL zum Erstellen',
    'databaseBrowser.simple.copyCreateSql': 'SQL kopieren',
    'databaseBrowser.simple.createSqlCopied': 'SQL wurde kopiert',
    'databaseBrowser.loadFailed':
        'Datenbank konnte nicht gelesen werden: {error}',
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
