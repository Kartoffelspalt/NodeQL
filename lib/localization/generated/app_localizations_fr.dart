// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'Bibliothèque de blocs';

  @override
  String get workspace => 'Espace de travail';

  @override
  String get stage => 'Scène';

  @override
  String get workspaceHint => 'Glissez des blocs ici pour créer votre script.';

  @override
  String get stageHint =>
      'Exécutez les scripts et interagissez avec les sprites.';

  @override
  String get blockWhenFlagClicked => 'quand le drapeau vert est cliqué';

  @override
  String blockMoveSteps(int steps) {
    return 'avancer de $steps pas';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'répéter $times fois';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'tourner de $degrees degrés';
  }

  @override
  String get blockForever => 'pour toujours';

  @override
  String get desktopFeatureOnly =>
      'Cette fonctionnalité est disponible uniquement dans l’application de bureau.';

  @override
  String get joinConnectTables => 'Relier les tables';

  @override
  String get joinExistingData => 'Données existantes';

  @override
  String get joinNewTable => 'Nouvelle table';

  @override
  String get joinConnectSource => 'Relier SELECT ou FROM';

  @override
  String get joinChooseTable => 'Choisir une table';

  @override
  String get joinChooseColumn => 'Choisir une colonne';

  @override
  String get joinResult => 'Lignes du résultat';

  @override
  String get joinMatchesOnly => 'Lignes correspondantes';

  @override
  String get joinKeepExisting => 'Garder toutes les existantes';

  @override
  String get joinKeepNew => 'Garder toutes les nouvelles';

  @override
  String get joinKeepAll => 'Tout garder des deux côtés';

  @override
  String get joinEveryPair => 'Toutes les combinaisons';

  @override
  String get joinSameNames => 'Noms de colonnes identiques';

  @override
  String get joinSameTable => 'Une table, deux rôles';

  @override
  String get joinInnerDescription =>
      'Uniquement les paires dont les valeurs des colonnes choisies correspondent.';

  @override
  String get joinLeftDescription =>
      'Garder chaque ligne existante, même sans nouvelle ligne correspondante.';

  @override
  String get joinRightDescription =>
      'Garder chaque nouvelle ligne, même sans ligne existante correspondante.';

  @override
  String get joinFullDescription =>
      'Garder les correspondances et les lignes sans partenaire des deux côtés.';

  @override
  String get joinCrossDescription =>
      'Associer chaque ligne existante à chaque nouvelle ligne, sans condition.';

  @override
  String get joinNaturalDescription =>
      'Utiliser tous les noms de colonnes communs. Sans nom commun, produire toutes les combinaisons.';

  @override
  String get joinSelfDescription =>
      'Choisir la même table avec un autre alias pour comparer deux rôles.';

  @override
  String get joinChooseResult => 'Quelles lignes conserver ?';

  @override
  String get joinExampleHint =>
      'Exemple : valeurs existantes 1, 2 ; nouvelles 1, 3. Relier les valeurs égales. Chaque paire de cellules est une ligne du résultat.';

  @override
  String get joinNullHint =>
      'NULL indique un partenaire absent. Plusieurs correspondances donnent plusieurs lignes.';

  @override
  String get joinSpecialCases => 'Cas particuliers';

  @override
  String get joinClose => 'Fermer';

  @override
  String get joinPaletteDescription =>
      'Choisissez une table, reliez les colonnes correspondantes et décidez quelles lignes garder.';
}
