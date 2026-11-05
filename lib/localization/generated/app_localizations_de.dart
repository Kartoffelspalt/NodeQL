// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'Block-Bibliothek';

  @override
  String get workspace => 'Arbeitsbereich';

  @override
  String get stage => 'Bühne';

  @override
  String get workspaceHint => 'Ziehe Blöcke hierher, um dein Skript zu bauen.';

  @override
  String get stageHint => 'Führe Skripte aus und interagiere mit Sprites.';

  @override
  String get blockWhenFlagClicked => 'Wenn grüne Flagge angeklickt';

  @override
  String blockMoveSteps(int steps) {
    return 'gehe $steps Schritte';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'wiederhole $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'drehe dich um $degrees Grad';
  }

  @override
  String get blockForever => 'fortlaufend';

  @override
  String get desktopFeatureOnly =>
      'Dieses Feature ist nur in der Desktop App verfügbar.';

  @override
  String get joinConnectTables => 'Tabellen verbinden';

  @override
  String get joinExistingData => 'Bisherige Daten';

  @override
  String get joinNewTable => 'Neue Tabelle';

  @override
  String get joinConnectSource => 'SELECT oder FROM verbinden';

  @override
  String get joinChooseTable => 'Tabelle wählen';

  @override
  String get joinChooseColumn => 'Spalte wählen';

  @override
  String get joinResult => 'Zeilen im Ergebnis';

  @override
  String get joinMatchesOnly => 'Nur passende Zeilen';

  @override
  String get joinKeepExisting => 'Alle bisherigen behalten';

  @override
  String get joinKeepNew => 'Alle neuen behalten';

  @override
  String get joinKeepAll => 'Alle aus beiden behalten';

  @override
  String get joinEveryPair => 'Jede mögliche Kombination';

  @override
  String get joinSameNames => 'Gleiche Spaltennamen';

  @override
  String get joinSameTable => 'Eine Tabelle, zwei Rollen';

  @override
  String get joinInnerDescription =>
      'Nur Paare, bei denen die gewählten Spaltenwerte zueinander passen.';

  @override
  String get joinLeftDescription =>
      'Jede bisherige Zeile bleibt, auch ohne passende neue Zeile.';

  @override
  String get joinRightDescription =>
      'Jede neue Zeile bleibt, auch ohne passende bisherige Zeile.';

  @override
  String get joinFullDescription =>
      'Passende Paare und Zeilen ohne Partner aus beiden Seiten bleiben.';

  @override
  String get joinCrossDescription =>
      'Jede bisherige mit jeder neuen Zeile kombinieren. Ohne Bedingung.';

  @override
  String get joinNaturalDescription =>
      'Alle gleich benannten Spalten verwenden. Gibt es keine, wird jede Zeile mit jeder kombiniert.';

  @override
  String get joinSelfDescription =>
      'Dieselbe Tabelle noch einmal mit anderem Alias wählen, um zwei Rollen zu vergleichen.';

  @override
  String get joinChooseResult => 'Welche Zeilen sollen bleiben?';

  @override
  String get joinExampleHint =>
      'Beispiel: bisherige Werte 1, 2; neue Werte 1, 3. Gleiche Werte verbinden. Jedes Zellenpaar ist eine Ergebniszeile.';

  @override
  String get joinNullHint =>
      'NULL bedeutet: kein Partner gefunden. Mehrere Treffer ergeben mehrere Ergebniszeilen.';

  @override
  String get joinSpecialCases => 'Sonderfälle';

  @override
  String get joinClose => 'Schließen';

  @override
  String get joinPaletteDescription =>
      'Tabelle wählen, passende Spalten verbinden und entscheiden, welche Zeilen bleiben.';
}
