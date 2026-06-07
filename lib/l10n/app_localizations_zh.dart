// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => '积木库';

  @override
  String get workspace => '工作区';

  @override
  String get stage => '舞台';

  @override
  String get workspaceHint => '将积木拖到这里来构建脚本。';

  @override
  String get stageHint => '运行脚本并与角色互动。';

  @override
  String get blockWhenFlagClicked => '当绿旗被点击';

  @override
  String blockMoveSteps(int steps) {
    return '移动 $steps 步';
  }

  @override
  String blockRepeatTimes(int times) {
    return '重复 $times 次';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return '旋转 $degrees 度';
  }

  @override
  String get blockForever => '重复执行';
}
