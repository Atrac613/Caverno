import 'dart:async';

import 'package:caverno/features/chat/data/datasources/chat_completion_bounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('boundedCompletion', () {
    test('passes a completion through untouched', () async {
      final result = await boundedCompletion(
        Future.value('answer'),
        'chat completion',
      );

      expect(result, 'answer');
    });

    test('fails a request that never answers', () async {
      // Without this the socket stays half-open and the turn is unrecoverable
      // short of an app restart.
      await expectLater(
        boundedCompletion(
          Completer<String>().future,
          'chat completion',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            contains('chat completion did not respond'),
          ),
        ),
      );
    });
  });

  group('boundedCompletionStream', () {
    test('measures the gap between chunks, not the total', () async {
      // A long answer legitimately streams for far longer than the idle
      // budget; only silence means the connection is wedged.
      final chunks = Stream<String>.periodic(
        const Duration(milliseconds: 20),
        (index) => 'chunk$index',
      ).take(10);

      final received = await boundedCompletionStream(
        chunks,
        'chat stream',
        idleTimeout: const Duration(milliseconds: 100),
      ).toList();

      expect(received, hasLength(10));
    });

    test('ends the stream when a chunk never arrives', () async {
      final controller = StreamController<String>();
      addTearDown(controller.close);
      controller.add('partial');

      final bounded = boundedCompletionStream(
        controller.stream,
        'chat stream',
        idleTimeout: const Duration(milliseconds: 50),
      );

      final received = <String>[];
      await expectLater(
        bounded.forEach(received.add),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            contains('chat stream sent no data'),
          ),
        ),
      );
      expect(received, ['partial']);
    });
  });
}
