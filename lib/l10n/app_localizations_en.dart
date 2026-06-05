// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ScratchQL Creator';

  @override
  String get blockLibrary => 'Block Library';

  @override
  String get workspace => 'Workspace';

  @override
  String get stage => 'Stage';

  @override
  String get workspaceHint => 'Drag blocks here to build your script.';

  @override
  String get stageHint => 'Run scripts and interact with sprites.';

  @override
  String get blockWhenFlagClicked => 'when green flag clicked';

  @override
  String blockMoveSteps(int steps) {
    return 'move $steps steps';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'repeat $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'turn $degrees degrees';
  }

  @override
  String get blockForever => 'forever';
}
