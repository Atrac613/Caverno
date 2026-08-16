import 'package:caverno/features/chat/data/datasources/chat_completion_request_fallback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart';

void main() {
  group('ChatCompletionRequestFallback rate limits', () {
    late List<Duration> delays;
    late ChatCompletionRequestFallback fallback;

    setUp(() {
      delays = <Duration>[];
      fallback = ChatCompletionRequestFallback(
        null,
        delay: (duration) async => delays.add(duration),
      );
    });

    test('retries a 429 and returns the eventual success', () async {
      var attempts = 0;
      final result = await fallback.create<String>(
        operation: 'test',
        send: (_) async {
          attempts += 1;
          if (attempts < 3) {
            throw const RateLimitException(message: 'slow down');
          }
          return 'ok';
        },
      );

      expect(result, 'ok');
      expect(attempts, 3);
      expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('waits at least as long as the server asked for', () async {
      var attempts = 0;
      await fallback.create<String>(
        operation: 'test',
        send: (_) async {
          attempts += 1;
          if (attempts == 1) {
            throw const RateLimitException(
              message:
                  'Rate limit reached for gpt-5.6-luna on tokens per min '
                  '(TPM): Limit 200000, Used 190450, Requested 20670. Please '
                  'try again in 3.336s.',
            );
          }
          return 'ok';
        },
      );

      // 3.336s beats the 1s local backoff, and is rounded up rather than down.
      expect(delays.single, const Duration(milliseconds: 3336));
    });

    test('prefers the Retry-After header over the message text', () async {
      var attempts = 0;
      await fallback.create<String>(
        operation: 'test',
        send: (_) async {
          attempts += 1;
          if (attempts == 1) {
            throw const RateLimitException(
              message: 'Please try again in 2s.',
              retryAfter: Duration(seconds: 8),
            );
          }
          return 'ok';
        },
      );

      expect(delays.single, const Duration(seconds: 8));
    });

    test('gives up after the retry budget and rethrows', () async {
      var attempts = 0;

      await expectLater(
        fallback.create<String>(
          operation: 'test',
          send: (_) async {
            attempts += 1;
            throw const RateLimitException(message: 'always limited');
          },
        ),
        throwsA(isA<RateLimitException>()),
      );
      expect(attempts, 5);
      expect(delays, hasLength(4));
    });

    test('does not retry a non-rate-limit failure', () async {
      var attempts = 0;

      await expectLater(
        fallback.create<String>(
          operation: 'test',
          send: (_) async {
            attempts += 1;
            throw const ApiException(message: 'nope', statusCode: 500);
          },
        ),
        throwsA(isA<ApiException>()),
      );
      expect(attempts, 1);
      expect(delays, isEmpty);
    });

    test('retries a stream that failed before emitting anything', () async {
      var attempts = 0;
      final events = await fallback
          .stream<String>(
            operation: 'test',
            send: (_) async* {
              attempts += 1;
              if (attempts == 1) {
                throw const RateLimitException(message: 'slow down');
              }
              yield 'a';
              yield 'b';
            },
          )
          .toList();

      expect(events, ['a', 'b']);
      expect(delays, [const Duration(seconds: 1)]);
    });

    test('never replays a stream that already emitted content', () async {
      var attempts = 0;

      await expectLater(
        fallback
            .stream<String>(
              operation: 'test',
              send: (_) async* {
                attempts += 1;
                yield 'partial';
                throw const RateLimitException(message: 'slow down');
              },
            )
            .toList(),
        throwsA(isA<RateLimitException>()),
      );
      expect(attempts, 1);
      expect(delays, isEmpty);
    });
  });
}
