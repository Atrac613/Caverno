import 'dart:async';

import 'package:caverno/features/chat/application/runtime/turn_abort_signals.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:flutter_test/flutter_test.dart';

ChatTurnOwner _owner(String conversationId, int generation) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );

void main() {
  group('TurnAbortSignals', () {
    test('aborting one turn leaves another thread running', () {
      final signals = TurnAbortSignals();
      final a = _owner('thread-a', 10);
      final b = _owner('thread-b', 3);
      signals
        ..signalFor(a)
        ..signalFor(b);

      signals.abort(a);

      expect(signals.isAborted(a), isTrue);
      expect(signals.isAborted(b), isFalse);
    });

    test('abort is idempotent', () {
      final signals = TurnAbortSignals();
      final owner = _owner('thread-a', 10);
      signals.signalFor(owner);

      signals
        ..abort(owner)
        ..abort(owner);

      expect(signals.isAborted(owner), isTrue);
    });

    test('a released signal is not inherited by the next turn', () {
      final signals = TurnAbortSignals();
      final cancelled = _owner('thread-a', 10);
      signals
        ..signalFor(cancelled)
        ..abort(cancelled)
        ..release(cancelled);

      // Same thread, next generation. Inheriting the completed signal would
      // abort the new turn before it read a single chunk.
      final next = _owner('thread-a', 11);
      signals.signalFor(next);

      expect(signals.isAborted(next), isFalse);
      expect(signals.trackedCount, 1);
    });

    test('abortAll ends every tracked turn', () {
      final signals = TurnAbortSignals();
      final a = _owner('thread-a', 10);
      final b = _owner('thread-b', 3);
      signals
        ..signalFor(a)
        ..signalFor(b)
        ..abortAll();

      expect(signals.isAborted(a), isTrue);
      expect(signals.isAborted(b), isTrue);
    });
  });

  group('TurnAbortScope', () {
    test('a request issued inside the scope reads the turn signal', () {
      final signals = TurnAbortSignals();
      final owner = _owner('thread-a', 10);
      final expected = signals.signalFor(owner);

      // Read where the datasource reads it: synchronously, while the request is
      // still being built. A lazily-listened response stream runs outside this
      // zone, so a read from inside the generator would see null.
      final seen = TurnAbortScope.runWith(
        expected,
        () => TurnAbortScope.current,
      );

      expect(seen, same(expected));
      expect(TurnAbortScope.current, isNull, reason: 'the zone does not leak');
    });

    test('no signal means no scope value', () {
      expect(TurnAbortScope.runWith(null, () => TurnAbortScope.current), isNull);
    });
  });

  group('endOnAbort', () {
    test('passes chunks through and ends with the source', () async {
      final chunks = await endOnAbort(
        Stream<String>.fromIterable(['a', 'b']),
        Completer<void>().future,
      ).toList();

      expect(chunks, ['a', 'b']);
    });

    test('ends the stream and cancels the source when the abort fires', () async {
      final signals = TurnAbortSignals();
      final owner = _owner('thread-a', 10);
      final source = StreamController<String>();
      var sourceCancelled = false;
      source.onCancel = () => sourceCancelled = true;

      final received = <String>[];
      final drained = endOnAbort(
        source.stream,
        signals.signalFor(owner),
      ).forEach(received.add);

      source.add('first');
      await pumpEventQueue();
      signals.abort(owner);
      await drained;

      expect(received, ['first']);
      expect(
        sourceCancelled,
        isTrue,
        reason:
            'The cancel is what aborts the request; without it the server keeps '
            'generating for a turn nobody is reading.',
      );
      await source.close();
    });

    test('a silent source still ends on abort', () async {
      // The case the stop button exists for: an `await for` can only notice a
      // cancelled generation when a chunk arrives, and this source sends none.
      final signals = TurnAbortSignals();
      final owner = _owner('thread-a', 10);
      final source = StreamController<String>();
      var sourceCancelled = false;
      source.onCancel = () => sourceCancelled = true;

      final drained = endOnAbort(
        source.stream,
        signals.signalFor(owner),
      ).drain<void>();

      await pumpEventQueue();
      signals.abort(owner);
      await drained;

      expect(sourceCancelled, isTrue);
      await source.close();
    });

    test('forwards source errors', () async {
      await expectLater(
        endOnAbort(
          Stream<String>.error(StateError('boom')),
          Completer<void>().future,
        ).drain<void>(),
        throwsStateError,
      );
    });
  });
}
