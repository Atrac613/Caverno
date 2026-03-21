import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/core/services/whisper_service.dart';

void main() {
  group('WhisperService', () {
    group('transcribe', () {
      test('returns text on 200 response', () async {
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, contains('audio/transcriptions'));
          return http.Response(jsonEncode({'text': 'hello world'}), 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        final result = await service.transcribe(Uint8List.fromList([0, 1, 2]));
        expect(result, 'hello world');
      });

      test('trims whitespace from result', () async {
        final client = MockClient((request) async {
          return http.Response(jsonEncode({'text': '  spaced  '}), 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        final result = await service.transcribe(Uint8List.fromList([0]));
        expect(result, 'spaced');
      });

      test('returns empty string when text is null', () async {
        final client = MockClient((request) async {
          return http.Response(jsonEncode({'text': null}), 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        final result = await service.transcribe(Uint8List.fromList([0]));
        expect(result, '');
      });

      test('throws on non-200 response', () async {
        final client = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        expect(
          () => service.transcribe(Uint8List.fromList([0])),
          throwsException,
        );
      });

      test('uses /audio/transcriptions endpoint for v1 URL', () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/v1/audio/transcriptions');
          return http.Response(jsonEncode({'text': 'ok'}), 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        await service.transcribe(Uint8List.fromList([0]));
      });

      test('uses /inference endpoint for non-v1 URL', () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/inference');
          return http.Response(jsonEncode({'text': 'ok'}), 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080',
          client: client,
        );
        await service.transcribe(Uint8List.fromList([0]));
      });
    });

    group('isAvailable', () {
      test('returns true on 200 response', () async {
        final client = MockClient((request) async {
          return http.Response('ok', 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        expect(await service.isAvailable(), true);
      });

      test('returns false on non-200 response', () async {
        final client = MockClient((request) async {
          return http.Response('', 503);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        expect(await service.isAvailable(), false);
      });

      test('returns false on network error', () async {
        final client = MockClient((request) async {
          throw Exception('Connection refused');
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        expect(await service.isAvailable(), false);
      });

      test('checks /v1/models for v1 URL', () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/v1/models');
          return http.Response('ok', 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080/v1',
          client: client,
        );
        await service.isAvailable();
      });

      test('checks /props for non-v1 URL', () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/props');
          return http.Response('ok', 200);
        });

        final service = WhisperService(
          baseUrl: 'http://localhost:8080',
          client: client,
        );
        await service.isAvailable();
      });
    });
  });
}
