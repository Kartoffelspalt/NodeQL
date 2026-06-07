// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'مكتبة الكتل';

  @override
  String get workspace => 'مساحة العمل';

  @override
  String get stage => 'المنصة';

  @override
  String get workspaceHint => 'اسحب الكتل إلى هنا لبناء البرنامج.';

  @override
  String get stageHint => 'شغّل البرامج وتفاعل مع الكائنات.';

  @override
  String get blockWhenFlagClicked => 'عند النقر على العلم الأخضر';

  @override
  String blockMoveSteps(int steps) {
    return 'تحرك $steps خطوات';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'كرر $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'استدر $degrees درجة';
  }

  @override
  String get blockForever => 'إلى الأبد';
}
