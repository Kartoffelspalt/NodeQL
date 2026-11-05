// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'Libreria blocchi';

  @override
  String get workspace => 'Area di lavoro';

  @override
  String get stage => 'Palcoscenico';

  @override
  String get workspaceHint => 'Trascina qui i blocchi per costruire lo script.';

  @override
  String get stageHint => 'Esegui script e interagisci con gli sprite.';

  @override
  String get blockWhenFlagClicked => 'quando si clicca la bandiera verde';

  @override
  String blockMoveSteps(int steps) {
    return 'muovi di $steps passi';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'ripeti $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'ruota di $degrees gradi';
  }

  @override
  String get blockForever => 'per sempre';

  @override
  String get desktopFeatureOnly =>
      'Questa funzionalità è disponibile solo nell’app desktop.';

  @override
  String get joinConnectTables => 'Collega tabelle';

  @override
  String get joinExistingData => 'Dati esistenti';

  @override
  String get joinNewTable => 'Nuova tabella';

  @override
  String get joinConnectSource => 'Collega SELECT o FROM';

  @override
  String get joinChooseTable => 'Scegli tabella';

  @override
  String get joinChooseColumn => 'Scegli colonna';

  @override
  String get joinResult => 'Righe nel risultato';

  @override
  String get joinMatchesOnly => 'Solo righe corrispondenti';

  @override
  String get joinKeepExisting => 'Mantieni tutte le esistenti';

  @override
  String get joinKeepNew => 'Mantieni tutte le nuove';

  @override
  String get joinKeepAll => 'Mantieni tutte da entrambe';

  @override
  String get joinEveryPair => 'Ogni combinazione possibile';

  @override
  String get joinSameNames => 'Nomi di colonna uguali';

  @override
  String get joinSameTable => 'Una tabella, due ruoli';

  @override
  String get joinInnerDescription =>
      'Solo coppie con valori corrispondenti nelle colonne scelte.';

  @override
  String get joinLeftDescription =>
      'Mantieni ogni riga esistente, anche senza una nuova riga corrispondente.';

  @override
  String get joinRightDescription =>
      'Mantieni ogni nuova riga, anche senza una riga esistente corrispondente.';

  @override
  String get joinFullDescription =>
      'Mantieni corrispondenze e righe senza partner da entrambi i lati.';

  @override
  String get joinCrossDescription =>
      'Abbina ogni riga esistente a ogni nuova riga, senza condizione.';

  @override
  String get joinNaturalDescription =>
      'Usa tutti i nomi di colonna comuni. Se non ce ne sono, genera tutte le combinazioni.';

  @override
  String get joinSelfDescription =>
      'Scegli la stessa tabella con un altro alias per confrontare due ruoli.';

  @override
  String get joinChooseResult => 'Quali righe conservare?';

  @override
  String get joinExampleHint =>
      'Esempio: valori esistenti 1, 2; nuovi 1, 3. Collega valori uguali. Ogni coppia di celle è una riga del risultato.';

  @override
  String get joinNullHint =>
      'NULL indica un partner mancante. Più corrispondenze producono più righe.';

  @override
  String get joinSpecialCases => 'Casi speciali';

  @override
  String get joinClose => 'Chiudi';

  @override
  String get joinPaletteDescription =>
      'Scegli una tabella, collega le colonne corrispondenti e decidi quali righe mantenere.';
}
