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

  @override
  String get desktopFeatureOnly =>
      'Bu özellik yalnızca masaüstü uygulamasında kullanılabilir.';

  @override
  String get joinConnectTables => 'Tabloları bağla';

  @override
  String get joinExistingData => 'Mevcut veriler';

  @override
  String get joinNewTable => 'Yeni tablo';

  @override
  String get joinConnectSource => 'SELECT veya FROM bağlayın';

  @override
  String get joinChooseTable => 'Tablo seç';

  @override
  String get joinChooseColumn => 'Sütun seç';

  @override
  String get joinResult => 'Sonuçtaki satırlar';

  @override
  String get joinMatchesOnly => 'Yalnızca eşleşen satırlar';

  @override
  String get joinKeepExisting => 'Tüm mevcut satırları tut';

  @override
  String get joinKeepNew => 'Tüm yeni satırları tut';

  @override
  String get joinKeepAll => 'Her iki taraftaki tüm satırlar';

  @override
  String get joinEveryPair => 'Olası tüm çiftler';

  @override
  String get joinSameNames => 'Aynı sütun adları';

  @override
  String get joinSameTable => 'Bir tablo, iki rol';

  @override
  String get joinInnerDescription =>
      'Yalnızca seçilen sütun değerleri eşleşen çiftler.';

  @override
  String get joinLeftDescription =>
      'Yeni bir eşleşme olmasa da her mevcut satırı tutar.';

  @override
  String get joinRightDescription =>
      'Mevcut bir eşleşme olmasa da her yeni satırı tutar.';

  @override
  String get joinFullDescription =>
      'Her iki taraftaki eşleşmeleri ve eşleşmeyen satırları tutar.';

  @override
  String get joinCrossDescription =>
      'Her mevcut satırı her yeni satırla koşulsuz eşler.';

  @override
  String get joinNaturalDescription =>
      'Tüm ortak sütun adlarını kullanır. Ortak ad yoksa tüm çiftleri üretir.';

  @override
  String get joinSelfDescription =>
      'İki rolü karşılaştırmak için aynı tabloyu farklı bir takma adla seçin.';

  @override
  String get joinChooseResult => 'Hangi satırlar kalsın?';

  @override
  String get joinExampleHint =>
      'Örnek: mevcut değerler 1, 2; yeni değerler 1, 3. Eşit değerleri bağlayın. Her hücre çifti bir sonuç satırıdır.';

  @override
  String get joinNullHint =>
      'NULL, eş bulunamadığını gösterir. Birden çok eşleşme birden çok satır üretir.';

  @override
  String get joinSpecialCases => 'Özel durumlar';

  @override
  String get joinClose => 'Kapat';

  @override
  String get joinPaletteDescription =>
      'Bir tablo seçin, eşleşen sütunları bağlayın ve hangi satırların kalacağına karar verin.';
}
