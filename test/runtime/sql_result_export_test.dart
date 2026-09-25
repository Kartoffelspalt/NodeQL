import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_result_export.dart';

void main() {
  const rows = <Map<String, String>>[
    {'name': 'Ada, Lovelace', 'note': 'first\nprogrammer'},
    {'name': 'Grace', 'note': '"COBOL"'},
  ];

  test('CSV escapes portable result values', () {
    expect(
      encodeSqlResultRows(rows, SqlResultExportFormat.csv),
      'name,note\n"Ada, Lovelace","first\nprogrammer"\nGrace,"""COBOL"""',
    );
  });

  test('JSON and TSV retain all visible result fields', () {
    expect(
      encodeSqlResultRows(rows, SqlResultExportFormat.json),
      contains('Ada, Lovelace'),
    );
    expect(
      encodeSqlResultRows(rows, SqlResultExportFormat.tsv),
      'name\tnote\nAda, Lovelace\tfirst programmer\nGrace\t"COBOL"',
    );
  });
}
