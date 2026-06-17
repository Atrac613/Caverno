import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_math.dart';

void main() {
  group('EmbeddingsMath.cosineSimilarity', () {
    test('is 1 for identical, 0 for orthogonal, -1 for opposite', () {
      expect(
        EmbeddingsMath.cosineSimilarity([1, 2, 3], [1, 2, 3]),
        closeTo(1, 1e-9),
      );
      expect(EmbeddingsMath.cosineSimilarity([1, 0], [0, 1]), closeTo(0, 1e-9));
      expect(
        EmbeddingsMath.cosineSimilarity([1, 0], [-1, 0]),
        closeTo(-1, 1e-9),
      );
    });

    test('returns 0 for zero-magnitude or mismatched-length vectors', () {
      expect(EmbeddingsMath.cosineSimilarity([0, 0], [1, 1]), 0);
      expect(EmbeddingsMath.cosineSimilarity([1, 2, 3], [1, 2]), 0);
      expect(EmbeddingsMath.cosineSimilarity(const [], const []), 0);
    });
  });

  group('EmbeddingsClient', () {
    test('posts {model,input} and parses vectors in input order', () async {
      late Map<String, dynamic> sentBody;
      late Uri sentUri;
      final client = EmbeddingsClient(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'k',
        client: MockClient((request) async {
          sentUri = request.url;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          // Deliberately out of order to verify index sorting.
          return http.Response(
            jsonEncode({
              'model': 'text-embed',
              'data': [
                {
                  'index': 1,
                  'embedding': [0.1, 0.2],
                },
                {
                  'index': 0,
                  'embedding': [0.3, 0.4],
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await client.embed(
        inputs: ['first', 'second'],
        model: 'text-embed',
      );

      expect(sentUri.toString(), 'http://localhost:1234/v1/embeddings');
      expect(sentBody['model'], 'text-embed');
      expect(sentBody['input'], ['first', 'second']);
      expect(result, isNotNull);
      expect(result!.dimension, 2);
      expect(result.vectors[0], [0.3, 0.4]); // index 0 first
      expect(result.vectors[1], [0.1, 0.2]);
    });

    test(
      'returns an empty result for empty input without calling the endpoint',
      () async {
        var called = false;
        final client = EmbeddingsClient(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: '',
          client: MockClient((request) async {
            called = true;
            return http.Response('{}', 200);
          }),
        );
        final result = await client.embed(inputs: const [], model: 'm');
        expect(called, isFalse);
        expect(result!.vectors, isEmpty);
      },
    );

    test(
      'degrades to null on non-2xx, malformed body, or network error',
      () async {
        final non2xx = EmbeddingsClient(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: '',
          client: MockClient((_) async => http.Response('nope', 404)),
        );
        expect(await non2xx.embed(inputs: ['x'], model: 'm'), isNull);

        final malformed = EmbeddingsClient(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: '',
          client: MockClient((_) async => http.Response('not json', 200)),
        );
        expect(await malformed.embed(inputs: ['x'], model: 'm'), isNull);

        final networkError = EmbeddingsClient(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: '',
          client: MockClient((_) async => throw const _NetworkDown()),
        );
        expect(await networkError.embed(inputs: ['x'], model: 'm'), isNull);
      },
    );
  });
}

class _NetworkDown implements Exception {
  const _NetworkDown();
}
