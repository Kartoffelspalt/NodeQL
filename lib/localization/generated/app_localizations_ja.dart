// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'ブロックライブラリ';

  @override
  String get workspace => 'ワークスペース';

  @override
  String get stage => 'ステージ';

  @override
  String get workspaceHint => 'ブロックをここにドラッグしてスクリプトを作成します。';

  @override
  String get stageHint => 'スクリプトを実行してスプライトを操作します。';

  @override
  String get blockWhenFlagClicked => '緑の旗が押されたとき';

  @override
  String blockMoveSteps(int steps) {
    return '$steps歩動かす';
  }

  @override
  String blockRepeatTimes(int times) {
    return '$times回繰り返す';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return '$degrees度回す';
  }

  @override
  String get blockForever => 'ずっと';
}
