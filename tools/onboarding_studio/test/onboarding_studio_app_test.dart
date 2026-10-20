import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql_onboarding_studio/onboarding_studio_app.dart';

void main() {
  testWidgets('lets authors add another walkthrough step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const OnboardingStudioApp());

    expect(find.text('Walkthrough-Schritte'), findsOneWidget);
    expect(find.text('Nodes auswählen'), findsWidgets);

    await tester.tap(find.text('Schritt'));
    await tester.pump();

    expect(find.text('Neuer Schritt'), findsWidgets);
  });
}
