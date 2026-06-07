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
}
