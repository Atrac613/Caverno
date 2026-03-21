import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/core/services/voicevox_service.dart';

void main() {
  group('VoicevoxService', () {
    group('synthesize', () {
      test('returns WAV bytes on success', () async {
        final fakeWav = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
        final client = MockClient((request) async {
          if (request.url.path.contains('audio_query')) {
            return http.Response('{"accent_phrases":[]}', 200);
          }
          if (request.url.path.contains('synthesis')) {
            return http.Response.bytes(fakeWav, 200);
          }
          return http.Response('Not found', 404);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        final result = await service.synthesize('hello');
        expect(result, fakeWav);
      });

      test('returns empty bytes for empty text', () async {
        var httpCalled = false;
        final client = MockClient((request) async {
          httpCalled = true;
          return http.Response('', 200);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        final result = await service.synthesize('');
        expect(result.length, 0);
        expect(httpCalled, false);
      });

      test('returns empty bytes for whitespace-only text', () async {
        var httpCalled = false;
        final client = MockClient((request) async {
          httpCalled = true;
          return http.Response('', 200);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        final result = await service.synthesize('   ');
        expect(result.length, 0);
        expect(httpCalled, false);
      });

      test('throws on audio_query failure', () async {
        final client = MockClient((request) async {
          return http.Response('error', 500);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        expect(() => service.synthesize('hello'), throwsException);
      });

      test('throws on synthesis failure', () async {
        final client = MockClient((request) async {
          if (request.url.path.contains('audio_query')) {
            return http.Response('{"query": true}', 200);
          }
          return http.Response('synthesis error', 500);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        expect(() => service.synthesize('hello'), throwsException);
      });

      test('passes speaker ID to both endpoints', () async {
        final client = MockClient((request) async {
          expect(request.url.queryParameters['speaker'], '42');
          if (request.url.path.contains('audio_query')) {
            return http.Response('{}', 200);
          }
          return http.Response.bytes(Uint8List(0), 200);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        await service.synthesize('hello', speakerId: 42);
      });
    });

    group('getSpeakers', () {
      test('parses speakers with nested styles', () async {
        final speakersJson = jsonEncode([
          {
            'name': 'Zundamon',
            'styles': [
              {'id': 1, 'name': 'Normal'},
              {'id': 2, 'name': 'Happy'},
            ],
          },
          {
            'name': 'Tsumugi',
            'styles': [
              {'id': 3, 'name': 'Normal'},
            ],
          },
        ]);

        final client = MockClient((request) async {
          expect(request.url.path, '/speakers');
          return http.Response(speakersJson, 200);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        final speakers = await service.getSpeakers();

        expect(speakers.length, 3);
        expect(speakers[0].name, 'Zundamon');
        expect(speakers[0].speakerId, 1);
        expect(speakers[0].styleName, 'Normal');
        expect(speakers[0].displayName, 'Zundamon (Normal)');
        expect(speakers[1].speakerId, 2);
        expect(speakers[2].name, 'Tsumugi');
      });

      test('handles empty speakers list', () async {
        final client = MockClient((request) async {
          return http.Response('[]', 200);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        final speakers = await service.getSpeakers();
        expect(speakers, isEmpty);
      });

      test('throws on failure', () async {
        final client = MockClient((request) async {
          return http.Response('error', 500);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        expect(() => service.getSpeakers(), throwsException);
      });
    });

    group('isAvailable', () {
      test('returns true on 200', () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/speakers');
          return http.Response('[]', 200);
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        expect(await service.isAvailable(), true);
      });

      test('returns false on error', () async {
        final client = MockClient((request) async {
          throw Exception('Connection refused');
        });

        final service = VoicevoxService(
          baseUrl: 'http://localhost:50021',
          client: client,
        );
        expect(await service.isAvailable(), false);
      });
    });
  });
}
