// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'NodeQL';

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

  @override
  String get desktopFeatureOnly =>
      'This feature is only available in the desktop app.';

  @override
  String get joinConnectTables => 'Connect tables';

  @override
  String get joinExistingData => 'Existing data';

  @override
  String get joinNewTable => 'New table';

  @override
  String get joinConnectSource => 'Connect SELECT or FROM';

  @override
  String get joinChooseTable => 'Choose table';

  @override
  String get joinChooseColumn => 'Choose column';

  @override
  String get joinResult => 'Rows in the result';

  @override
  String get joinMatchesOnly => 'Matching rows only';

  @override
  String get joinKeepExisting => 'Keep all existing rows';

  @override
  String get joinKeepNew => 'Keep all new rows';

  @override
  String get joinKeepAll => 'Keep all rows from both';

  @override
  String get joinEveryPair => 'Every possible pair';

  @override
  String get joinSameNames => 'Match column names';

  @override
  String get joinSameTable => 'Same table, two roles';

  @override
  String get joinInnerDescription =>
      'Only pairs whose selected column values match.';

  @override
  String get joinLeftDescription =>
      'Keep every existing row, even without a matching new row.';

  @override
  String get joinRightDescription =>
      'Keep every new row, even without a matching existing row.';

  @override
  String get joinFullDescription =>
      'Keep matches and unmatched rows from either side.';

  @override
  String get joinCrossDescription =>
      'Pair every existing row with every new row. No matching condition.';

  @override
  String get joinNaturalDescription =>
      'Use all shared column names. With none, produce every possible pair.';

  @override
  String get joinSelfDescription =>
      'Choose the same table again with a different alias to compare two roles.';

  @override
  String get joinChooseResult => 'Which rows should stay?';

  @override
  String get joinExampleHint =>
      'Example: existing values 1, 2; new values 1, 3. Match equal values. Each pair of cells is one result row.';

  @override
  String get joinNullHint =>
      'NULL means that no partner was found. Several matches produce several result rows.';

  @override
  String get joinSpecialCases => 'Special cases';

  @override
  String get joinClose => 'Close';

  @override
  String get joinPaletteDescription =>
      'Choose a table, connect matching columns, then decide which rows to keep.';
}
