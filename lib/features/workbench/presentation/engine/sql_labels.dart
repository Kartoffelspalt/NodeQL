import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';

String simpleAllColumnsLabel(String languageCode) {
  final normalizedCode = languageCode.toLowerCase().split(RegExp('[-_]')).first;
  return switch (normalizedCode) {
    'de' => 'Alles',
    'fr' => 'Tout',
    'es' => 'Todo',
    'it' => 'Tutto',
    'pt' => 'Tudo',
    'tr' => 'Tümü',
    'ar' => 'الكل',
    'ja' => 'すべて',
    'ko' => '모두',
    'zh' => '全部',
    _ => 'Everything',
  };
}

String sqlLabelFor(
  BlockType type,
  SqlAbstractionMode mode,
  Map<String, dynamic> inputs,
  String languageCode,
) {
  final simpleLang = _simpleByLanguage(languageCode);
  final genericJoinUsesCondition =
      '${inputs['join_type'] ?? 'INNER'}'.trim().toUpperCase() != 'CROSS' &&
      '${inputs['join_type'] ?? 'INNER'}'.trim().toUpperCase() != 'NATURAL';
  final adv = <BlockType, String>{
    BlockType.eventGreenFlag: 'EXECUTE QUERY',
    BlockType.sqlSelect: 'SELECT [columns] FROM [table_name]',
    BlockType.sqlColumn: '[column]',
    BlockType.sqlText: 'TEXT {text}',
    BlockType.sqlFrom: 'FROM [table_name]',
    BlockType.sqlWhere: 'WHERE [column] [operator] [value]',
    BlockType.sqlOrderBy: 'ORDER BY [column] [ASC|DESC]',
    BlockType.sqlGroupBy: 'GROUP BY [column]',
    BlockType.sqlHaving: 'HAVING [aggregate]([column]) [operator] [value]',
    BlockType.sqlJoin: genericJoinUsesCondition
        ? '[JOIN_TYPE] JOIN [table]\nON [left_column] = [right_column]'
        : '[JOIN_TYPE] JOIN [table]',
    BlockType.sqlInnerJoin:
        'INNER JOIN [table]\nON [left_column] = [right_column]',
    BlockType.sqlLeftJoin:
        'LEFT JOIN [table]\nON [left_column] = [right_column]',
    BlockType.sqlRightJoin:
        'RIGHT JOIN [table]\nON [left_column] = [right_column]',
    BlockType.sqlFullJoin:
        'FULL JOIN [table]\nON [left_column] = [right_column]',
    BlockType.sqlCrossJoin: 'CROSS JOIN [table]',
    BlockType.sqlSelfJoin:
        'SELF JOIN [table]\nON [left_column] = [right_column]',
    BlockType.sqlNaturalJoin: 'NATURAL JOIN [table]',
    BlockType.sqlInsert: 'INSERT INTO [table] ([columns]) VALUES ([values])',
    BlockType.sqlUpdate:
        'UPDATE [table] SET [column] = [value] WHERE [where_column] [operator] [where_value]',
    BlockType.sqlDelete:
        'DELETE FROM [table] WHERE [where_column] [operator] [where_value]',
    BlockType.sqlCreateTable:
        'CREATE TABLE [table_name] ([column_definitions])',
    BlockType.sqlAlterTable:
        'ALTER TABLE [table_name] ADD [column_name] [datatype]',
    BlockType.sqlDropTable: 'DROP TABLE [table_name]',
    BlockType.sqlTruncate: 'TRUNCATE TABLE [table_name]',
    BlockType.sqlGrant: 'GRANT [privilege] ON [table] TO [user]',
    BlockType.sqlRevoke: 'REVOKE [privilege] ON [table] FROM [user]',
    BlockType.sqlSavepoint: 'SAVEPOINT [name]',
    BlockType.sqlRollbackToSavepoint: 'ROLLBACK TO SAVEPOINT [name]',
    BlockType.sqlCommit: 'COMMIT',
    BlockType.sqlRollback: 'ROLLBACK',
    BlockType.sqlUnion: 'UNION [sql]',
    BlockType.sqlIntersect: 'INTERSECT [sql]',
    BlockType.sqlExcept: 'EXCEPT [sql]',
    BlockType.sqlSubqueryIn: '[column] IN ([sql])',
    BlockType.sqlSubqueryAny: '[column] = ANY ([sql])',
    BlockType.sqlSubqueryAll: '[column] = ALL ([sql])',
    BlockType.sqlCount: 'COUNT([column])',
    BlockType.sqlSum: 'SUM([column])',
    BlockType.sqlAvg: 'AVG([column])',
    BlockType.sqlMin: 'MIN([column])',
    BlockType.sqlMax: 'MAX([column])',
    BlockType.sqlConcat: 'CONCAT({value}, {default})',
    BlockType.sqlSubstring: 'SUBSTRING({value})',
    BlockType.sqlLength: 'LENGTH({value})',
    BlockType.sqlUpper: 'UPPER({value})',
    BlockType.sqlLower: 'LOWER({value})',
    BlockType.sqlTrim: 'TRIM({value})',
    BlockType.sqlLeft: 'LEFT({value})',
    BlockType.sqlRight: 'RIGHT({value})',
    BlockType.sqlReplace: 'REPLACE({value})',
    BlockType.sqlCurrentDate: 'CURRENT_DATE',
    BlockType.sqlCurrentTime: 'CURRENT_TIME',
    BlockType.sqlCurrentTimestamp: 'CURRENT_TIMESTAMP',
    BlockType.sqlDatePart: 'DATE_PART({value})',
    BlockType.sqlDateAdd: 'DATE_ADD({value})',
    BlockType.sqlDateSub: 'DATE_SUB({value})',
    BlockType.sqlExtract: 'EXTRACT({value})',
    BlockType.sqlToChar: 'TO_CHAR({value})',
    BlockType.sqlTimestampDiff: 'TIMESTAMPDIFF({value})',
    BlockType.sqlDateDiff: 'DATEDIFF({value})',
    BlockType.sqlCase:
        'CASE WHEN [condition_column] [operator] [condition_value] THEN {result} ELSE {default} END',
    BlockType.sqlIf:
        'IF([condition_column] [operator] [condition_value], {value}, {default})',
    BlockType.sqlCoalesce: 'COALESCE({value}, {default})',
    BlockType.sqlNullIf: 'NULLIF({value}, {default})',
    BlockType.sqlSetTransaction: 'SET TRANSACTION [level]',
  };

  final simpleDe = <BlockType, String>{
    BlockType.eventGreenFlag: 'QUERY AUSFUEHREN',
    BlockType.sqlSelect: 'Zeige [Spalten] aus Tabelle [table_name]',
    BlockType.sqlColumn: '[Spalte]',
    BlockType.sqlText: 'Text {text}',
    BlockType.sqlFrom: 'aus Tabelle [table_name]',
    BlockType.sqlWhere: 'nur Zeilen, bei denen [Spalte] [operator] [value] ist',
    BlockType.sqlOrderBy: 'sortiere nach [Spalte] [aufsteigend|absteigend]',
    BlockType.sqlGroupBy: 'bilde Gruppen nach [Spalte]',
    BlockType.sqlHaving:
        'zeige nur Gruppen, bei denen [aggregate] von [Spalte] [operator] [value] ist',
    BlockType.sqlJoin: genericJoinUsesCondition
        ? 'verbinde mit Tabelle [table] als [JOIN_TYPE]\nwenn [linke_Spalte] = [rechte_Spalte]'
        : 'verbinde mittels [JOIN_TYPE] mit Tabelle [table]',
    BlockType.sqlInnerJoin:
        'verbinde passende Zeilen aus [table]\nwenn [linke_Spalte] = [rechte_Spalte]',
    BlockType.sqlLeftJoin:
        'verbinde [table] und behalte alle bisherigen Zeilen\nwenn [linke_Spalte] = [rechte_Spalte]',
    BlockType.sqlRightJoin:
        'verbinde [table] und behalte alle neuen Zeilen\nwenn [linke_Spalte] = [rechte_Spalte]',
    BlockType.sqlFullJoin:
        'verbinde [table] und behalte alle Zeilen beider Tabellen\nwenn [linke_Spalte] = [rechte_Spalte]',
    BlockType.sqlCrossJoin: 'verbinde kreuzweise mit Tabelle [table]',
    BlockType.sqlSelfJoin:
        'verbinde Tabelle [table] mit sich selbst\nwenn [linke_Spalte] = [rechte_Spalte]',
    BlockType.sqlNaturalJoin: 'verbinde natuerlich mit Tabelle [table]',
    BlockType.sqlInsert:
        'fuege ein in [table] ([Spalten]) die Werte ([values])',
    BlockType.sqlUpdate:
        'aendere in [table] das Feld [Spalte] auf [value], wenn [Filter_Spalte] [operator] [where_value] ist',
    BlockType.sqlDelete:
        'loesche aus [table], wenn [Filter_Spalte] [operator] [where_value] ist',
    BlockType.sqlCreateTable:
        'erstelle neue Tabelle [table_name] mit den Spalten ([Spaltendefinitionen])',
    BlockType.sqlAlterTable:
        'aendere Tabelle [table_name] fuege Spalte [Spaltenname] vom Typ [datatype] hinzu',
    BlockType.sqlDropTable: 'loesche Tabelle [table_name] permanent',
    BlockType.sqlTruncate: 'leere Tabelle [table_name] komplett',
    BlockType.sqlGrant: 'erlaube das Recht [privilege] auf [table] fuer [user]',
    BlockType.sqlRevoke:
        'entziehe das Recht [privilege] auf [table] fuer [user]',
    BlockType.sqlSavepoint: 'setze Sicherungspunkt [name]',
    BlockType.sqlRollbackToSavepoint:
        'springe zurueck zu Sicherungspunkt [name]',
    BlockType.sqlCommit: 'bestaetige Transaktion',
    BlockType.sqlRollback: 'verwerfe Transaktion',
    BlockType.sqlUnion: 'vereine mit [sql]',
    BlockType.sqlIntersect: 'schneide mit [sql]',
    BlockType.sqlExcept: 'entferne Treffer aus [sql]',
    BlockType.sqlSubqueryIn: '[Spalte] ist in ([sql])',
    BlockType.sqlSubqueryAny: '[Spalte] entspricht irgendeinem aus ([sql])',
    BlockType.sqlSubqueryAll: '[Spalte] entspricht allen aus ([sql])',
    BlockType.sqlCount: 'zaehle [Spalte]',
    BlockType.sqlSum: 'summiere [Spalte]',
    BlockType.sqlAvg: 'berechne Durchschnitt von [Spalte]',
    BlockType.sqlMin: 'kleinster Wert von [Spalte]',
    BlockType.sqlMax: 'groesster Wert von [Spalte]',
    BlockType.sqlConcat: 'verbinde Texte {value} und {default}',
    BlockType.sqlSubstring: 'Textausschnitt aus {value}',
    BlockType.sqlLength: 'Laenge von {value}',
    BlockType.sqlUpper: '{value} in Grossbuchstaben',
    BlockType.sqlLower: '{value} in Kleinbuchstaben',
    BlockType.sqlTrim: 'Leerzeichen von {value} entfernen',
    BlockType.sqlLeft: 'linke Zeichen von {value}',
    BlockType.sqlRight: 'rechte Zeichen von {value}',
    BlockType.sqlReplace: 'ersetze Text in {value}',
    BlockType.sqlCurrentDate: 'aktuelles Datum',
    BlockType.sqlCurrentTime: 'aktuelle Uhrzeit',
    BlockType.sqlCurrentTimestamp: 'aktueller Zeitstempel',
    BlockType.sqlDatePart: 'Datumsteil aus {value}',
    BlockType.sqlDateAdd: 'Zeit zu {value} addieren',
    BlockType.sqlDateSub: 'Zeit von {value} abziehen',
    BlockType.sqlExtract: 'Datumsteil extrahieren aus {value}',
    BlockType.sqlToChar: '{value} als Text formatieren',
    BlockType.sqlTimestampDiff: 'Zeitstempel-Differenz berechnen',
    BlockType.sqlDateDiff: 'Datums-Differenz berechnen',
    BlockType.sqlCase:
        'falls [condition_column] [operator] [condition_value] ist, dann {result}, sonst {default}',
    BlockType.sqlIf:
        'wenn [condition_column] [operator] [condition_value] ist, dann {value}, sonst {default}',
    BlockType.sqlCoalesce: 'nutze {value} sonst {default}',
    BlockType.sqlNullIf: 'setze auf leer wenn {value} gleich {default}',
    BlockType.sqlSetTransaction: 'setze Transaktionsstufe [level]',
  };

  final simpleEn = <BlockType, String>{
    BlockType.eventGreenFlag: 'RUN QUERY',
    BlockType.sqlSelect: 'Show [columns] from table [table_name]',
    BlockType.sqlColumn: '[column]',
    BlockType.sqlText: 'text {text}',
    BlockType.sqlFrom: 'from table [table_name]',
    BlockType.sqlWhere: 'only rows where [column] [operator] [value]',
    BlockType.sqlOrderBy: 'sort by [column] [ascending|descending]',
    BlockType.sqlGroupBy: 'make groups by [column]',
    BlockType.sqlHaving:
        'keep groups where [aggregate] of [column] [operator] [value]',
    BlockType.sqlJoin: genericJoinUsesCondition
        ? 'join with [table] using [JOIN_TYPE]\nwhen [left_column] = [right_column]'
        : 'join with [table] using [JOIN_TYPE]',
    BlockType.sqlInnerJoin:
        'join matching rows from [table]\nwhen [left_column] = [right_column]',
    BlockType.sqlLeftJoin:
        'join [table] and keep all previous rows\nwhen [left_column] = [right_column]',
    BlockType.sqlRightJoin:
        'join [table] and keep all new rows\nwhen [left_column] = [right_column]',
    BlockType.sqlFullJoin:
        'join [table] and keep all rows from both tables\nwhen [left_column] = [right_column]',
    BlockType.sqlCrossJoin: 'cross-join with table [table]',
    BlockType.sqlSelfJoin:
        'join table [table] with itself\nwhen [left_column] = [right_column]',
    BlockType.sqlNaturalJoin: 'natural-join with table [table]',
    BlockType.sqlInsert: 'add to [table] ([columns]) values ([values])',
    BlockType.sqlUpdate:
        'change [table] set [column] to [value] when [where_column] [operator] [where_value]',
    BlockType.sqlDelete:
        'delete from [table] when [where_column] [operator] [where_value]',
    BlockType.sqlCreateTable:
        'create new table [table_name] with columns ([column_definitions])',
    BlockType.sqlAlterTable:
        'change table [table_name] add column [column_name] with type [datatype]',
    BlockType.sqlDropTable: 'delete table [table_name] permanently',
    BlockType.sqlTruncate: 'clear table [table_name] completely',
    BlockType.sqlGrant: 'allow [privilege] on [table] for [user]',
    BlockType.sqlRevoke: 'remove [privilege] on [table] for [user]',
    BlockType.sqlSavepoint: 'set savepoint [name]',
    BlockType.sqlRollbackToSavepoint: 'go back to savepoint [name]',
    BlockType.sqlCommit: 'confirm transaction',
    BlockType.sqlRollback: 'cancel transaction',
    BlockType.sqlUnion: 'combine with [sql]',
    BlockType.sqlIntersect: 'keep overlap with [sql]',
    BlockType.sqlExcept: 'remove matches from [sql]',
    BlockType.sqlSubqueryIn: '[column] is in ([sql])',
    BlockType.sqlSubqueryAny: '[column] equals any value from ([sql])',
    BlockType.sqlSubqueryAll: '[column] equals all values from ([sql])',
    BlockType.sqlCount: 'count [column]',
    BlockType.sqlSum: 'sum [column]',
    BlockType.sqlAvg: 'average of [column]',
    BlockType.sqlMin: 'smallest value of [column]',
    BlockType.sqlMax: 'largest value of [column]',
    BlockType.sqlConcat: 'combine texts {value} and {default}',
    BlockType.sqlSubstring: 'text part from {value}',
    BlockType.sqlLength: 'length of {value}',
    BlockType.sqlUpper: '{value} as uppercase',
    BlockType.sqlLower: '{value} as lowercase',
    BlockType.sqlTrim: 'remove spaces from {value}',
    BlockType.sqlLeft: 'left characters of {value}',
    BlockType.sqlRight: 'right characters of {value}',
    BlockType.sqlReplace: 'replace text in {value}',
    BlockType.sqlCurrentDate: 'current date',
    BlockType.sqlCurrentTime: 'current time',
    BlockType.sqlCurrentTimestamp: 'current timestamp',
    BlockType.sqlDatePart: 'date part from {value}',
    BlockType.sqlDateAdd: 'add time to {value}',
    BlockType.sqlDateSub: 'subtract time from {value}',
    BlockType.sqlExtract: 'extract date part from {value}',
    BlockType.sqlToChar: 'format {value} as text',
    BlockType.sqlTimestampDiff: 'timestamp difference',
    BlockType.sqlDateDiff: 'date difference',
    BlockType.sqlCase:
        'if [condition_column] [operator] [condition_value] then {result} else {default}',
    BlockType.sqlIf:
        'if [condition_column] [operator] [condition_value] then {value} else {default}',
    BlockType.sqlCoalesce: 'use {value} otherwise {default}',
    BlockType.sqlNullIf: 'set empty if {value} equals {default}',
    BlockType.sqlSetTransaction: 'set transaction level [level]',
  };

  final simpleBase = languageCode == 'de' ? simpleDe : simpleEn;
  final simple = {...simpleBase, ...?simpleLang};
  final map = mode == SqlAbstractionMode.advanced ? adv : simple;
  if (type == BlockType.sqlSelect && inputs['separate_from'] == true) {
    if (mode == SqlAbstractionMode.advanced) return 'SELECT [columns]';
    return languageCode == 'de' ? 'Zeige [Spalten]' : 'Show [columns]';
  }
  return map[type] ?? simpleBase[type] ?? adv[type] ?? type.name;
}

Map<BlockType, String>? _simpleByLanguage(String languageCode) {
  switch (languageCode) {
    case 'fr':
      return <BlockType, String>{
        BlockType.eventGreenFlag: 'EXECUTER REQUETE',
        BlockType.sqlSelect: 'affiche [columns] de la table [table_name]',
        BlockType.sqlWhere: 'si [condition]',
        BlockType.sqlOrderBy: 'trie par [column] {croissant|décroissant}',
      };
    case 'es':
      return <BlockType, String>{
        BlockType.eventGreenFlag: 'EJECUTAR CONSULTA',
        BlockType.sqlSelect: 'muestra [columns] de tabla [table_name]',
        BlockType.sqlWhere: 'si [condition]',
        BlockType.sqlOrderBy: 'ordena por [column] {ascendente|descendente}',
      };
    default:
      return null;
  }
}
