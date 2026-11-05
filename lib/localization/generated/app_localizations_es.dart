// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'NodeQL';

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

  @override
  String get desktopFeatureOnly =>
      'Esta función solo está disponible en la aplicación de escritorio.';

  @override
  String get joinConnectTables => 'Conectar tablas';

  @override
  String get joinExistingData => 'Datos existentes';

  @override
  String get joinNewTable => 'Tabla nueva';

  @override
  String get joinConnectSource => 'Conecta SELECT o FROM';

  @override
  String get joinChooseTable => 'Elegir tabla';

  @override
  String get joinChooseColumn => 'Elegir columna';

  @override
  String get joinResult => 'Filas del resultado';

  @override
  String get joinMatchesOnly => 'Solo filas coincidentes';

  @override
  String get joinKeepExisting => 'Conservar las existentes';

  @override
  String get joinKeepNew => 'Conservar las nuevas';

  @override
  String get joinKeepAll => 'Conservar todas de ambas';

  @override
  String get joinEveryPair => 'Todas las combinaciones';

  @override
  String get joinSameNames => 'Nombres de columna iguales';

  @override
  String get joinSameTable => 'Una tabla, dos funciones';

  @override
  String get joinInnerDescription =>
      'Solo pares cuyos valores de las columnas elegidas coincidan.';

  @override
  String get joinLeftDescription =>
      'Conserva cada fila existente, incluso sin una fila nueva coincidente.';

  @override
  String get joinRightDescription =>
      'Conserva cada fila nueva, incluso sin una fila existente coincidente.';

  @override
  String get joinFullDescription =>
      'Conserva coincidencias y filas sin pareja de ambos lados.';

  @override
  String get joinCrossDescription =>
      'Combina cada fila existente con cada fila nueva, sin condición.';

  @override
  String get joinNaturalDescription =>
      'Usa todos los nombres de columna comunes. Sin ellos, genera todas las combinaciones.';

  @override
  String get joinSelfDescription =>
      'Elige la misma tabla con otro alias para comparar dos funciones.';

  @override
  String get joinChooseResult => '¿Qué filas deben quedar?';

  @override
  String get joinExampleHint =>
      'Ejemplo: valores existentes 1, 2; nuevos 1, 3. Relaciona valores iguales. Cada par de celdas es una fila del resultado.';

  @override
  String get joinNullHint =>
      'NULL significa que falta la pareja. Varias coincidencias producen varias filas.';

  @override
  String get joinSpecialCases => 'Casos especiales';

  @override
  String get joinClose => 'Cerrar';

  @override
  String get joinPaletteDescription =>
      'Elige una tabla, conecta las columnas correspondientes y decide qué filas conservar.';
}
