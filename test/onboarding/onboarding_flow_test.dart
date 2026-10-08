import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/onboarding/onboarding_flow.dart';

void main() {
  test('reads the Onboarding Studio export format', () {
    final definition = OnboardingDefinition.fromJsonString('''
      {
        "schemaVersion": 1,
        "name": "NodeQL intro",
        "steps": [{
          "id": "nodes",
          "target": "nodePalette",
          "title": "Nodes",
          "message": "Choose a node.",
          "placement": "bottom"
        }]
      }
    ''');

    expect(definition.steps.single.target, OnboardingTarget.nodePalette);
  });

  testWidgets('can skip an active walkthrough', (tester) async {
    var skipped = false;
    final definition = defaultNodeQlOnboarding(const Locale('de'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              NodeQlOnboardingOverlay(
                definition: definition,
                stepIndex: 0,
                targetRectFor: (_) => const Rect.fromLTWH(20, 20, 120, 50),
                onNext: () {},
                onSkip: () => skipped = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('onboarding-skip')));
    expect(skipped, isTrue);
  });
}
