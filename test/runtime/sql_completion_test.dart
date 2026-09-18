import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_completion.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:nodeql/features/workbench/presentation/widgets/sql_code_editor.dart';

void main() {
  const schemas = <TableSchema>[
    TableSchema(name: 'kunden', columns: <String>['kunden_id', 'nachname']),
    TableSchema(
      name: 'bestellungen',
      columns: <String>['bestell_id', 'kunden_id', 'gesamtbetrag'],
    ),
  ];
  const engine = SqlCompletionEngine();

  test('suggests connected database tables after FROM', () {
    const sql = 'SELECT * FROM ku';
    final suggestions = engine.suggest(
      sql: sql,
      cursorOffset: sql.length,
      schemas: schemas,
    );

    expect(suggestions.first.label, 'kunden');
    expect(suggestions.first.kind, SqlCompletionKind.table);
  });

  test('resolves aliases and suggests qualified columns', () {
    const sql = 'SELECT * FROM kunden AS k WHERE k.na';
    final suggestions = engine.suggest(
      sql: sql,
      cursorOffset: sql.length,
      schemas: schemas,
    );

    expect(suggestions.map((item) => item.insertText), contains('k.nachname'));
    expect(
      suggestions.every((item) => item.kind == SqlCompletionKind.column),
      isTrue,
    );
  });

  test('learned local selections improve completion ranking', () {
    const sql = 'W';
    final suggestions = engine.suggest(
      sql: sql,
      cursorOffset: sql.length,
      schemas: schemas,
      explicitlyRequested: true,
      acceptedSelections: const <String, int>{'with ': 20},
    );

    expect(suggestions.first.insertText, 'WITH ');
  });

  test('static diagnostics find unclosed SQL structures', () {
    final quote = SqlStaticAnalyzer.analyze("SELECT 'open");
    final parenthesis = SqlStaticAnalyzer.analyze('SELECT COUNT(id');

    expect(quote?.message, contains('Unterminated'));
    expect(parenthesis?.message, contains('parenthesis'));
    expect(SqlStaticAnalyzer.analyze('SELECT COUNT(id);'), isNull);
  });

  testWidgets('editor displays and accepts schema-aware suggestions', (
    tester,
  ) async {
    final controller = SqlHighlightingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 300,
            child: SqlCodeEditor(
              controller: controller,
              schemas: schemas,
              onChanged: (_) {},
              onRun: null,
              hintText: 'SQL',
              localModelLabel: 'Local completion',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('custom-sql-input')));
    await tester.enterText(
      find.byKey(const ValueKey<String>('custom-sql-input')),
      'SELECT * FROM ku',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('sql-completion-popup')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('sql-completion-kunden')),
    );
    await tester.pump();
    expect(controller.text, 'SELECT * FROM kunden');
  });
}
