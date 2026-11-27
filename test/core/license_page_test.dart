import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/licenses/license_page.dart';
import 'package:nodeql/core/licenses/license_repository.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:nodeql/localization/translation_repository.dart';

void main() {
  testWidgets('retries a failed load, opens notices, and reuses the cache', (
    tester,
  ) async {
    var reads = 0;
    final retry = Completer<String>();
    final repository = BundledLicenseRepository(
      loadNotices: () async {
        reads++;
        if (reads == 1) throw StateError('missing asset');
        return retry.future;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          licenseRepositoryProvider.overrideWithValue(repository),
          translationControllerProvider.overrideWith(
            (_) => _ReadyTranslations(),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const NodeQlLicensePage(
                      applicationVersion: '1.0.0',
                      applicationIcon: Icon(Icons.account_tree),
                    ),
                  ),
                ),
                child: const Text('Open licenses'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open licenses'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('licenses-retry')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byKey(const ValueKey('licenses-retry')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    retry.complete('example\n\nCopyright example\nLicense contents.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('example'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Copyright example'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open licenses'));
    await tester.pumpAndSettle();
    expect(find.text('example'), findsOneWidget);
    expect(reads, 2);
  });
}

class _ReadyTranslations extends TranslationController {
  _ReadyTranslations() : super(FileTranslationRepository()) {
    state = const TranslationState(loading: false);
  }

  @override
  Future<void> initialize() async {}
}
