import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql_onboarding_studio/onboarding_models.dart';

void main() {
  test('exports a versioned walkthrough with stable target IDs', () {
    final json =
        jsonDecode(exampleWalkthrough.toPrettyJson()) as Map<String, dynamic>;

    expect(json['schemaVersion'], 1);
    expect(json['name'], 'Erste Schritte');
    expect((json['steps'] as List).first['target'], 'nodePalette');
  });
}
