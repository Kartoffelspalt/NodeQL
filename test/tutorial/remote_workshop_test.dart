import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nodeql/core/platform/sqlite.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/classroom_workshop_code.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/remote_workshop.dart';
import 'package:nodeql/features/tutorial/remote_workshop_dialog.dart';
import 'package:nodeql/features/tutorial/remote_workshop_sql.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:nodeql/localization/translation_catalog.dart';

const _url = 'https://example.github.io/workshops/select.json';
const _path = AuthoredLearningPath(
  id: 'nodeql-overview',
  title: 'Custom SELECT',
  description: 'Projection and filtering.',
  steps: [
    LearningPathStep(
      id: 'projection',
      title: 'Projection',
      instruction: 'Show customer names.',
      nodes: [
        LearningPathNodeTemplate(
          ref: 'select',
          type: BlockType.sqlSelect,
          defaults: {'columns': 'name', 'table': 'customers'},
        ),
      ],
      callouts: [
        LearningPathNodeCallout(
          id: 'select',
          targetRef: 'select',
          title: 'SELECT',
          body: 'Choose the result columns.',
        ),
      ],
    ),
  ],
);

void main() {
  final source = encodeLearningPathBundle([_path]);
  final bytes = utf8.encode(source);
  final digest = sha256.convert(bytes).toString();
  final link = WorkshopDownloadLink.parse('$_url#sha256=$digest');

  ClassroomWorkshopCode issueCode() => ClassroomWorkshopCode.issue(
    address: '192.168.4.12',
    port: 45230,
    bundle: bytes,
  );

  test(
    'classroom codes constrain the endpoint and keep secrets out of the request',
    () {
      final issued = issueCode();
      final code = ClassroomWorkshopCode.parse(issued.encode());
      expect(code.digest, digest);
      expect(code.requestUri, issued.requestUri);
      expect(code.requestUri.host, '192.168.4.12');
      expect(code.requestUri.port, 45230);
      expect(code.requestUri.toString(), isNot(contains(digest)));
      expect(code.requestUri.toString(), isNot(contains(issued.encode())));
      expect(issueCode().requestUri.path, isNot(code.requestUri.path));

      final payload = base64Url.decode(issued.encode().substring(5));
      for (final address in [
        [127, 0, 0, 1],
        [169, 254, 169, 254],
        [8, 8, 8, 8],
        [172, 32, 0, 1],
      ]) {
        payload.setRange(0, 4, address);
        expect(
          () =>
              ClassroomWorkshopCode.parse('NQL1-${base64Url.encode(payload)}'),
          throwsFormatException,
        );
      }
      payload.setRange(0, 6, [192, 168, 4, 12, 0, 80]);
      expect(
        () => ClassroomWorkshopCode.parse('NQL1-${base64Url.encode(payload)}'),
        throwsFormatException,
      );
    },
  );

  test('authenticates classroom bytes and pins the original content', () async {
    final code = issueCode();
    final sealed = await code.seal(bytes);
    final repository = RemoteWorkshopRepository(
      createClassroomClient: () => MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        expect(request.url, code.requestUri);
        return http.Response.bytes(sealed, 200);
      }),
    );
    final download = await repository.downloadClassroom(code);
    expect(download.path.id, 'downloaded:$digest:nodeql-overview');
    expect(download.path.title, _path.title);

    sealed[sealed.length - 1] ^= 1;
    await expectLater(
      repository.downloadClassroom(code),
      throwsA(isA<Exception>()),
    );

    // A peer with the classroom key can encrypt bytes, but cannot change the
    // workshop pinned by the original code.
    final substitute = await code.seal(
      utf8.encode(source.replaceFirst(_path.title, 'Substituted workshop')),
    );
    final altered = RemoteWorkshopRepository(
      createClassroomClient: () =>
          MockClient((_) async => http.Response.bytes(substitute, 200)),
    );
    await expectLater(altered.downloadClassroom(code), throwsFormatException);
  });

  test('validates files under the same schema and size limit', () async {
    final repository = RemoteWorkshopRepository();
    final file = await repository.readFile(Stream.value(bytes));
    expect(file.path.id, 'downloaded:$digest:nodeql-overview');
    await expectLater(
      repository.readFile(Stream.value(utf8.encode('{"schemaVersion":2}'))),
      throwsFormatException,
    );
    await expectLater(
      repository.readFile(Stream.value(List.filled(256 * 1024 + 1, 32))),
      throwsFormatException,
    );
  });

  test('validates HTTPS share links and strips the checksum from the GET', () {
    expect(link.uri.toString(), _url);
    expect(link.digest, digest);
    for (final url in [
      'http://example.github.io/file.json',
      'https://example.github.io.evil.test/file.json',
      'https://127.0.0.1/file.json',
      'https://a@example.github.io/file.json',
      'https://example.github.io:444/file.json',
      'https://example.github.io/file.json?secret=abc',
      'https://example.github.io/file.zip',
    ]) {
      expect(
        () => WorkshopDownloadLink.parse('$url#sha256=$digest'),
        throwsFormatException,
        reason: url,
      );
    }
    expect(() => WorkshopDownloadLink.parse(_url), throwsFormatException);
  });

  for (final classroom in [false, true]) {
    final method = classroom ? 'classroom code' : 'HTTPS link';
    testWidgets('previews, saves and starts a workshop from a $method', (
      tester,
    ) async {
      final code = issueCode();
      final repository = _PreviewRepository(source, await code.seal(bytes));
      AuthoredLearningPath? started;
      var clipboardReads = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          clipboardReads++;
          return {'text': code.encode()};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => TutorialDialog(
                    catalog: const TranslationCatalog(
                      locale: 'en',
                      messages: {},
                      englishMessages: {},
                    ),
                    authoredPaths: const [_path],
                    downloads: repository,
                    onComplete: () async {},
                    onStartAuthoredPath: (path) async {
                      expect(repository.installed, same(path));
                      started = path;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tutorial.classroom.enterCode'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteWorkshopDialog), findsOneWidget);
      expect(clipboardReads, 0);
      if (classroom) {
        await tester.tap(find.text('tutorial.classroom.paste'));
        await tester.pump();
        expect(clipboardReads, 1);
      } else {
        await tester.tap(find.text('tutorial.download.link'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), '$_url#sha256=$digest');
        await tester.pump();
      }
      await tester.tap(find.text('tutorial.download.check'));
      await tester.pumpAndSettle();

      expect(find.text('tutorial.download.preview'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RemoteWorkshopDialog),
          matching: find.text(_path.title),
        ),
        findsOneWidget,
      );
      expect(repository.installed, isNull);
      expect(started, isNull);
      await tester.tap(find.text('tutorial.download.install'));
      await tester.pumpAndSettle();
      expect(repository.installed?.title, _path.title);
      expect(started, same(repository.installed));
      expect(find.byType(RemoteWorkshopDialog), findsNothing);
      expect(find.byType(TutorialDialog), findsNothing);
    });
  }

  test(
    'downloads, installs offline, deduplicates and removes a workshop',
    () async {
      final directory = await Directory.systemTemp.createTemp('workshop-test-');
      addTearDown(() => directory.delete(recursive: true));
      var requests = 0;
      final repository = RemoteWorkshopRepository(
        supportDirectory: () async => directory,
        createClient: () => MockClient((request) async {
          requests++;
          expect(request.method, 'GET');
          expect(request.url.toString(), _url);
          expect(request.followRedirects, isFalse);
          return http.Response(source, 200);
        }),
      );
      final bundle = await repository.download(link);
      expect(await repository.load(), isEmpty);
      await Future.wait([
        repository.install(bundle),
        repository.install(bundle),
      ]);
      final offline = RemoteWorkshopRepository(
        supportDirectory: () async => directory,
        createClient: () => throw StateError('Unexpected network access.'),
      );
      final cached = (await offline.load()).single;
      expect(isDownloadedWorkshop(cached), isTrue);
      expect(cached.id, 'downloaded:$digest:nodeql-overview');
      expect(cached.steps.single.nodes.single.defaults['table'], 'customers');
      expect(requests, 1);

      final file = File(
        '${directory.path}/nodeql_workshop_downloads/$digest.json',
      );
      await file.writeAsString('$source ');
      expect(await offline.load(), isEmpty);
      await repository.install(bundle);
      expect(await offline.load(), hasLength(1));
      await offline.remove(cached);
      expect(await offline.load(), isEmpty);
    },
  );

  test(
    'rejects redirects, modified bytes and oversized streamed downloads',
    () async {
      for (final response in [
        http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'http://127.0.0.1/file.json'},
        ),
        http.StreamedResponse(Stream.value(utf8.encode('$source ')), 200),
        http.StreamedResponse(
          Stream.value(List.filled(256 * 1024 + 1, 32)),
          200,
        ),
      ]) {
        final repository = RemoteWorkshopRepository(
          createClient: () => MockClient.streaming((request, _) async {
            expect(request.followRedirects, isFalse);
            return response;
          }),
        );
        await expectLater(repository.download(link), throwsFormatException);
      }
    },
  );

  test(
    'rejects unsupported schemas, dangerous node defaults and deep JSON',
    () {
      expect(validateRemoteWorkshopBundle(source).title, _path.title);
      for (final invalid in [
        source.replaceFirst('"schemaVersion": 1', '"schemaVersion": 3'),
        source.replaceFirst('"sqlSelect"', '"sqlAttachDatabase"'),
        source.replaceFirst('"columns": "name"', '"columns": "name; ATTACH"'),
        source.replaceFirst(
          '"columns": "name"',
          '"columns": {"type": "sqlFunction"}',
        ),
        source.replaceFirst('"columns": "name"', '"__plugin_id": "unknown"'),
        source.replaceFirst('"targetRef": "select"', '"targetRef": "missing"'),
        encodeLearningPathBundle([_path, _path]),
        '${'[' * 1000}${']' * 1000}',
      ]) {
        expect(
          () => validateRemoteWorkshopBundle(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test('accepts ordinary SELECTs and rejects SQL that can escape query limits', () {
    for (final sql in [
      "SELECT name FROM customers WHERE city = 'Berlin';",
      "SELECT 'a; /* -- b''s';",
      'SELECT COUNT(*) FROM orders;',
      'SELECT c.name, o.total FROM customers AS "c" JOIN orders AS "o" ON c.id = o.customer_id;',
    ]) {
      expect(isDownloadedWorkshopQuery(sql), isTrue, reason: sql);
    }
    for (final sql in [
      "ATTACH DATABASE '/tmp/private.db' AS external;",
      "SELECT 1; VACUUM INTO '/tmp/other.db';",
      'PRAGMA writable_schema = ON;',
      'SELECT name FROM customers /*; */;',
      "SELECT load_extension('/tmp/evil');",
      "SELECT 'load_extension'('/tmp/evil');",
      "SELECT readfile('/tmp/private.db');",
      'SELECT randomblob(1000000000);',
      'SELECT 1 UNION SELECT 2;',
      'SELECT * FROM customers, customers;',
      'SELECT * FROM customers JOIN orders JOIN customers JOIN orders JOIN customers;',
      'SELECT 1 WHERE id IN (SELECT id FROM customers);',
      'WITH RECURSIVE n AS (SELECT 1) SELECT * FROM n;',
      'SELECT 1\u0000;',
    ]) {
      expect(isDownloadedWorkshopQuery(sql), isFalse, reason: sql);
    }
  });

  test(
    'executes downloaded queries on freshly seeded in-memory data only',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'workshop-sql-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/private.db');
      final database = sqlite3.open(file.path);
      try {
        database.execute(
          "CREATE TABLE customers(name); INSERT INTO customers VALUES ('private');",
        );
      } finally {
        database.close();
      }
      final runtime = SqlRuntimeController(
        initialState: SqlRuntimeState(dbPath: file.path),
      );
      addTearDown(runtime.dispose);

      const rejected = 'Download query blocked';
      await runtime.executeDownloadedWorkshopQuery(
        "SELECT name FROM customers WHERE city = 'Berlin' ORDER BY name;",
        rejectedMessage: rejected,
      );
      expect(runtime.state.lastRows, [
        {'name': 'Ada'},
        {'name': 'Clara'},
        {'name': 'Fatima'},
      ]);

      await runtime.executeDownloadedWorkshopQuery(
        "SELECT 1; VACUUM INTO '${directory.path}/escaped.db';",
        rejectedMessage: rejected,
      );
      expect(runtime.state.lastMessage, rejected);
      expect(runtime.state.lastRows, isEmpty);
      expect(File('${directory.path}/escaped.db').existsSync(), isFalse);

      await runtime.executeDownloadedWorkshopQuery(
        'SELECT * FROM json_each;',
        rejectedMessage: rejected,
      );
      expect(runtime.state.lastMessage, startsWith('Live preview blocked'));
    },
  );
}

class _PreviewRepository extends RemoteWorkshopRepository {
  _PreviewRepository(String source, List<int> classroomBytes)
    : super(
        createClient: () => MockClient((_) async => http.Response(source, 200)),
        createClassroomClient: () =>
            MockClient((_) async => http.Response.bytes(classroomBytes, 200)),
      );

  AuthoredLearningPath? installed;

  @override
  Future<List<AuthoredLearningPath>> load() async => [?installed];

  @override
  Future<void> install(WorkshopDownload bundle) async {
    installed = bundle.path;
  }
}
