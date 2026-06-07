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
}
