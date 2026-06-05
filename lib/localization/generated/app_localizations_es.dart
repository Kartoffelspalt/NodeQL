// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'ScratchQL Creator';

  @override
  String get blockLibrary => 'Biblioteca de bloques';

  @override
  String get workspace => 'Espacio de trabajo';

  @override
  String get stage => 'Escenario';

  @override
  String get workspaceHint => 'Arrastra bloques aquí para crear tu script.';

  @override
  String get stageHint => 'Ejecuta scripts e interactúa con sprites.';

  @override
  String get blockWhenFlagClicked => 'al hacer clic en la bandera verde';

  @override
  String blockMoveSteps(int steps) {
    return 'mover $steps pasos';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'repetir $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'girar $degrees grados';
  }

  @override
  String get blockForever => 'por siempre';
}
