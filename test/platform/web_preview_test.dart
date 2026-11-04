@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nodeql/core/platform/sqlite.dart';
import 'package:nodeql/core/platform/storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/app/nodeql_app.dart';
import 'package:nodeql/features/onboarding/onboarding_launch_controller.dart';
import 'package:nodeql/features/onboarding/onboarding_flow.dart';
import 'package:nodeql/features/workbench/presentation/engine/plugin_registry.dart';
import 'package:nodeql/features/workbench/presentation/workbench_page.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:url_launcher/link.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Flutter's browser test server exposes files below test/, but does not
    // wire the flutter/assets channel. test/assets points to the app assets.
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final key = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      final response = await http.get(Uri.base.resolve('/$key'));
      return response.statusCode == 200
          ? ByteData.sublistView(response.bodyBytes)
          : null;
    });
    await initializeSqlite();
  });
  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  test(
    'browser SQLite uses the same files as imports and project storage',
    () async {
      final directory = temporaryDirectory.createTempSync('web-files-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final originalPath = '${directory.path}/original.db';
      final database = sqlite3.open(originalPath);
      database.execute(
        'CREATE TABLE demo (name TEXT); INSERT INTO demo VALUES (\'Ada\');',
      );
      database.close();
      final importedPath = '${directory.path}/imported.db';
      await fileAt(
        importedPath,
      ).writeAsBytes(await fileAt(originalPath).readAsBytes());
      final runtime = SqlRuntimeController();
      addTearDown(runtime.dispose);
      await runtime.attachDatabasePath(importedPath);
      final query = await runtime.executeReadOnlyPreview(
        'SELECT name FROM demo;',
      );
      expect(query.success, isTrue, reason: query.message);
      expect(query.rows.single['name'], 'Ada');
    },
  );

  test(
    'browser snapshots restore failed writes and block preview writes',
    () async {
      final runtime = SqlRuntimeController();
      addTearDown(runtime.dispose);
      final directory = temporaryDirectory.createTempSync('web-runtime-');
      addTearDown(() => directory.deleteSync(recursive: true));
      await runtime.createEmptyDatabase(directoryPath: directory.path);

      final created = await runtime.executeWithSnapshot(
        'CREATE TABLE demo (id INTEGER PRIMARY KEY); INSERT INTO demo VALUES (1);',
      );
      expect(created.success, isTrue, reason: created.message);
      final failed = await runtime.executeWithSnapshot(
        'INSERT INTO demo VALUES (2); INSERT INTO demo VALUES (1);',
      );
      expect(failed.success, isFalse);
      final result = await runtime.executeReadOnlyPreview(
        'SELECT id FROM demo;',
      );
      expect(result.rows, [
        <String, String>{'id': '1'},
      ]);

      final blocked = await runtime.executeReadOnlyPreview('DELETE FROM demo;');
      expect(blocked.success, isFalse);
      final database = sqlite3.open(
        runtime.state.dbPath!,
        mode: OpenMode.readOnly,
      );
      try {
        expect(database.select('SELECT id FROM demo;'), hasLength(1));
        expect(
          () => database.execute('DELETE FROM demo;'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        database.close();
      }
    },
  );
  testWidgets(
    'web preview explains desktop-only features before linking to GitHub',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container
            .read(translationControllerProvider.notifier)
            .initialize();
        final onboarding = container.read(onboardingLaunchProvider.notifier);
        await onboarding.initialize();
        await onboarding.markSeen();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NodeQlApp(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchPage), findsOneWidget);
      Future<void> expectDesktopNotice(
        String buttonKey, {
        String message = 'This feature is only available in the desktop app.',
      }) async {
        final button = find.byKey(ValueKey(buttonKey));
        expect(button, findsOneWidget);
        expect(
          find.ancestor(of: button, matching: find.byType(Link)),
          findsNothing,
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('desktop-feature-notice')),
          findsOneWidget,
        );
        expect(find.text(message), findsOneWidget);
        final link = tester.widget<Link>(
          find.ancestor(
            of: find.byKey(const ValueKey('desktop-feature-github')),
            matching: find.byType(Link),
          ),
        );
        expect(link.uri, Uri.parse('https://github.com/Kartoffelspalt/NodeQL'));
        expect(link.target, LinkTarget.blank);
        expect(link.isDisabled, isFalse);
        await tester.tap(find.byKey(const ValueKey('desktop-feature-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('desktop-feature-notice')),
          findsNothing,
        );
      }

      await expectDesktopNotice('open-workshop');
      await expectDesktopNotice('open-database-browser');
      expect(find.text('Workshop'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-sqlite')), findsOneWidget);
      expect(container.exists(pluginPaletteProvider), isFalse);

      await tester.tap(find.byKey(const ValueKey('open-onboarding')));
      await tester.pumpAndSettle();
      final onboarding = tester.widget<NodeQlOnboardingOverlay>(
        find.byType(NodeQlOnboardingOverlay),
      );
      expect(onboarding.definition.steps, hasLength(3));
      expect(
        onboarding.definition.steps.map((step) => step.target),
        isNot(contains(OnboardingTarget.workshop)),
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pumpAndSettle();

      for (final key in [
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyB,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      expect(
        find.byKey(const ValueKey('database-browser-dialog')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Language & Region'), findsOneWidget);
      expect(find.text('About NodeQL'), findsOneWidget);
      await tester.tap(find.text('Extensions'));
      await tester.pumpAndSettle();
      await expectDesktopNotice('settings-manage-plugins');
      expect(find.text('Manage Plugins'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('install-plugin-manifest')),
        findsNothing,
      );
      await tester.tap(find.text('Learning'));
      await tester.pumpAndSettle();
      await expectDesktopNotice('settings-tutorial');
      expect(
        find.byKey(const ValueKey('workshop-provider-scope')),
        findsNothing,
      );
      expect(container.exists(pluginPaletteProvider), isFalse);
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container
            .read(translationControllerProvider.notifier)
            .setLocaleTag('de'),
      );
      await tester.pumpAndSettle();
      await expectDesktopNotice(
        'open-workshop',
        message: 'Dieses Feature ist nur in der Desktop App verfügbar.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
