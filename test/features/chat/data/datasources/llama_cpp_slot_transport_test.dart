import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_transport.dart';

void main() {
  group('LlamaCppTimings', () {
    test('parses timing fields and cached share', () {
      final timings = LlamaCppTimings.fromJson({
        'cache_n': 900,
        'prompt_n': 100,
        'prompt_ms': 130.0,
        'predicted_n': 8,
        'predicted_ms': 40.0,
        'prompt_per_second': '770.0',
      });

      expect(timings.cacheN, 900);
      expect(timings.promptN, 100);
      expect(timings.promptMs, 130.0);
      expect(timings.predictedN, 8);
      expect(timings.promptPerSecond, 770.0);
      expect(timings.hasCacheTiming, isTrue);
      expect(timings.cachedPromptShare, closeTo(0.9, 0.0001));
    });
  });

  group('LlamaCppSlotTransport', () {
    test(
      'round-trips id_slot, cache_prompt, and tools into the request',
      () async {
        late Map<String, dynamic> sentBody;
        late Uri sentUri;
        final transport = LlamaCppSlotTransport(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: 'secret-key',
          client: MockClient((request) async {
            sentUri = request.url;
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': 'ok'},
                    'finish_reason': 'stop',
                  },
                ],
                'usage': {'prompt_tokens': 10, 'completion_tokens': 2},
                'id_slot': 3,
                'timings': {'cache_n': 50, 'prompt_n': 10, 'prompt_ms': 12.0},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final result = await transport.createChatCompletion(
          model: 'local-model',
          messages: const [
            {'role': 'system', 'content': 'You are a test.'},
            {'role': 'user', 'content': 'hi'},
          ],
          tools: const [
            {
              'type': 'function',
              'function': {'name': 'read_file'},
            },
          ],
          temperature: 0.0,
          maxTokens: 16,
          idSlot: 3,
        );

        // Request preserves the extension fields the typed SDK drops.
        expect(sentUri.toString(), 'http://localhost:1234/v1/chat/completions');
        expect(sentBody['id_slot'], 3);
        expect(sentBody['cache_prompt'], isTrue);
        expect(sentBody['max_tokens'], 16);
        expect(sentBody['stream'], isFalse);
        expect((sentBody['tools'] as List), hasLength(1));

        // Response extension fields round-trip back.
        expect(result.content, 'ok');
        expect(result.finishReason, 'stop');
        expect(result.idSlot, 3);
        expect(result.promptTokens, 10);
        expect(result.completionTokens, 2);
        expect(result.timings!.cacheN, 50);
        expect(result.timings!.cachedPromptShare, closeTo(0.8333, 0.0001));
      },
    );

    test(
      'omits id_slot when not pinned (non-slot endpoints behave as today)',
      () async {
        late Map<String, dynamic> sentBody;
        final transport = LlamaCppSlotTransport(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: '',
          client: MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'hello'},
                    'finish_reason': 'stop',
                  },
                ],
              }),
              200,
            );
          }),
        );

        final result = await transport.createChatCompletion(
          model: 'local-model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        );

        expect(sentBody.containsKey('id_slot'), isFalse);
        expect(result.idSlot, isNull);
        expect(result.timings, isNull);
        expect(result.content, 'hello');
      },
    );

    test('throws SlotChatTransportException on a non-2xx response', () async {
      final transport = LlamaCppSlotTransport(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'k',
        client: MockClient((request) async {
          return http.Response('invalid slot', 400);
        }),
      );

      expect(
        () => transport.createChatCompletion(
          model: 'local-model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          idSlot: 99,
        ),
        throwsA(
          isA<SlotChatTransportException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.body, 'body', contains('invalid slot')),
        ),
      );
    });

    test('falls back to the requested slot when the server omits id_slot', () {
      final result = SlotChatResult.fromResponseJson({
        'choices': [
          {
            'message': {'content': 'x'},
            'finish_reason': 'stop',
          },
        ],
      }, requestedIdSlot: 5);
      expect(result.idSlot, 5);
    });
  });
}
