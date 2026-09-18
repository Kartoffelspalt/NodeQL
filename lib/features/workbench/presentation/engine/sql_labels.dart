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
  if (type == BlockType.sqlText && inputs['literal_type'] != null) {
    return switch ('${inputs['literal_type']}'.trim().toLowerCase()) {
      'null' => 'NULL',
      'integer' => 'INT {text}',
      'real' => 'REAL {text}',
      'blob' => 'BLOB {text}',
      _ => 'TEXT {text}',
    };
  }
  if (type == BlockType.sqlPragma) {
    final pragma = '${inputs['pragma'] ?? 'foreign_keys'}'.toLowerCase();
    final de = languageCode.toLowerCase().startsWith('de');
    if (pragma == 'database_list') {
      return mode == SqlAbstractionMode.advanced
          ? 'PRAGMA [pragma]'
          : (de ? 'zeige [pragma]' : 'show [pragma]');
    }
    if (pragma == 'table_info') {
      return mode == SqlAbstractionMode.advanced
          ? 'PRAGMA [pragma]([pragma_value])'
          : (de
                ? 'zeige [pragma] fuer [pragma_value]'
                : 'show [pragma] for [pragma_value]');
    }
    return mode == SqlAbstractionMode.advanced
        ? 'PRAGMA [pragma] = [pragma_value]'
        : (de
              ? 'konfiguriere [pragma] als [pragma_value]'
              : 'configure [pragma] as [pragma_value]');
  }
  final simpleLang = _simpleByLanguage(languageCode);
  final genericJoinUsesCondition =
      '${inputs['join_type'] ?? 'INNER'}'.trim().toUpperCase() != 'CROSS' &&
      '${inputs['join_type'] ?? 'INNER'}'.trim().toUpperCase() != 'NATURAL';
  final adv = <BlockType, String>{
    BlockType.eventGreenFlag: 'EXECUTE QUERY',
    BlockType.sqlSelect:
        'SELECT [select_mode] [columns] FROM [table_name] AS [table_alias]',
    BlockType.sqlColumn: '[column]',
    BlockType.sqlText: 'TEXT {text}',
    BlockType.sqlAlias: '{value} AS [alias]',
    BlockType.sqlFrom: 'FROM [table_name] AS [table_alias]',
    BlockType.sqlWhere: 'WHERE [negation] [column] [operator] [value]',
    BlockType.sqlAnd: 'AND [negation] [column] [operator] [value]',
    BlockType.sqlOr: 'OR [negation] [column] [operator] [value]',
    BlockType.sqlOrderBy: 'ORDER BY [column] [ASC|DESC]',
    BlockType.sqlLimit: 'LIMIT [count] OFFSET [offset]',
    BlockType.sqlGroupBy: 'GROUP BY [column]',
    BlockType.sqlHaving: 'HAVING [aggregate]([column]) [operator] [value]',
    BlockType.sqlJoin: genericJoinUsesCondition
        ? '[JOIN_TYPE] JOIN [table] AS [table_alias]\nON [left_column] [operator] [right_column]'
        : '[JOIN_TYPE] JOIN [table] AS [table_alias]',
    BlockType.sqlInnerJoin:
        'INNER JOIN [table] AS [table_alias]\nON [left_column] [operator] [right_column]',
    BlockType.sqlLeftJoin:
        'LEFT JOIN [table] AS [table_alias]\nON [left_column] [operator] [right_column]',
    BlockType.sqlRightJoin:
        'RIGHT JOIN [table] AS [table_alias]\nON [left_column] [operator] [right_column]',
    BlockType.sqlFullJoin:
        'FULL JOIN [table] AS [table_alias]\nON [left_column] [operator] [right_column]',
    BlockType.sqlCrossJoin: 'CROSS JOIN [table] AS [table_alias]',
    BlockType.sqlSelfJoin:
        'SELF JOIN [table] AS [table_alias]\nON [left_column] [operator] [right_column]',
    BlockType.sqlNaturalJoin: 'NATURAL JOIN [table] AS [table_alias]',
    BlockType.sqlInsert: 'INSERT INTO [table] ([columns]) VALUES ([values])',
    BlockType.sqlInsertOrReplace:
        'INSERT OR REPLACE INTO [table] ([columns]) VALUES ([values])',
    BlockType.sqlUpsert:
        'INSERT INTO [table] ([columns]) VALUES ([values])\nON CONFLICT ([conflict_columns]) [action] SET [assignments]',
    BlockType.sqlUpdate:
        'UPDATE [table] SET [column] = [value] WHERE [where_column] [operator] [where_value]',
    BlockType.sqlDelete:
        'DELETE FROM [table] WHERE [where_column] [operator] [where_value]',
    BlockType.sqlCreateTable:
        'CREATE TABLE [if_not_exists] [table_name]\n([column_definitions])',
    BlockType.sqlCreateIndex:
        'CREATE [unique] INDEX [if_not_exists] [name]\nON [table] ([columns])',
    BlockType.sqlDropIndex: 'DROP INDEX [if_exists] [name]',
    BlockType.sqlCreateView:
        'CREATE [temporary] VIEW [if_not_exists] [name]\nAS [sql]',
    BlockType.sqlDropView: 'DROP VIEW [if_exists] [name]',
    BlockType.sqlCreateTrigger:
        'CREATE [temporary] TRIGGER [if_not_exists] [name]\n[timing] [event] ON [table] WHEN [when] DO [body]',
    BlockType.sqlDropTrigger: 'DROP TRIGGER [if_exists] [name]',
    BlockType.sqlCreateVirtualTable:
        'CREATE VIRTUAL TABLE [if_not_exists] [table]\nUSING [module] ([arguments])',
    BlockType.sqlAlterTable:
        'ALTER TABLE [table_name] [alter_action] [alter_value]',
    BlockType.sqlDropTable: 'DROP TABLE [if_exists] [table_name]',
    BlockType.sqlTruncate: 'TRUNCATE TABLE [table_name]',
    BlockType.sqlGrant: 'GRANT [privilege] ON [table] TO [user]',
    BlockType.sqlRevoke: 'REVOKE [privilege] ON [table] FROM [user]',
    BlockType.sqlSavepoint: 'SAVEPOINT [name]',
    BlockType.sqlRollbackToSavepoint: 'ROLLBACK TO SAVEPOINT [name]',
    BlockType.sqlReleaseSavepoint: 'RELEASE SAVEPOINT [name]',
    BlockType.sqlBeginTransaction: 'BEGIN [behavior] TRANSACTION',
    BlockType.sqlCommit: 'COMMIT',
    BlockType.sqlEndTransaction: 'END TRANSACTION',
    BlockType.sqlRollback: 'ROLLBACK',
    BlockType.sqlPragma: 'PRAGMA [pragma] [pragma_value]',
    BlockType.sqlAttachDatabase: 'ATTACH DATABASE [path] AS [schema]',
    BlockType.sqlDetachDatabase: 'DETACH DATABASE [schema]',
    BlockType.sqlVacuum: 'VACUUM [schema]',
    BlockType.sqlReindex: 'REINDEX [target]',
    BlockType.sqlAnalyze: 'ANALYZE [target]',
    BlockType.sqlExplain: '[explain_mode]',
    BlockType.sqlWith: 'WITH [recursive] [name] ([columns]) AS ([sql])',
    BlockType.sqlValues: 'VALUES [values]',
    BlockType.sqlUnion: 'UNION [set_mode] [sql]',
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
    BlockType.sqlSelect:
        'Zeige [select_mode] [Spalten] aus Tabelle [table_name] als [table_alias]',
    BlockType.sqlColumn: '[Spalte]',
    BlockType.sqlText: 'Text {text}',
    BlockType.sqlAlias: '{value} als [Alias]',
    BlockType.sqlFrom: 'aus Tabelle [table_name] als [table_alias]',
    BlockType.sqlWhere:
        'filtere Zeilen\n[negation] [Spalte] [operator] [value]',
    BlockType.sqlAnd: 'und zusätzlich\n[negation] [Spalte] [operator] [value]',
    BlockType.sqlOr: 'oder alternativ\n[negation] [Spalte] [operator] [value]',
    BlockType.sqlOrderBy: 'sortiere nach\n[Spalte] [aufsteigend|absteigend]',
    BlockType.sqlLimit: 'zeige höchstens [count]\nüberspringe [offset]',
    BlockType.sqlGroupBy: 'bilde Gruppen nach [Spalte]',
    BlockType.sqlHaving:
        'filtere Gruppen\n[aggregate] von [Spalte] [operator] [value]',
    BlockType.sqlJoin: genericJoinUsesCondition
        ? 'verbinde [JOIN_TYPE] mit [table] als [table_alias]\nüber [linke_Spalte] [operator] [rechte_Spalte]'
        : 'verbinde [JOIN_TYPE] mit [table] als [table_alias]',
    BlockType.sqlInnerJoin:
        'verbinde Treffer aus [table] als [table_alias]\nüber [linke_Spalte] [operator] [rechte_Spalte]',
    BlockType.sqlLeftJoin:
        'verbinde links mit [table] als [table_alias]\nüber [linke_Spalte] [operator] [rechte_Spalte]',
    BlockType.sqlRightJoin:
        'verbinde rechts mit [table] als [table_alias]\nüber [linke_Spalte] [operator] [rechte_Spalte]',
    BlockType.sqlFullJoin:
        'verbinde alles mit [table] als [table_alias]\nüber [linke_Spalte] [operator] [rechte_Spalte]',
    BlockType.sqlCrossJoin:
        'kombiniere jede Zeile mit [table] als [table_alias]',
    BlockType.sqlSelfJoin:
        'verbinde [table] als [table_alias] mit sich selbst\nüber [linke_Spalte] [operator] [rechte_Spalte]',
    BlockType.sqlNaturalJoin:
        'verbinde automatisch mit [table] als [table_alias]',
    BlockType.sqlInsert: 'fuege ein in [table]\n[Spalten] = [values]',
    BlockType.sqlInsertOrReplace:
        'fuege ein oder ersetze in [table]\n[Spalten] = [values]',
    BlockType.sqlUpsert:
        'fuege [Spalten] = [values] in [table] ein\nbei Konflikt in [conflict_columns] [action]: [assignments]',
    BlockType.sqlUpdate:
        'aendere [table]: [Spalte] = [value]\nwenn [Filter_Spalte] [operator] [where_value]',
    BlockType.sqlDelete:
        'loesche aus [table]\nwenn [Filter_Spalte] [operator] [where_value]',
    BlockType.sqlCreateTable:
        'erstelle Tabelle [if_not_exists] [table_name]\nmit Spalten [Spaltendefinitionen]',
    BlockType.sqlCreateIndex:
        'erstelle [unique] Index [if_not_exists] [name]\nauf [table] für [Spalten]',
    BlockType.sqlDropIndex: 'loesche Index [if_exists] [name]',
    BlockType.sqlCreateView: 'erstelle Sicht [if_not_exists] [name]\naus [sql]',
    BlockType.sqlDropView: 'loesche Sicht [if_exists] [name]',
    BlockType.sqlCreateTrigger:
        'erstelle Automatik [name]\n[timing] [event] auf [table]: [body]',
    BlockType.sqlDropTrigger: 'loesche Automatik [if_exists] [name]',
    BlockType.sqlCreateVirtualTable:
        'erstelle Spezialtabelle [table]\nmit [module] fuer [arguments]',
    BlockType.sqlAlterTable:
        'aendere Tabelle [table_name]\n[alter_action] [alter_value]',
    BlockType.sqlDropTable:
        'loesche Tabelle [if_exists] [table_name] permanent',
    BlockType.sqlTruncate: 'leere Tabelle [table_name] komplett',
    BlockType.sqlGrant: 'erlaube das Recht [privilege] auf [table] fuer [user]',
    BlockType.sqlRevoke:
        'entziehe das Recht [privilege] auf [table] fuer [user]',
    BlockType.sqlSavepoint: 'setze Sicherungspunkt [name]',
    BlockType.sqlRollbackToSavepoint:
        'springe zurueck zu Sicherungspunkt [name]',
    BlockType.sqlReleaseSavepoint: 'gib Sicherungspunkt [name] frei',
    BlockType.sqlBeginTransaction: 'starte Snapshot [behavior]',
    BlockType.sqlCommit: 'uebernehme Snapshot dauerhaft',
    BlockType.sqlEndTransaction: 'beende und uebernehme Snapshot',
    BlockType.sqlRollback: 'stelle Zustand vor Snapshot wieder her',
    BlockType.sqlPragma: 'konfiguriere SQLite: [pragma] [pragma_value]',
    BlockType.sqlAttachDatabase: 'binde Datenbank [path] als [schema] ein',
    BlockType.sqlDetachDatabase: 'trenne Datenbank [schema]',
    BlockType.sqlVacuum: 'raeume Datenbank [schema] auf',
    BlockType.sqlReindex: 'baue Indizes [target] neu',
    BlockType.sqlAnalyze: 'aktualisiere Statistiken fuer [target]',
    BlockType.sqlExplain: 'zeige Abfrageplan [explain_mode]',
    BlockType.sqlWith:
        'definiere [recursive] Zwischenergebnis [name] als ([sql])',
    BlockType.sqlValues: 'erzeuge Werte [values]',
    BlockType.sqlUnion: 'vereine [set_mode] mit [sql]',
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
        'falls [condition_column] [operator] [condition_value]\ndann {result}, sonst {default}',
    BlockType.sqlIf:
        'wenn [condition_column] [operator] [condition_value]\ndann {value}, sonst {default}',
    BlockType.sqlCoalesce: 'nutze {value} sonst {default}',
    BlockType.sqlNullIf: 'setze auf leer wenn {value} gleich {default}',
    BlockType.sqlSetTransaction: 'setze Transaktionsstufe [level]',
  };

  final simpleEn = <BlockType, String>{
    BlockType.eventGreenFlag: 'RUN QUERY',
    BlockType.sqlSelect:
        'Show [select_mode] [columns] from table [table_name] as [table_alias]',
    BlockType.sqlColumn: '[column]',
    BlockType.sqlText: 'text {text}',
    BlockType.sqlAlias: '{value} as [alias]',
    BlockType.sqlFrom: 'from table [table_name] as [table_alias]',
    BlockType.sqlWhere: 'filter rows\n[negation] [column] [operator] [value]',
    BlockType.sqlAnd: 'and also\n[negation] [column] [operator] [value]',
    BlockType.sqlOr: 'or alternatively\n[negation] [column] [operator] [value]',
    BlockType.sqlOrderBy: 'sort by\n[column] [ascending|descending]',
    BlockType.sqlLimit: 'show at most [count]\nskip [offset]',
    BlockType.sqlGroupBy: 'make groups by [column]',
    BlockType.sqlHaving:
        'filter groups\n[aggregate] of [column] [operator] [value]',
    BlockType.sqlJoin: genericJoinUsesCondition
        ? 'join [JOIN_TYPE] with [table] as [table_alias]\non [left_column] [operator] [right_column]'
        : 'join with [table] as [table_alias] using [JOIN_TYPE]',
    BlockType.sqlInnerJoin:
        'join matches from [table] as [table_alias]\non [left_column] [operator] [right_column]',
    BlockType.sqlLeftJoin:
        'left-join [table] as [table_alias]\non [left_column] [operator] [right_column]',
    BlockType.sqlRightJoin:
        'right-join [table] as [table_alias]\non [left_column] [operator] [right_column]',
    BlockType.sqlFullJoin:
        'full-join [table] as [table_alias]\non [left_column] [operator] [right_column]',
    BlockType.sqlCrossJoin: 'combine every row with [table] as [table_alias]',
    BlockType.sqlSelfJoin:
        'join [table] as [table_alias] with itself\non [left_column] [operator] [right_column]',
    BlockType.sqlNaturalJoin: 'auto-join with [table] as [table_alias]',
    BlockType.sqlInsert: 'add to [table]\n[columns] = [values]',
    BlockType.sqlInsertOrReplace:
        'insert or replace in [table]\n[columns] = [values]',
    BlockType.sqlUpsert:
        'insert [columns] = [values] into [table]\non conflict in [conflict_columns] [action]: [assignments]',
    BlockType.sqlUpdate:
        'change [table]: [column] = [value]\nwhen [where_column] [operator] [where_value]',
    BlockType.sqlDelete:
        'delete from [table]\nwhen [where_column] [operator] [where_value]',
    BlockType.sqlCreateTable:
        'create table [if_not_exists] [table_name]\nwith columns [column_definitions]',
    BlockType.sqlCreateIndex:
        'create [unique] index [if_not_exists] [name]\non [table] for [columns]',
    BlockType.sqlDropIndex: 'drop index [if_exists] [name]',
    BlockType.sqlCreateView: 'create view [if_not_exists] [name]\nfrom [sql]',
    BlockType.sqlDropView: 'drop view [if_exists] [name]',
    BlockType.sqlCreateTrigger:
        'create automation [name]\n[timing] [event] on [table]: [body]',
    BlockType.sqlDropTrigger: 'drop automation [if_exists] [name]',
    BlockType.sqlCreateVirtualTable:
        'create special table [table]\nusing [module] for [arguments]',
    BlockType.sqlAlterTable:
        'change table [table_name]\n[alter_action] [alter_value]',
    BlockType.sqlDropTable: 'delete table [if_exists] [table_name] permanently',
    BlockType.sqlTruncate: 'clear table [table_name] completely',
    BlockType.sqlGrant: 'allow [privilege] on [table] for [user]',
    BlockType.sqlRevoke: 'remove [privilege] on [table] for [user]',
    BlockType.sqlSavepoint: 'set savepoint [name]',
    BlockType.sqlRollbackToSavepoint: 'go back to savepoint [name]',
    BlockType.sqlReleaseSavepoint: 'release savepoint [name]',
    BlockType.sqlBeginTransaction: 'start snapshot [behavior]',
    BlockType.sqlCommit: 'keep snapshot changes',
    BlockType.sqlEndTransaction: 'finish and keep snapshot changes',
    BlockType.sqlRollback: 'restore state before snapshot',
    BlockType.sqlPragma: 'configure SQLite: [pragma] [pragma_value]',
    BlockType.sqlAttachDatabase: 'attach database [path] as [schema]',
    BlockType.sqlDetachDatabase: 'detach database [schema]',
    BlockType.sqlVacuum: 'clean up database [schema]',
    BlockType.sqlReindex: 'rebuild indexes [target]',
    BlockType.sqlAnalyze: 'refresh statistics for [target]',
    BlockType.sqlExplain: 'show query plan [explain_mode]',
    BlockType.sqlWith: 'define [recursive] temporary result [name] as ([sql])',
    BlockType.sqlValues: 'create values [values]',
    BlockType.sqlUnion: 'combine [set_mode] with [sql]',
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
        'if [condition_column] [operator] [condition_value]\nthen {result} else {default}',
    BlockType.sqlIf:
        'if [condition_column] [operator] [condition_value]\nthen {value} else {default}',
    BlockType.sqlCoalesce: 'use {value} otherwise {default}',
    BlockType.sqlNullIf: 'set empty if {value} equals {default}',
    BlockType.sqlSetTransaction: 'set transaction level [level]',
  };

  final simpleBase = languageCode == 'de' ? simpleDe : simpleEn;
  final simple = {...simpleBase, ...?simpleLang};
  final map = mode == SqlAbstractionMode.advanced ? adv : simple;
  if (type == BlockType.sqlSelect && inputs['separate_from'] == true) {
    if (mode == SqlAbstractionMode.advanced) {
      return 'SELECT [select_mode] [columns]';
    }
    return languageCode == 'de'
        ? 'Zeige [select_mode] [Spalten]'
        : 'Show [select_mode] [columns]';
  }
  return map[type] ?? simpleBase[type] ?? adv[type] ?? type.name;
}

Map<BlockType, String>? _simpleByLanguage(String languageCode) {
  switch (languageCode) {
    case 'fr':
      return <BlockType, String>{
        BlockType.eventGreenFlag: 'EXECUTER REQUETE',
        BlockType.sqlSelect:
            'affiche [select_mode] [columns] de la table [table_name] comme [table_alias]',
        BlockType.sqlWhere: 'si [negation] [column] [operator] [value]',
        BlockType.sqlOrderBy: 'trie par [column] [ascending|descending]',
      };
    case 'es':
      return <BlockType, String>{
        BlockType.eventGreenFlag: 'EJECUTAR CONSULTA',
        BlockType.sqlSelect:
            'muestra [select_mode] [columns] de tabla [table_name] como [table_alias]',
        BlockType.sqlWhere: 'si [negation] [column] [operator] [value]',
        BlockType.sqlOrderBy: 'ordena por [column] [ascending|descending]',
      };
    default:
      return null;
  }
}
