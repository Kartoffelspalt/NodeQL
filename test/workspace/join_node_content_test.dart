import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/widgets/join_node_content.dart';
import 'package:nodeql/localization/generated/app_localizations.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('table bridges fit every bundled language and join kind', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final kind in [
        'INNER',
        'LEFT',
        'RIGHT',
        'FULL',
        'CROSS',
        'NATURAL',
        'SELF',
      ]) {
        final node = _join(kind);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: JoinNodeContent.width,
                  height: JoinNodeContent.height,
                  child: ColoredBox(
                    color: Colors.deepPurple,
                    child: JoinNodeContent(
                      node: node,
                      sourceTable: 'customers AS c + orders AS o',
                      languageCode: locale.languageCode,
                      onChooseKind: () {},
                      slotBuilder: (key, width) => SizedBox(
                        width: width,
                        height: key == 'table' ? 26 : 30,
                        child: Text(
                          '${node.inputs[key] ?? key}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${locale.languageCode}: $kind',
        );
      }
    }
  });

  testWidgets(
    'raw ON stays editable and conditionless joins hide matching slots',
    (tester) async {
      Future<List<String>> render(Map<String, dynamic> inputs) async {
        final slots = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: JoinNodeContent.width,
                height: JoinNodeContent.height,
                child: JoinNodeContent(
                  node: _join('INNER')..inputs.addAll(inputs),
                  sourceTable: 'customers',
                  languageCode: 'en',
                  slotBuilder: (key, width) {
                    slots.add(key);
                    return SizedBox(width: width, height: 26, child: Text(key));
                  },
                ),
              ),
            ),
          ),
        );
        return slots;
      }

      final raw = await render({
        'imported_raw_on': true,
        'on': 'c.id = o.customer_id OR c.id = o.reviewer_id',
      });
      expect(raw, contains('on'));
      expect(raw, isNot(contains('left_column')));
      for (final kind in ['CROSS', 'NATURAL']) {
        final slots = await render({'join_type': kind});
        expect(slots, ['table']);
      }
      final structured = await render({'join_type': 'LEFT'});
      expect(
        structured,
        containsAll(['table', 'left_column', 'operator', 'right_column']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outcome picker returns the choice and keeps special cases collapsed',
    (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDialog<String>(
                    context: context,
                    builder: (_) => const JoinKindDialog(
                      selected: 'INNER',
                      languageCode: 'en',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('join-kind-CROSS')).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('join-kind-LEFT')));
      await tester.pumpAndSettle();
      expect(picked, 'LEFT');
      expect(find.byType(JoinKindDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('row examples agree with SQLite outer-join and NULL semantics', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    database.execute(
      'CREATE TABLE existing_data (id INTEGER); INSERT INTO existing_data VALUES (1), (2);'
      'CREATE TABLE new_data (id INTEGER); INSERT INTO new_data VALUES (1), (3);',
    );
    const examples = <String, List<List<int?>>>{
      'INNER': [
        [1, 1],
      ],
      'LEFT': [
        [1, 1],
        [2, null],
      ],
      'RIGHT': [
        [1, 1],
        [null, 3],
      ],
      'FULL': [
        [1, 1],
        [2, null],
        [null, 3],
      ],
    };
    for (final entry in examples.entries) {
      final rows = database.select(
        'SELECT e.id, n.id FROM existing_data AS e '
        '${entry.key} JOIN new_data AS n ON e.id = n.id',
      );
      expect(rows.map((row) => row.values.toList()).toList(), entry.value);
    }
  });
}

OperatorBlock _join(String kind) => OperatorBlock(
  id: 'join',
  position: Offset.zero,
  operatorType: BlockType.sqlJoin,
  inputs: {
    'join_type': kind,
    'table': 'orders AS o',
    'left_column': 'c.id',
    'right_column': 'o.customer_id',
    'operator': '=',
  },
);
