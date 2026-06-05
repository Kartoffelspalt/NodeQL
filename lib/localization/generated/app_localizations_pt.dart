// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'ScratchQL Creator';

  @override
  String get blockLibrary => 'Biblioteca de blocos';

  @override
  String get workspace => 'Área de trabalho';

  @override
  String get stage => 'Palco';

  @override
  String get workspaceHint => 'Arraste blocos para cá para montar seu script.';

  @override
  String get stageHint => 'Execute scripts e interaja com sprites.';

  @override
  String get blockWhenFlagClicked => 'quando a bandeira verde for clicada';

  @override
  String blockMoveSteps(int steps) {
    return 'mova $steps passos';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'repita $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'gire $degrees graus';
  }

  @override
  String get blockForever => 'para sempre';
}
