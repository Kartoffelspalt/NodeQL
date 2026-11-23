import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_studio_library.dart';
import 'package:nodeql/localization/translation_catalog.dart';

void main() {
  final catalog = _englishCatalog();
  const draft = AuthoredLearningPath(
    id: 'draft-1',
    title: 'Working with joins',
    description: 'Match customers with their orders',
    steps: [
      LearningPathStep(
        id: 'join',
        title: 'Inner join',
        instruction: 'Join rows.',
      ),
    ],
  );
  const official = AuthoredLearningPath(
    id: 'official-1',
    title: 'Filter records',
    description: 'An exercise on the WHERE clause',
    steps: [
      LearningPathStep(
        id: 'filter',
        title: 'Compare values',
        instruction: 'Filter.',
      ),
    ],
  );

  Future<void> pumpLibrary(
    WidgetTester tester, {
    ValueChanged<AuthoredLearningPath>? onDuplicate,
    Future<void> Function(AuthoredLearningPath)? onDelete,
    ValueChanged<AuthoredLearningPath>? onShare,
    ValueChanged<AuthoredLearningPath>? onExport,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: Material(
              child: LearningPathStudioLibrary(
                catalog: catalog,
                paths: const [draft, official],
                draftIds: {draft.id},
                onCreate: () {},
                onEdit: (_) {},
                onPreview: (_) {},
                onDuplicate: onDuplicate ?? (_) {},
                onDelete: onDelete,
                onShareClassroom: onShare ?? (_) {},
                onExportDownload: onExport,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('filters by source and searches description and step titles', (
    tester,
  ) async {
    await pumpLibrary(tester);
    final search = find.byKey(const ValueKey('learning-path-search'));
    await tester.enterText(search, 'ORDERS inner');
    await tester.pumpAndSettle();
    expect(find.text(draft.title), findsOneWidget);
    expect(find.text(official.title), findsNothing);

    await tester.tap(find.text('Official (1)'));
    await tester.pumpAndSettle();
    expect(
      find.text('No workshops match your search or filter.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sort workshops'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Name A–Z'),
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(official.title)).dy,
      lessThan(tester.getTopLeft(find.text(draft.title)).dy),
    );
  });

  testWidgets('offers nonmutating actions for official templates', (
    tester,
  ) async {
    AuthoredLearningPath? duplicated;
    AuthoredLearningPath? shared;
    AuthoredLearningPath? exported;
    await pumpLibrary(
      tester,
      onDuplicate: (path) => duplicated = path,
      onDelete: (_) async {},
      onShare: (path) => shared = path,
      onExport: (path) => exported = path,
    );

    await tester.tap(find.text('Official (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workshop'), findsNothing);
    await tester.tap(find.text('Duplicate as draft'));
    expect(duplicated, same(official));
    await tester.tap(find.text('Share with class'));
    expect(shared, same(official));
    await tester.tap(find.byTooltip('More workshop actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete workshop'), findsNothing);
    await tester.tap(find.text('Export for download'));
    await tester.pumpAndSettle();
    expect(exported, same(official));
  });

  testWidgets('confirms deletion of drafts', (tester) async {
    AuthoredLearningPath? deleted;
    await pumpLibrary(tester, onDelete: (path) async => deleted = path);

    await tester.tap(find.text('Drafts (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workshop'), findsOneWidget);
    expect(find.text('Share with class'), findsOneWidget);
    await tester.tap(find.byTooltip('More workshop actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete workshop'));
    await tester.pumpAndSettle();
    expect(deleted, isNull);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, same(draft));
  });
}

TranslationCatalog _englishCatalog() {
  final source = File('assets/translations/en.json').readAsStringSync();
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  final messages = Map<String, String>.from(decoded['messages'] as Map);
  return TranslationCatalog(
    locale: 'en',
    messages: messages,
    englishMessages: messages,
  );
}
