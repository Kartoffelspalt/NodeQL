import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql_workshop_admin/workshop_admin_launcher.dart';

void main() {
  testWidgets('exposes the private Workshop Studio action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: WorkshopAdminLauncher(onStart: (_) {})),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workshop-learning-path-studio')),
      findsOneWidget,
    );
  });
}
