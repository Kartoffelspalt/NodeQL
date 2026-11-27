import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/onboarding/onboarding_flow.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_controller.dart';

void main() {
  final english = Map<String, String>.from(
    (jsonDecode(File('assets/translations/en.json').readAsStringSync())
            as Map<String, dynamic>)['messages']
        as Map,
  );
  final catalog = TranslationCatalog(
    locale: 'de',
    messages: builtInMessages['de']!,
    englishMessages: english,
  );

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
    final definition = defaultNodeQlOnboarding(catalog);
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
                catalog: catalog,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('onboarding-skip')));
    expect(skipped, isTrue);
  });

  test('uses package translations and falls back for older packages', () {
    final french = TranslationCatalog(
      locale: 'fr',
      messages: const {'onboarding.nodes.title': 'Choisir des nœuds'},
      englishMessages: english,
    );
    final definition = defaultNodeQlOnboarding(french);

    expect(definition.steps.first.title, 'Choisir des nœuds');
    expect(definition.steps[1].title, 'Connect nodes');
    for (final step in defaultNodeQlOnboarding(catalog).steps) {
      expect(step.title, isNot(startsWith('onboarding.')));
      expect(step.message, isNot(startsWith('onboarding.')));
    }
  });
}
