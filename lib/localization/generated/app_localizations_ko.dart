// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => '블록 라이브러리';

  @override
  String get workspace => '작업 공간';

  @override
  String get stage => '무대';

  @override
  String get workspaceHint => '스크립트를 만들 블록을 여기로 드래그하세요.';

  @override
  String get stageHint => '스크립트를 실행하고 스프라이트와 상호작용하세요.';

  @override
  String get blockWhenFlagClicked => '초록 깃발을 클릭했을 때';

  @override
  String blockMoveSteps(int steps) {
    return '$steps 만큼 움직이기';
  }

  @override
  String blockRepeatTimes(int times) {
    return '$times번 반복';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return '$degrees도 회전';
  }

  @override
  String get blockForever => '계속 반복';

  @override
  String get desktopFeatureOnly => '이 기능은 데스크톱 앱에서만 사용할 수 있습니다.';

  @override
  String get joinConnectTables => '테이블 연결';

  @override
  String get joinExistingData => '기존 데이터';

  @override
  String get joinNewTable => '새 테이블';

  @override
  String get joinConnectSource => 'SELECT 또는 FROM 연결';

  @override
  String get joinChooseTable => '테이블 선택';

  @override
  String get joinChooseColumn => '열 선택';

  @override
  String get joinResult => '결과에 포함할 행';

  @override
  String get joinMatchesOnly => '일치하는 행만';

  @override
  String get joinKeepExisting => '기존 행 모두 유지';

  @override
  String get joinKeepNew => '새 행 모두 유지';

  @override
  String get joinKeepAll => '양쪽 행 모두 유지';

  @override
  String get joinEveryPair => '가능한 모든 조합';

  @override
  String get joinSameNames => '같은 열 이름으로 연결';

  @override
  String get joinSameTable => '한 테이블, 두 역할';

  @override
  String get joinInnerDescription => '선택한 열의 값이 일치하는 쌍만 남깁니다.';

  @override
  String get joinLeftDescription => '일치하는 새 행이 없어도 기존 행을 모두 유지합니다.';

  @override
  String get joinRightDescription => '일치하는 기존 행이 없어도 새 행을 모두 유지합니다.';

  @override
  String get joinFullDescription => '일치하는 쌍과 양쪽의 짝이 없는 행을 유지합니다.';

  @override
  String get joinCrossDescription => '조건 없이 기존의 각 행을 새 테이블의 모든 행과 조합합니다.';

  @override
  String get joinNaturalDescription =>
      '공통된 모든 열 이름을 사용합니다. 공통 이름이 없으면 모든 조합을 만듭니다.';

  @override
  String get joinSelfDescription => '같은 테이블을 다른 별칭으로 선택하여 두 역할을 비교합니다.';

  @override
  String get joinChooseResult => '어떤 행을 유지할까요?';

  @override
  String get joinExampleHint =>
      '예: 기존 값은 1, 2이고 새 값은 1, 3입니다. 같은 값을 연결합니다. 셀 한 쌍이 결과의 한 행입니다.';

  @override
  String get joinNullHint => 'NULL은 짝을 찾지 못했다는 뜻입니다. 여러 일치 항목은 여러 결과 행을 만듭니다.';

  @override
  String get joinSpecialCases => '특수한 경우';

  @override
  String get joinClose => '닫기';

  @override
  String get joinPaletteDescription => '테이블을 고르고, 일치하는 열을 연결한 다음 유지할 행을 정하세요.';
}
