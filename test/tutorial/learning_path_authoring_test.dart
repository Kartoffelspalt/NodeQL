import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';

void main() {
  test('learning paths preserve node snapshots and timeline callouts', () {
    const path = AuthoredLearningPath(
      id: 'select-tour',
      title: 'SELECT Tour',
      description: 'Explains a query node by node.',
      steps: [
        LearningPathStep(
          id: 'projection',
          title: 'Choose columns',
          instruction: 'Inspect SELECT.',
          nodes: [
            LearningPathNodeTemplate(
              ref: 'select-node',
              type: BlockType.sqlSelect,
              defaults: {'columns': 'name', 'table': 'customers'},
            ),
          ],
          callouts: [
            LearningPathNodeCallout(
              id: 'select-label',
              targetRef: 'select-node',
              title: 'Projection',
              body: 'SELECT decides which values are returned.',
            ),
          ],
        ),
      ],
    );

    final restored = AuthoredLearningPath.fromJson(path.toJson());
    expect(restored.title, 'SELECT Tour');
    expect(restored.steps.single.nodes.single.type, BlockType.sqlSelect);
    expect(restored.steps.single.callouts.single.targetRef, 'select-node');
    expect(restored.calloutCount, 1);
  });

  test('published bundles resolve localized workshop metadata', () {
    final path = AuthoredLearningPath.fromJson(<String, dynamic>{
      'id': 'localized-path',
      'title': <String, String>{
        'de': 'Deutscher Workshop',
        'en': 'English workshop',
      },
      'description': <String, String>{
        'de': 'Deutsche Beschreibung',
        'en': 'English description',
      },
      'steps': <Object>[
        <String, dynamic>{
          'id': 'step',
          'title': 'Step',
          'instruction': 'Inspect it.',
        },
      ],
    });

    expect(path.titleFor('en'), 'English workshop');
    expect(path.titleFor('en-US'), 'English workshop');
    expect(path.titleFor('de'), 'Deutscher Workshop');
    expect(path.descriptionFor('fr'), 'English description');
    expect(path.toJson()['title'], isA<Map<String, String>>());
  });

  test('library persists, replaces and deletes authored paths', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nodeql-learning-paths-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/paths.json');
    final controller = LearningPathLibraryController(
      storageFile: () async => file,
      bundledPaths: () async => const [],
    );
    await controller.initialize();

    const first = AuthoredLearningPath(
      id: 'path',
      title: 'First title',
      description: '',
      steps: [
        LearningPathStep(
          id: 'step',
          title: 'Step',
          instruction: 'Do something.',
        ),
      ],
    );
    await controller.save(first);
    await controller.save(
      const AuthoredLearningPath(
        id: 'path',
        title: 'Updated title',
        description: '',
        steps: [
          LearningPathStep(
            id: 'step',
            title: 'Step',
            instruction: 'Do something.',
          ),
        ],
      ),
    );

    final restored = LearningPathLibraryController(
      storageFile: () async => file,
      bundledPaths: () async => const [],
    );
    await restored.initialize();
    expect(restored.state.paths, hasLength(1));
    expect(restored.state.paths.single.title, 'Updated title');

    await restored.delete('path');
    expect(restored.state.paths, isEmpty);
  });

  test(
    'a failed save keeps the last saved drafts and allows a retry',
    () async {
      final directory = await Directory.systemTemp.createTemp('nodeql-draft-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/workshops.json');
      var unavailable = false;
      final controller = LearningPathLibraryController(
        bundledPaths: () async => const [],
        storageFile: () async {
          if (unavailable)
            throw const FileSystemException('Storage unavailable');
          return file;
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      const path = AuthoredLearningPath(
        id: 'retry',
        title: 'My workshop',
        description: '',
        steps: [
          LearningPathStep(
            id: 'task',
            title: 'Task',
            instruction: 'Try SELECT.',
          ),
        ],
      );
      unavailable = true;
      await expectLater(
        controller.save(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(controller.state.paths, isEmpty);
      unavailable = false;
      await controller.save(path);
      expect(controller.state.paths.single, path);
      expect(
        decodeLearningPathBundle(
          jsonDecode(await file.readAsString()),
        ).single.id,
        path.id,
      );
    },
  );

  test(
    'bundled paths are visible and local paths override matching ids',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nodeql-bundled-learning-paths-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = LearningPathLibraryController(
        storageFile: () async => File('${directory.path}/paths.json'),
        bundledPaths: () async => const [
          AuthoredLearningPath(
            id: 'published',
            title: 'Published title',
            description: '',
            steps: [
              LearningPathStep(
                id: 'step',
                title: 'Step',
                instruction: 'Inspect it.',
              ),
            ],
          ),
        ],
      );
      await controller.initialize();

      expect(controller.state.paths.single.title, 'Published title');
      await controller.save(
        const AuthoredLearningPath(
          id: 'published',
          title: 'Local draft',
          description: '',
          steps: [
            LearningPathStep(
              id: 'step',
              title: 'Step',
              instruction: 'Inspect it.',
            ),
          ],
        ),
      );

      expect(controller.state.paths, hasLength(1));
      expect(controller.state.paths.single.title, 'Local draft');
      expect(
        decodeLearningPathBundle(jsonDecode(controller.exportBundle())),
        hasLength(1),
      );
    },
  );

  test('published-only library rejects local drafts', () async {
    final controller = LearningPathLibraryController(
      enableLocalDrafts: false,
      bundledPaths: () async => const [],
    );
    await controller.initialize();

    expect(
      () => controller.save(
        const AuthoredLearningPath(
          id: 'draft',
          title: 'Draft',
          description: '',
          steps: [
            LearningPathStep(
              id: 'step',
              title: 'Step',
              instruction: 'Draft it.',
            ),
          ],
        ),
      ),
      throwsStateError,
    );
  });
}
