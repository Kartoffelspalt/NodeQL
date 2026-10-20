import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';

void main() {
  test('the published workshop bundle contains progressive playable paths', () {
    final source = File('assets/workshops/workshops.json').readAsStringSync();
    final paths = decodeLearningPathBundle(jsonDecode(source));

    expect(paths, hasLength(11));
    expect(paths.map((path) => path.id).toSet(), hasLength(paths.length));
    expect(
      paths.map((path) => path.id),
      containsAll(<String>[
        'nodeql-nodes-and-values',
        'nodeql-overview',
        'nodeql-workshop-tools',
        'sqlite-select-and-filters',
        'sqlite-data-types',
        'sqlite-advanced-filters',
        'sqlite-sorting-and-where',
        'sqlite-complex-queries',
        'sqlite-data-manipulation',
        'sqlite-schema-objects',
        'sqlite-transactions',
      ]),
    );
    for (final path in paths) {
      expect(path.titleTranslations['de'], isNotEmpty);
      expect(path.titleTranslations['en'], isNotEmpty);
      expect(path.descriptionTranslations['de'], isNotEmpty);
      expect(path.descriptionTranslations['en'], isNotEmpty);
      expect(path.steps, isNotEmpty, reason: '${path.id} has no steps');
      expect(
        path.steps.map((step) => step.id).toSet(),
        hasLength(path.steps.length),
        reason: '${path.id} needs unique step IDs for saved progress',
      );
      expect(
        path.steps.first.mode,
        LearningPathMode.simple,
        reason: '${path.id} must introduce its topic in Simple Mode',
      );
      expect(
        path.steps.map((step) => step.mode),
        contains(LearningPathMode.advanced),
        reason: '${path.id} must include an Advanced Mode phase',
      );
      for (final step in path.steps) {
        expect(step.nodes, isNotEmpty, reason: '${step.id} has no nodes');
        final nodeRefs = step.nodes.map((node) => node.ref).toSet();
        expect(
          step.callouts.every(
            (callout) => nodeRefs.contains(callout.targetRef),
          ),
          isTrue,
          reason: '${step.id} contains an orphaned callout',
        );
      }
    }
  });
}
