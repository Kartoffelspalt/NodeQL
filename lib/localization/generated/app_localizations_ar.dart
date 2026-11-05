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

  @override
  String get desktopFeatureOnly => 'هذه الميزة متاحة فقط في تطبيق سطح المكتب.';

  @override
  String get joinConnectTables => 'ربط الجداول';

  @override
  String get joinExistingData => 'البيانات الحالية';

  @override
  String get joinNewTable => 'الجدول الجديد';

  @override
  String get joinConnectSource => 'اربط SELECT أو FROM';

  @override
  String get joinChooseTable => 'اختر جدولًا';

  @override
  String get joinChooseColumn => 'اختر عمودًا';

  @override
  String get joinResult => 'صفوف النتيجة';

  @override
  String get joinMatchesOnly => 'الصفوف المتطابقة فقط';

  @override
  String get joinKeepExisting => 'الاحتفاظ بكل الصفوف الحالية';

  @override
  String get joinKeepNew => 'الاحتفاظ بكل الصفوف الجديدة';

  @override
  String get joinKeepAll => 'الاحتفاظ بصفوف الجانبين';

  @override
  String get joinEveryPair => 'كل التركيبات الممكنة';

  @override
  String get joinSameNames => 'أسماء الأعمدة المتشابهة';

  @override
  String get joinSameTable => 'جدول واحد ودوران';

  @override
  String get joinInnerDescription =>
      'الأزواج التي تتطابق فيها قيم الأعمدة المختارة فقط.';

  @override
  String get joinLeftDescription => 'يحتفظ بكل صف حالي حتى دون صف جديد مطابق.';

  @override
  String get joinRightDescription => 'يحتفظ بكل صف جديد حتى دون صف حالي مطابق.';

  @override
  String get joinFullDescription =>
      'يحتفظ بالتطابقات والصفوف دون شريك من كلا الجانبين.';

  @override
  String get joinCrossDescription => 'يجمع كل صف حالي مع كل صف جديد دون شرط.';

  @override
  String get joinNaturalDescription =>
      'يستخدم كل أسماء الأعمدة المشتركة. إن لم توجد، ينتج كل التركيبات.';

  @override
  String get joinSelfDescription =>
      'اختر الجدول نفسه باسم مستعار مختلف لمقارنة دورين.';

  @override
  String get joinChooseResult => 'ما الصفوف التي تريد الاحتفاظ بها؟';

  @override
  String get joinExampleHint =>
      'مثال: القيم الحالية 1، 2 والجديدة 1، 3. نربط القيم المتساوية. كل زوج من الخلايا يمثل صف نتيجة.';

  @override
  String get joinNullHint =>
      'تعني NULL عدم وجود شريك. التطابقات المتعددة تنتج صفوفًا متعددة.';

  @override
  String get joinSpecialCases => 'حالات خاصة';

  @override
  String get joinClose => 'إغلاق';

  @override
  String get joinPaletteDescription =>
      'اختر جدولًا واربط الأعمدة المتطابقة ثم حدد الصفوف التي تريد الاحتفاظ بها.';
}
