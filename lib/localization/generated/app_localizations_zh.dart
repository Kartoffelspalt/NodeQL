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

  @override
  String get desktopFeatureOnly => '此功能仅在桌面应用中可用。';

  @override
  String get joinConnectTables => '连接表';

  @override
  String get joinExistingData => '已有数据';

  @override
  String get joinNewTable => '新增表';

  @override
  String get joinConnectSource => '连接 SELECT 或 FROM';

  @override
  String get joinChooseTable => '选择表';

  @override
  String get joinChooseColumn => '选择列';

  @override
  String get joinResult => '结果中的行';

  @override
  String get joinMatchesOnly => '仅保留匹配行';

  @override
  String get joinKeepExisting => '保留全部已有行';

  @override
  String get joinKeepNew => '保留全部新增行';

  @override
  String get joinKeepAll => '保留两侧全部行';

  @override
  String get joinEveryPair => '所有可能的组合';

  @override
  String get joinSameNames => '按相同列名匹配';

  @override
  String get joinSameTable => '同一张表，两种角色';

  @override
  String get joinInnerDescription => '仅保留所选列值匹配的行对。';

  @override
  String get joinLeftDescription => '保留每一条已有行，即使没有匹配的新增行。';

  @override
  String get joinRightDescription => '保留每一条新增行，即使没有匹配的已有行。';

  @override
  String get joinFullDescription => '保留匹配的行对和两侧未匹配的行。';

  @override
  String get joinCrossDescription => '将每一条已有行与每一条新增行组合，无需匹配条件。';

  @override
  String get joinNaturalDescription => '使用所有同名列。没有同名列时，生成所有可能的组合。';

  @override
  String get joinSelfDescription => '再次选择同一张表并使用不同别名，以比较两种角色。';

  @override
  String get joinChooseResult => '要保留哪些行？';

  @override
  String get joinExampleHint => '示例：已有值为 1、2，新增值为 1、3。连接相同的值。每对单元格代表一条结果行。';

  @override
  String get joinNullHint => 'NULL 表示没有找到匹配对象。多个匹配项会生成多条结果行。';

  @override
  String get joinSpecialCases => '特殊情况';

  @override
  String get joinClose => '关闭';

  @override
  String get joinPaletteDescription => '选择一张表，连接匹配的列，然后决定保留哪些行。';
}
