import 'dart:convert';

/// Portable formats for query-result reuse outside NodeQL.
enum SqlResultExportFormat { csv, json, tsv }

String sqlResultExportExtension(SqlResultExportFormat format) =>
    switch (format) {
      SqlResultExportFormat.csv => 'csv',
      SqlResultExportFormat.json => 'json',
      SqlResultExportFormat.tsv => 'tsv',
    };

String sqlResultExportLabel(SqlResultExportFormat format) => switch (format) {
  SqlResultExportFormat.csv => 'CSV',
  SqlResultExportFormat.json => 'JSON',
  SqlResultExportFormat.tsv => 'TSV',
};

/// Encodes result rows without losing column order. CSV works with spreadsheet
/// applications, JSON with APIs/scripts, and TSV can be pasted into tables.
String encodeSqlResultRows(
  List<Map<String, String>> rows,
  SqlResultExportFormat format,
) {
  final columns = <String>[];
  for (final row in rows) {
    for (final column in row.keys) {
      if (!columns.contains(column)) columns.add(column);
    }
  }
  if (format == SqlResultExportFormat.json) {
    return const JsonEncoder.withIndent('  ').convert(rows);
  }

  final separator = format == SqlResultExportFormat.csv ? ',' : '\t';
  String cell(String value) {
    if (format == SqlResultExportFormat.tsv) {
      return value.replaceAll('\t', ' ').replaceAll(RegExp(r'[\r\n]+'), ' ');
    }
    if (!value.contains(RegExp(r'[,"\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  return <String>[
    columns.map(cell).join(separator),
    for (final row in rows)
      columns.map((column) => cell(row[column] ?? '')).join(separator),
  ].join('\n');
}
