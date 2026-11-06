import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../tool/src/ai_translation_generator.dart';

http.Response completion(Object messages, {String finish = 'STOP'}) =>
    http.Response(
      jsonEncode({
        'candidates': [
          {
            'finishReason': finish,
            'content': {
              'parts': [
                {'text': jsonEncode(messages)},
              ],
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('Gemini provider', () {
    GeminiTranslationClient provider(
      http.Client client, {
      Future<void> Function(Duration)? wait,
    }) => GeminiTranslationClient(
      client: client,
      model: 'gemini-test-model',
      apiKey: 'test-secret',
      wait: wait ?? (_) async {},
    );

    test('sends only catalog strings and returns Unicode translations', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-test-model:generateContent',
        );
        expect(request.url.hasQuery, isFalse);
        expect(request.headers['x-goog-api-key'], 'test-secret');
        expect(request.headers.containsKey('Authorization'), isFalse);
        final body = jsonDecode(request.body) as Map;
        expect(body.containsKey('messages'), isFalse);
        expect(body['generationConfig'], {
          'responseMimeType': 'application/json',
          'responseJsonSchema': {
            'type': 'object',
            'properties': {
              'hello': {'type': 'string'},
            },
            'required': ['hello'],
            'additionalProperties': false,
          },
        });
        final contents = body['contents'] as List;
        expect(contents.single['role'], 'user');
        expect(jsonDecode(contents.single['parts'][0]['text'] as String), {
          'hello': 'Hello {name}',
        });
        expect(
          body['systemInstruction']['parts'][0]['text'],
          contains('SQLite'),
        );
        return completion({'hello': 'こんにちは {name}'});
      });
      addTearDown(client.close);
      expect(
        await provider(client).translate('ja', {'hello': 'Hello {name}'}),
        {'hello': 'こんにちは {name}'},
      );
    });

    for (final bad in <Object>[
      {'wrong': 'Bonjour {name}'},
      {'hello': 'Bonjour {person}'},
      {'hello': 'Bonjour {name} {name}'},
      {'hello': '   '},
      {'hello': 'Bonjour {name}', 'extra': 'unexpected'},
      {'hello': 3},
      ['not an object'],
    ]) {
      test('rejects invalid generated messages: $bad', () async {
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return completion(bad);
        });
        addTearDown(client.close);
        await expectLater(
          provider(client).translate('fr', {'hello': 'Hello {name}'}),
          throwsFormatException,
        );
        expect(requests, 3);
      });
    }

    test('retries throttling and transient server errors', () async {
      var requests = 0;
      final delays = <Duration>[];
      final client = MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('', 429)
            : requests == 2
            ? http.Response('', 503)
            : completion({'plain': 'Hallo'});
      });
      addTearDown(client.close);
      final translator = provider(
        client,
        wait: (delay) async => delays.add(delay),
      );
      expect(await translator.translate('de', {'plain': 'Hello'}), {
        'plain': 'Hallo',
      });
      expect(requests, 3);
      expect(delays, [const Duration(minutes: 1), const Duration(seconds: 4)]);
    });

    test('honors the longest Gemini retry hint', () async {
      var requests = 0;
      final delays = <Duration>[];
      final client = MockClient((_) async {
        if (++requests > 1) return completion({'plain': 'Hallo'});
        return http.Response(
          jsonEncode({
            'error': {
              'details': [
                {'retryDelay': '42.5s'},
              ],
            },
          }),
          429,
          headers: {'retry-after': '20'},
        );
      });
      addTearDown(client.close);
      final translator = provider(
        client,
        wait: (delay) async => delays.add(delay),
      );
      await translator.translate('de', {'plain': 'Hello'});
      expect(delays, [const Duration(seconds: 44)]);
    });

    test(
      'daily quota exhaustion stops without retrying or logging the body',
      () async {
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'error': {
                'message': 'echoed test-secret',
                'details': [
                  {
                    'violations': [
                      {
                        'quotaId':
                            'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
                      },
                    ],
                  },
                ],
              },
            }),
            429,
          );
        });
        addTearDown(client.close);
        await expectLater(
          provider(client).translate('de', {'plain': 'Hello'}),
          throwsA(
            isA<TranslationRequestException>().having(
              (error) => '$error',
              'safe error',
              allOf(contains('daily quota'), isNot(contains('test-secret'))),
            ),
          ),
        );
        expect(requests, 1);
      },
    );

    test(
      'authentication failure is immediate and does not expose provider body',
      () async {
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response('echoed test-secret', 401);
        });
        addTearDown(client.close);
        await expectLater(
          provider(client).translate('de', {'plain': 'Hello'}),
          throwsA(
            isA<TranslationRequestException>().having(
              (error) => '$error',
              'safe error',
              allOf(contains('401'), isNot(contains('test-secret'))),
            ),
          ),
        );
        expect(requests, 1);
      },
    );

    test('rejects truncated responses even when their JSON is valid', () async {
      final client = MockClient(
        (_) async => completion({'plain': 'Hallo'}, finish: 'MAX_TOKENS'),
      );
      addTearDown(client.close);
      await expectLater(
        provider(client).translate('de', {'plain': 'Hello'}),
        throwsFormatException,
      );
    });

    test('requires a Gemini key and validates model IDs', () {
      final client = MockClient((_) async => completion({}));
      addTearDown(client.close);
      for (final model in [
        '',
        'not-a-gemini-model',
        'gemini-model?key=secret',
        'gemini-model/other',
      ]) {
        expect(
          () => GeminiTranslationClient(
            client: client,
            model: model,
            apiKey: 'secret',
          ),
          throwsFormatException,
        );
      }
      expect(
        () => GeminiTranslationClient(client: client, apiKey: ''),
        throwsFormatException,
      );
      expect(
        () => GeminiTranslationClient(client: client, apiKey: 'test-secret'),
        returnsNormally,
      );
    });

    test('uses the configured Gemini model in the endpoint', () {
      final client = MockClient((_) async => completion({}));
      addTearDown(client.close);
      final translator = GeminiTranslationClient(
        client: client,
        apiKey: 'test-secret',
      );
      expect(
        translator.endpoint.path,
        '/v1beta/models/$defaultGeminiTranslationModel:generateContent',
      );
    });

    test('joins multipart text and ignores Gemini thinking parts', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'Private reasoning', 'thought': true},
                    {'text': '{"plain":'},
                    {'text': '"Hallo"}'},
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );
      addTearDown(client.close);
      expect(await provider(client).translate('de', {'plain': 'Hello'}), {
        'plain': 'Hallo',
      });
    });

    for (final blocked in [
      {
        'promptFeedback': {'blockReason': 'SAFETY'},
      },
      {
        'candidates': [
          {'finishReason': 'SAFETY'},
        ],
      },
    ]) {
      test(
        'reports blocked Gemini requests without repeated calls: $blocked',
        () async {
          var requests = 0;
          final client = MockClient((_) async {
            requests++;
            return http.Response(jsonEncode(blocked), 200);
          });
          addTearDown(client.close);
          await expectLater(
            provider(client).translate('de', {'plain': 'Hello'}),
            throwsA(isA<TranslationRequestException>()),
          );
          expect(requests, 1);
        },
      );
    }

    for (final malformed in [
      <String, Object?>{},
      {'candidates': []},
      {
        'candidates': [null],
      },
    ]) {
      test('rejects malformed Gemini responses: $malformed', () async {
        final client = MockClient(
          (_) async => http.Response(jsonEncode(malformed), 200),
        );
        addTearDown(client.close);
        await expectLater(
          provider(client).translate('de', {'plain': 'Hello'}),
          throwsFormatException,
        );
      });
    }
  });

  group('release packages', () {
    late Directory temp;
    late File source;
    late Directory output;
    late Directory reviewed;
    late File state;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp(
        'nodeql-ai-translation-test-',
      );
      source = File('${temp.path}/en.json');
      output = Directory('${temp.path}/generated');
      reviewed = Directory('${temp.path}/reviewed');
      state = File('${temp.path}/state.json');
      await writePackage(source, 'en', {
        'plain': 'Hello',
        'welcome': 'Hello {name}',
      });
    });
    tearDown(() => temp.delete(recursive: true));

    Future<void> generate(
      TranslateBatch translate, {
      bool dryRun = false,
      int revision = 2,
      int batchSize = 1,
    }) => generateTranslationPackages(
      locales: ['de'],
      translate: translate,
      output: output,
      stateFile: state,
      revision: revision,
      source: source,
      reviewed: reviewed,
      batchSize: batchSize,
      dryRun: dryRun,
    );

    test(
      'batches, preserves reviewed wording and reuses unchanged source',
      () async {
        await writePackage(File('${reviewed.path}/de.json'), 'de', {
          'plain': 'Guten Tag',
        });
        var requests = 0;
        await generate((locale, batch) async {
          requests++;
          expect(locale, 'de');
          expect(batch, {'welcome': 'Hello {name}'});
          return {'welcome': 'Hallo {name}'};
        });
        expect(requests, 1);
        final package = readTranslationPackage(File('${output.path}/de.json'));
        expect(package.messages, {
          'plain': 'Guten Tag',
          'welcome': 'Hallo {name}',
        });
        expect(package.revision, 2);
        await generate(
          (_, _) => throw StateError('Cached strings must not call AI'),
          revision: 3,
        );
        expect(
          readTranslationPackage(File('${output.path}/de.json')).revision,
          3,
        );
      },
    );

    test(
      'refreshes changed placeholders and new keys, pruning removed keys',
      () async {
        await generate((_, batch) async => batch);
        await writePackage(source, 'en', {
          'welcome': 'Hello {person}',
          'added': 'New',
        });
        final translated = <String>[];
        await generate((_, batch) async {
          translated.addAll(batch.keys);
          return batch;
        }, revision: 3);
        expect(translated, ['welcome', 'added']);
        expect(
          readTranslationPackage(File('${output.path}/de.json')).messages,
          {'welcome': 'Hello {person}', 'added': 'New'},
        );
      },
    );

    test(
      'dry run needs no credentials and writes no output or state',
      () async {
        await generate((_, _) => throw StateError('No API call'), dryRun: true);
        expect(await output.exists(), isFalse);
        expect(await state.exists(), isFalse);
      },
    );

    test(
      'failed later batch leaves previous package and state intact',
      () async {
        await generate((_, batch) async => batch);
        final before = await File('${output.path}/de.json').readAsString();
        final stateBefore = await state.readAsString();
        await writePackage(source, 'en', {
          'plain': 'Changed',
          'welcome': 'Welcome {name}',
        });
        var requests = 0;
        await expectLater(
          generate((_, batch) async {
            if (++requests == 2) {
              throw const TranslationRequestException('offline');
            }
            return batch;
          }, revision: 3),
          throwsA(isA<TranslationRequestException>()),
        );
        expect(await File('${output.path}/de.json').readAsString(), before);
        expect(await state.readAsString(), stateBefore);
      },
    );

    test('rejects revisions below previously generated packages', () async {
      await generate((_, batch) async => batch);
      await expectLater(
        generate((_, batch) async => batch, revision: 1),
        throwsFormatException,
      );
    });

    test(
      'removing a reviewed override requests a new machine translation',
      () async {
        final override = File('${reviewed.path}/de.json');
        await writePackage(override, 'de', {'plain': 'Reviewed greeting'});
        await generate((_, batch) async => batch);
        await override.delete();
        final requested = <String>[];
        await generate((_, batch) async {
          requested.addAll(batch.keys);
          return batch;
        }, revision: 3);
        expect(requested, ['plain']);
      },
    );

    test('removes obsolete generated locales when targets change', () async {
      Future<void> targets(List<String> locales) => generateTranslationPackages(
        locales: locales,
        translate: (_, batch) async => batch,
        output: output,
        stateFile: state,
        revision: 2,
        source: source,
        reviewed: reviewed,
      );
      await targets(['de', 'fr']);
      expect(await File('${output.path}/fr.json').exists(), isTrue);
      await targets(['de']);
      expect(await File('${output.path}/fr.json').exists(), isFalse);
      expect((jsonDecode(await state.readAsString()) as Map).keys, ['de']);
    });

    test(
      'limits concurrent batches and still writes a complete package',
      () async {
        await writePackage(source, 'en', {
          for (var i = 0; i < 7; i++) 'key$i': 'Text $i',
        });
        var active = 0;
        var maximum = 0;
        await generate((_, batch) async {
          active++;
          if (active > maximum) {
            maximum = active;
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          return batch;
        });
        expect(maximum, 3);
        expect(
          readTranslationPackage(
            File('${output.path}/de.json'),
          ).messages.length,
          7,
        );
      },
    );
  });
}

Future<void> writePackage(
  File file,
  String locale,
  Map<String, String> messages,
) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'locale': locale,
      'revision': 1,
      'messages': messages,
    }),
  );
}
