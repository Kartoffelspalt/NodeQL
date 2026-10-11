import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_timeline.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/features/tutorial/workshop_icons.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
  final paths = decodeLearningPathBundle(
    jsonDecode(File('assets/workshops/workshops.json').readAsStringSync()),
  );
  const expectedIcons = <String, IconData>{
    'nodeql-overview': Icons.dashboard_outlined,
    'nodeql-nodes-and-values': Icons.account_tree_outlined,
    'nodeql-workshop-tools': Icons.construction_outlined,
    'sqlite-select-and-filters': Icons.filter_alt_outlined,
    'sqlite-data-types': Icons.data_object_outlined,
    'sqlite-advanced-filters': Icons.filter_list_alt,
    'sqlite-sorting-and-where': Icons.sort_by_alpha_outlined,
    'sqlite-complex-queries': Icons.hub_outlined,
    'sqlite-data-manipulation': Icons.edit_note_outlined,
    'sqlite-schema-objects': Icons.schema_outlined,
    'sqlite-transactions': Icons.restore_outlined,
  };

  test('all official workshops have a distinct topic icon', () {
    expect(paths.map((path) => path.id).toSet(), expectedIcons.keys.toSet());
    expect(expectedIcons.values.toSet(), hasLength(paths.length));
    for (final path in paths) {
      expect(workshopIconFor(path.id), expectedIcons[path.id]);
    }
    expect(workshopIconFor('custom-workshop'), Icons.timeline_rounded);
  });

  testWidgets('official workshop cards show their topic icons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialDialog(
          catalog: _englishCatalog(),
          authoredPaths: paths,
          onStartAuthoredPath: (_) async {},
          onComplete: () async {},
        ),
      ),
    );
    for (final path in paths) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('authored-learning-path-${path.id}')),
          matching: find.byIcon(expectedIcons[path.id]!),
        ),
        findsOneWidget,
        reason: path.id,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('workshop player uses the same topic icon as the overview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final path in paths) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: LearningPathTimelinePanel(
                catalog: _englishCatalog(),
                path: path,
                stepIndex: 0,
                onStep: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(expectedIcons[path.id]!), findsOneWidget);
      expect(tester.takeException(), isNull, reason: path.id);
    }
  });
}

TranslationCatalog _englishCatalog() {
  final decoded =
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
  final messages = (decoded['messages'] as Map<String, dynamic>).map(
    (key, value) => MapEntry(key, value as String),
  );
  return TranslationCatalog(
    locale: 'en',
    messages: messages,
    englishMessages: messages,
  );
}
