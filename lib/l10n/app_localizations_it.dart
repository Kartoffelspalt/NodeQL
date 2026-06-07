// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'Libreria blocchi';

  @override
  String get workspace => 'Area di lavoro';

  @override
  String get stage => 'Palcoscenico';

  @override
  String get workspaceHint => 'Trascina qui i blocchi per costruire lo script.';

  @override
  String get stageHint => 'Esegui script e interagisci con gli sprite.';

  @override
  String get blockWhenFlagClicked => 'quando si clicca la bandiera verde';

  @override
  String blockMoveSteps(int steps) {
    return 'muovi di $steps passi';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'ripeti $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'ruota di $degrees gradi';
  }

  @override
  String get blockForever => 'per sempre';
}
