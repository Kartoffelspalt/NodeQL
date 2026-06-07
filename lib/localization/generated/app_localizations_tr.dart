// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'Blok Kütüphanesi';

  @override
  String get workspace => 'Çalışma Alanı';

  @override
  String get stage => 'Sahne';

  @override
  String get workspaceHint => 'Betiği oluşturmak için blokları buraya sürükle.';

  @override
  String get stageHint => 'Betikleri çalıştır ve kuklalarla etkileşime gir.';

  @override
  String get blockWhenFlagClicked => 'yeşil bayrak tıklanınca';

  @override
  String blockMoveSteps(int steps) {
    return '$steps adım git';
  }

  @override
  String blockRepeatTimes(int times) {
    return '$times kez tekrarla';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return '$degrees derece dön';
  }

  @override
  String get blockForever => 'sürekli';
}
