// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'NodeQL';

  @override
  String get blockLibrary => 'Biblioteca de blocos';

  @override
  String get workspace => 'Área de trabalho';

  @override
  String get stage => 'Palco';

  @override
  String get workspaceHint => 'Arraste blocos para cá para montar seu script.';

  @override
  String get stageHint => 'Execute scripts e interaja com sprites.';

  @override
  String get blockWhenFlagClicked => 'quando a bandeira verde for clicada';

  @override
  String blockMoveSteps(int steps) {
    return 'mova $steps passos';
  }

  @override
  String blockRepeatTimes(int times) {
    return 'repita $times';
  }

  @override
  String blockTurnDegrees(int degrees) {
    return 'gire $degrees graus';
  }

  @override
  String get blockForever => 'para sempre';

  @override
  String get desktopFeatureOnly =>
      'Esta funcionalidade está disponível apenas na aplicação para computador.';

  @override
  String get joinConnectTables => 'Ligar tabelas';

  @override
  String get joinExistingData => 'Dados existentes';

  @override
  String get joinNewTable => 'Nova tabela';

  @override
  String get joinConnectSource => 'Ligar SELECT ou FROM';

  @override
  String get joinChooseTable => 'Escolher tabela';

  @override
  String get joinChooseColumn => 'Escolher coluna';

  @override
  String get joinResult => 'Linhas no resultado';

  @override
  String get joinMatchesOnly => 'Apenas correspondências';

  @override
  String get joinKeepExisting => 'Manter todas as existentes';

  @override
  String get joinKeepNew => 'Manter todas as novas';

  @override
  String get joinKeepAll => 'Manter todas de ambas';

  @override
  String get joinEveryPair => 'Todas as combinações';

  @override
  String get joinSameNames => 'Nomes de coluna iguais';

  @override
  String get joinSameTable => 'Uma tabela, dois papéis';

  @override
  String get joinInnerDescription =>
      'Apenas pares cujos valores das colunas escolhidas correspondem.';

  @override
  String get joinLeftDescription =>
      'Mantém cada linha existente, mesmo sem uma nova linha correspondente.';

  @override
  String get joinRightDescription =>
      'Mantém cada nova linha, mesmo sem uma linha existente correspondente.';

  @override
  String get joinFullDescription =>
      'Mantém correspondências e linhas sem par dos dois lados.';

  @override
  String get joinCrossDescription =>
      'Combina cada linha existente com cada nova linha, sem condição.';

  @override
  String get joinNaturalDescription =>
      'Usa todos os nomes de coluna comuns. Sem nomes comuns, gera todas as combinações.';

  @override
  String get joinSelfDescription =>
      'Escolhe a mesma tabela com outro alias para comparar dois papéis.';

  @override
  String get joinChooseResult => 'Que linhas devem ficar?';

  @override
  String get joinExampleHint =>
      'Exemplo: valores existentes 1, 2; novos 1, 3. Liga valores iguais. Cada par de células é uma linha do resultado.';

  @override
  String get joinNullHint =>
      'NULL significa que falta o par. Várias correspondências produzem várias linhas.';

  @override
  String get joinSpecialCases => 'Casos especiais';

  @override
  String get joinClose => 'Fechar';

  @override
  String get joinPaletteDescription =>
      'Escolhe uma tabela, liga as colunas correspondentes e decide que linhas manter.';
}
