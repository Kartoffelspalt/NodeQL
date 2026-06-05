// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'ScratchQL Creator';

  @override
  String get blockLibrary => 'Bibliothèque de blocs';

  @override
  String get workspace => 'Espace de travail';

  @override
  String get stage => 'Scène';

  @override
  String get workspaceHint => 'Glissez des blocs ici pour créer votre script.';

  @override
  String get stageHint =>
      'Exécutez les scripts et interagissez avec les sprites.';

  @override
  String get blockWhenFlagClicked => 'quand le drapeau vert est cliqué';

  @override
  String blockMoveSteps(int steps) {
    return 'avancer de $steps pas';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'répéter $times fois';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'tourner de $degrees degrés';
  }

  @override
  String get blockForever => 'pour toujours';
}
