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

  @override
  String get desktopFeatureOnly => 'この機能はデスクトップアプリでのみ利用できます。';

  @override
  String get joinConnectTables => 'テーブルを結合';

  @override
  String get joinExistingData => '既存のデータ';

  @override
  String get joinNewTable => '新しいテーブル';

  @override
  String get joinConnectSource => 'SELECT または FROM を接続';

  @override
  String get joinChooseTable => 'テーブルを選択';

  @override
  String get joinChooseColumn => '列を選択';

  @override
  String get joinResult => '結果に含める行';

  @override
  String get joinMatchesOnly => '一致する行のみ';

  @override
  String get joinKeepExisting => '既存の行をすべて残す';

  @override
  String get joinKeepNew => '新しい行をすべて残す';

  @override
  String get joinKeepAll => '両方の行をすべて残す';

  @override
  String get joinEveryPair => 'すべての組み合わせ';

  @override
  String get joinSameNames => '同じ列名で結合';

  @override
  String get joinSameTable => '1つのテーブルに2つの役割';

  @override
  String get joinInnerDescription => '選択した列の値が一致するペアのみを残します。';

  @override
  String get joinLeftDescription => '新しい行に一致しなくても、既存の行をすべて残します。';

  @override
  String get joinRightDescription => '既存の行に一致しなくても、新しい行をすべて残します。';

  @override
  String get joinFullDescription => '一致するペアと、どちらの側でも相手がいない行を残します。';

  @override
  String get joinCrossDescription => '条件なしで、既存の各行と新しい各行を組み合わせます。';

  @override
  String get joinNaturalDescription => '共通するすべての列名を使います。共通の列名がなければ全組み合わせになります。';

  @override
  String get joinSelfDescription => '同じテーブルを別のエイリアスで選び、2つの役割を比較します。';

  @override
  String get joinChooseResult => 'どの行を残しますか？';

  @override
  String get joinExampleHint => '例：既存の値は1、2、新しい値は1、3。同じ値を結びます。セルの各ペアが結果の1行です。';

  @override
  String get joinNullHint => 'NULL は一致する相手がいないことを示します。複数の一致は複数の結果行になります。';

  @override
  String get joinSpecialCases => '特殊な結合';

  @override
  String get joinClose => '閉じる';

  @override
  String get joinPaletteDescription => 'テーブルを選び、対応する列を結んで、残す行を決めます。';
}
