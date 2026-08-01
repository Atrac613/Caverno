import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/content_tool_turn_state_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sharedGeneration = 23;
  final ownerA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: sharedGeneration,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'thread-b',
    interactionGeneration: sharedGeneration,
  );

  test('requires an explicit owner lifecycle and returns immutable views', () {
    final registry = ContentToolTurnStateRegistry();

    expect(registry.length, 0);
    expect(registry.isEmpty, isTrue);
    expect(registry.contains(ownerA), isFalse);
    expect(registry.hasSeenCall(ownerA, 'seen-a'), isFalse);
    expect(registry.hasExecutedCall(ownerA, 'executed-a'), isFalse);
    expect(registry.markSeenCall(ownerA, 'seen-a'), isFalse);
    expect(registry.markExecutedCall(ownerA, 'executed-a'), isFalse);
    expect(registry.addPendingResult(ownerA, 'result-a'), isFalse);
    expect(registry.pendingResultCount(ownerA), 0);
    expect(registry.pendingResults(ownerA), isEmpty);
    expect(registry.takePendingResults(ownerA), isEmpty);
    expect(registry.setContinuationFallback(ownerA, 'fallback-a'), isFalse);
    expect(registry.continuationFallback(ownerA), isNull);
    expect(registry.continuationCount(ownerA), 0);
    expect(registry.incrementContinuationCount(ownerA), isNull);
    expect(registry.resetContinuationCount(ownerA), isFalse);
    expect(registry.pendingExecutionCount(ownerA), 0);
    expect(registry.enqueueExecution(ownerA, () async {}), isNull);
    expect(registry.snapshot(ownerA), isNull);

    expect(registry.begin(ownerA), isTrue);
    expect(registry.begin(ownerA), isFalse);
    expect(registry.length, 1);
    expect(registry.isEmpty, isFalse);
    expect(registry.contains(ownerA), isTrue);
    expect(registry.markSeenCall(ownerA, 'seen-a'), isTrue);
    expect(registry.hasSeenCall(ownerA, 'seen-a'), isTrue);
    expect(registry.markExecutedCall(ownerA, 'executed-a'), isTrue);
    expect(registry.hasExecutedCall(ownerA, 'executed-a'), isTrue);
    expect(registry.addPendingResult(ownerA, 'result-a'), isTrue);
    expect(registry.pendingResultCount(ownerA), 1);
    expect(registry.setContinuationFallback(ownerA, 'fallback-a'), isTrue);
    expect(registry.incrementContinuationCount(ownerA), 1);

    final snapshot = registry.snapshot(ownerA)!;
    expect(snapshot.seenCallHashes, {'seen-a'});
    expect(snapshot.executedCallKeys, {'executed-a'});
    expect(snapshot.pendingResults, ['result-a']);
    expect(snapshot.pendingExecutionCount, 0);
    expect(snapshot.continuationFallback, 'fallback-a');
    expect(snapshot.continuationCount, 1);
    expect(
      () => snapshot.seenCallHashes.add('blocked'),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.executedCallKeys.add('blocked'),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.pendingResults.add('blocked'),
      throwsUnsupportedError,
    );

    final taken = registry.takePendingResults(ownerA);
    expect(taken, ['result-a']);
    expect(() => taken.add('blocked'), throwsUnsupportedError);
    expect(registry.pendingResults(ownerA), isEmpty);
    expect(registry.takePendingResults(ownerA), isEmpty);
  });

  test('equal-generation owners cannot poison each other', () {
    final registry = ContentToolTurnStateRegistry();
    registry
      ..begin(ownerA)
      ..begin(ownerB);

    expect(registry.markSeenCall(ownerA, 'shared-hash'), isTrue);
    expect(registry.markSeenCall(ownerA, 'shared-hash'), isFalse);
    expect(registry.markSeenCall(ownerB, 'shared-hash'), isTrue);
    expect(registry.markExecutedCall(ownerA, 'shared-key'), isTrue);
    expect(registry.markExecutedCall(ownerA, 'shared-key'), isFalse);
    expect(registry.markExecutedCall(ownerB, 'shared-key'), isTrue);
    registry
      ..addPendingResult(ownerA, 'result-a')
      ..addPendingResult(ownerB, 'result-b')
      ..setContinuationFallback(ownerA, 'fallback-a')
      ..setContinuationFallback(ownerB, 'fallback-b')
      ..incrementContinuationCount(ownerA)
      ..incrementContinuationCount(ownerB)
      ..incrementContinuationCount(ownerB);

    final snapshotA = registry.snapshot(ownerA)!;
    final snapshotB = registry.snapshot(ownerB)!;
    expect(snapshotA.pendingResults, ['result-a']);
    expect(snapshotB.pendingResults, ['result-b']);
    expect(snapshotA.continuationFallback, 'fallback-a');
    expect(snapshotB.continuationFallback, 'fallback-b');
    expect(snapshotA.continuationCount, 1);
    expect(snapshotB.continuationCount, 2);

    expect(registry.takePendingResults(ownerA), ['result-a']);
    expect(registry.pendingResults(ownerB), ['result-b']);
    expect(registry.resetContinuationCount(ownerA), isTrue);
    expect(registry.continuationCount(ownerA), 0);
    expect(registry.continuationCount(ownerB), 2);
  });

  test(
    'serializes each owner and drains only the captured pending batch',
    () async {
      final registry = ContentToolTurnStateRegistry();
      registry
        ..begin(ownerA)
        ..begin(ownerB);
      final firstGate = Completer<void>();
      final laterGate = Completer<void>();
      final events = <String>[];

      registry.enqueueExecution(ownerA, () async {
        events.add('a1-start');
        await firstGate.future;
        events.add('a1-end');
      });
      registry.enqueueExecution(ownerA, () async {
        events.add('a2');
      });
      registry.enqueueExecution(ownerB, () async {
        events.add('b1');
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, ['a1-start', 'b1']);
      expect(registry.pendingExecutionCount(ownerA), 2);
      expect(registry.pendingExecutionCount(ownerB), 1);

      final firstDrain = registry.drainPendingExecutions(ownerA);
      registry.enqueueExecution(ownerA, () async {
        await laterGate.future;
        events.add('a3');
      });
      expect(registry.pendingExecutionCount(ownerA), 1);

      firstGate.complete();
      expect(await firstDrain, 2);
      expect(events, ['a1-start', 'b1', 'a1-end', 'a2']);
      expect(registry.pendingExecutionCount(ownerA), 1);
      expect(registry.pendingExecutionCount(ownerB), 1);

      laterGate.complete();
      expect(await registry.drainPendingExecutions(ownerA), 1);
      expect(events, ['a1-start', 'b1', 'a1-end', 'a2', 'a3']);
      expect(await registry.drainPendingExecutions(ownerB), 1);
      expect(registry.pendingExecutionCount(ownerB), 0);
      expect(await registry.drainPendingExecutions(ownerB), 0);
    },
  );

  test('a failed execution does not poison the serialized tail', () async {
    final registry = ContentToolTurnStateRegistry()..begin(ownerA);
    final events = <String>[];

    registry.enqueueExecution(ownerA, () async {
      events.add('failed');
      throw StateError('expected failure');
    });
    registry.enqueueExecution(ownerA, () async {
      events.add('recovered');
    });

    await expectLater(
      registry.drainPendingExecutions(ownerA),
      throwsA(isA<StateError>()),
    );
    expect(events, ['failed', 'recovered']);
    expect(registry.pendingExecutionCount(ownerA), 0);
  });

  test(
    'dispose blocks late writes and queued execution resurrection',
    () async {
      final registry = ContentToolTurnStateRegistry()..begin(ownerA);
      final gate = Completer<void>();
      var lateWriteAccepted = true;
      var queuedAfterDisposeRan = false;

      final activeExecution = registry.enqueueExecution(ownerA, () async {
        await gate.future;
        lateWriteAccepted = registry.addPendingResult(ownerA, 'late');
      })!;
      final queuedExecution = registry.enqueueExecution(ownerA, () async {
        queuedAfterDisposeRan = true;
      })!;
      await Future<void>.delayed(Duration.zero);

      expect(registry.dispose(ownerA), isTrue);
      expect(registry.dispose(ownerA), isFalse);
      expect(registry.contains(ownerA), isFalse);
      expect(registry.begin(ownerA), isFalse);
      expect(registry.addPendingResult(ownerA, 'later'), isFalse);

      gate.complete();
      await Future.wait([activeExecution, queuedExecution]);
      expect(lateWriteAccepted, isFalse);
      expect(queuedAfterDisposeRan, isFalse);
      expect(registry.snapshot(ownerA), isNull);
      expect(registry.isEmpty, isTrue);
    },
  );

  test('clear terminalizes current owners but permits newer turns', () {
    final registry = ContentToolTurnStateRegistry();
    registry
      ..begin(ownerA)
      ..begin(ownerB)
      ..addPendingResult(ownerA, 'result-a')
      ..addPendingResult(ownerB, 'result-b')
      ..clear();

    expect(registry.isEmpty, isTrue);
    expect(registry.begin(ownerA), isFalse);
    expect(registry.begin(ownerB), isFalse);

    final nextOwnerA = ChatTurnOwner(
      conversationId: ownerA.conversationId,
      interactionGeneration: sharedGeneration + 1,
    );
    expect(registry.begin(nextOwnerA), isTrue);
    expect(registry.addPendingResult(nextOwnerA, 'next-result'), isTrue);
    expect(registry.pendingResults(nextOwnerA), ['next-result']);
  });
}
