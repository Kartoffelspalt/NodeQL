import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/tutorial/classroom_workshop_code.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';
import 'package:nodeql_workshop_admin/classroom_workshop_session.dart';

void main() {
  final source = encodeLearningPathBundle([
    const AuthoredLearningPath(
      id: 'classroom-select',
      title: 'Classroom SELECT',
      description: 'Build a projection.',
      steps: [
        LearningPathStep(
          id: 'select',
          title: 'Projection',
          instruction: 'Add a SELECT node.',
        ),
      ],
    ),
  ]);

  test('serves only the matching workshop until sharing stops', () async {
    final networks = await ClassroomWorkshopSession.networks();
    if (networks.isEmpty) {
      markTestSkipped('Requires a private IPv4 interface for a local socket.');
      return;
    }
    final session = await ClassroomWorkshopSession.start(
      address: networks.first.address,
      source: source,
    );
    addTearDown(session.stop);
    final repository = RemoteWorkshopRepository();
    final code = ClassroomWorkshopCode.parse(session.code.encode());
    final file = await repository.downloadClassroom(code);
    expect(file.path.title, 'Classroom SELECT');

    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    for (final (method, uri) in [
      ('GET', code.requestUri.replace(path: '/other')),
      ('GET', code.requestUri.replace(query: 'data=1')),
      ('POST', code.requestUri),
    ]) {
      final request = await client.openUrl(method, uri);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    }

    await Future.wait([session.stop(), session.stop()]);
    await expectLater(
      repository.downloadClassroom(code),
      throwsA(isA<Exception>()),
    );
  });

  test('automatically closes a timed classroom session', () async {
    final networks = await ClassroomWorkshopSession.networks();
    if (networks.isEmpty) {
      markTestSkipped('Requires a private IPv4 interface for a local socket.');
      return;
    }
    final session = await ClassroomWorkshopSession.start(
      address: networks.first.address,
      source: source,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(session.stop);
    await session.closed.timeout(const Duration(seconds: 2));
    await expectLater(
      RemoteWorkshopRepository().downloadClassroom(session.code),
      throwsA(isA<Exception>()),
    );
  });
}
