import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_exit_reason.dart';
import 'package:caverno/features/chat/presentation/providers/turn_finalization_state_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 7,
  );

  test('requires an active owner and preserves transform order', () {
    final registry = TurnFinalizationStateRegistry();

    expect(registry.isEmpty, isTrue);
    expect(registry.length, 0);
    expect(registry.contains(owner), isFalse);
    expect(registry.reset(owner), isFalse);
    expect(registry.setHint(owner, ToolLoopExitReason.guardrailBlock), isFalse);
    expect(
      registry.setHintIfAbsent(owner, ToolLoopExitReason.pendingBatchExecuted),
      isFalse,
    );
    expect(registry.takeHint(owner), isNull);
    expect(registry.addTransform(owner, 'missing'), isFalse);
    expect(registry.transforms(owner), isEmpty);
    expect(
      registry.setGoalOutcome(owner, GoalUpdateAckOutcome.completionRecorded),
      isFalse,
    );
    expect(registry.takeGoalOutcome(owner), isNull);
    expect(registry.markGoalClaimed(owner), isFalse);
    expect(registry.takeGoalClaim(owner), isFalse);

    expect(registry.begin(owner), isTrue);
    expect(registry.begin(owner), isFalse);
    expect(registry.contains(owner), isTrue);
    expect(registry.length, 1);
    expect(registry.isEmpty, isFalse);

    expect(registry.addTransform(owner, 'first'), isTrue);
    expect(registry.addTransform(owner, 'second'), isTrue);
    expect(registry.addTransform(owner, 'first'), isFalse);
    final transforms = registry.transforms(owner);
    expect(transforms, ['first', 'second']);
    expect(() => transforms.add('third'), throwsUnsupportedError);

    expect(
      registry.setGoalOutcome(owner, GoalUpdateAckOutcome.completionRecorded),
      isTrue,
    );
    expect(registry.markGoalClaimed(owner), isTrue);
    expect(registry.markGoalClaimed(owner), isTrue);
    expect(registry.takeGoalClaim(owner), isTrue);
    expect(registry.takeGoalClaim(owner), isFalse);
    expect(
      registry.takeGoalOutcome(owner),
      GoalUpdateAckOutcome.completionRecorded,
    );
    expect(registry.takeGoalOutcome(owner), isNull);
  });

  test('keeps equal generations isolated by conversation', () {
    final peer = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 7,
    );
    final registry = TurnFinalizationStateRegistry();

    expect(registry.begin(owner), isTrue);
    expect(registry.begin(peer), isTrue);
    expect(
      registry.setHint(owner, ToolLoopExitReason.toolFailureAbort),
      isTrue,
    );
    expect(registry.setHint(peer, ToolLoopExitReason.guardrailBlock), isTrue);
    expect(registry.addTransform(owner, 'a-first'), isTrue);
    expect(registry.addTransform(peer, 'b-first'), isTrue);
    expect(
      registry.setGoalOutcome(owner, GoalUpdateAckOutcome.completionRecorded),
      isTrue,
    );
    expect(
      registry.setGoalOutcome(peer, GoalUpdateAckOutcome.completionRejected),
      isTrue,
    );
    expect(registry.markGoalClaimed(owner), isTrue);

    expect(registry.takeHint(owner), ToolLoopExitReason.toolFailureAbort);
    expect(registry.takeHint(owner), isNull);
    expect(registry.takeGoalClaim(owner), isTrue);
    expect(registry.takeGoalClaim(owner), isFalse);
    expect(
      registry.takeGoalOutcome(owner),
      GoalUpdateAckOutcome.completionRecorded,
    );
    expect(registry.takeGoalOutcome(owner), isNull);
    expect(registry.transforms(owner), ['a-first']);

    expect(registry.takeHint(peer), ToolLoopExitReason.guardrailBlock);
    expect(registry.takeGoalClaim(peer), isFalse);
    expect(
      registry.takeGoalOutcome(peer),
      GoalUpdateAckOutcome.completionRejected,
    );
    expect(registry.transforms(peer), ['b-first']);
  });

  test('preserves replacement and set-if-absent hint semantics', () {
    final registry = TurnFinalizationStateRegistry();
    expect(registry.begin(owner), isTrue);

    expect(
      registry.setHintIfAbsent(owner, ToolLoopExitReason.pendingBatchExecuted),
      isTrue,
    );
    expect(
      registry.setHintIfAbsent(owner, ToolLoopExitReason.maxIterations),
      isFalse,
    );
    expect(
      registry.setHint(owner, ToolLoopExitReason.toolFailureAbort),
      isTrue,
    );
    expect(registry.takeHint(owner), ToolLoopExitReason.toolFailureAbort);
    expect(
      registry.setHintIfAbsent(owner, ToolLoopExitReason.maxIterations),
      isTrue,
    );
    expect(registry.takeHint(owner), ToolLoopExitReason.maxIterations);
  });

  test('reset and disposal are owner-local and reject late writes', () {
    final peer = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 7,
    );
    final newerOwner = ChatTurnOwner(
      conversationId: 'thread-a',
      interactionGeneration: 8,
    );
    final newerPeer = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 8,
    );
    final registry = TurnFinalizationStateRegistry();

    expect(registry.begin(owner), isTrue);
    expect(registry.begin(peer), isTrue);
    expect(registry.addTransform(owner, 'a'), isTrue);
    expect(registry.addTransform(peer, 'b'), isTrue);
    expect(registry.setHint(owner, ToolLoopExitReason.emptyResponse), isTrue);
    expect(registry.markGoalClaimed(owner), isTrue);

    expect(registry.reset(owner), isTrue);
    expect(registry.reset(owner), isTrue);
    expect(registry.transforms(owner), isEmpty);
    expect(registry.takeHint(owner), isNull);
    expect(registry.takeGoalClaim(owner), isFalse);
    expect(registry.transforms(peer), ['b']);
    expect(registry.addTransform(owner, 'a-after-reset'), isTrue);

    expect(registry.dispose(owner), isTrue);
    expect(registry.dispose(owner), isFalse);
    expect(registry.contains(owner), isFalse);
    expect(registry.begin(owner), isFalse);
    expect(registry.reset(owner), isFalse);
    expect(registry.addTransform(owner, 'late'), isFalse);
    expect(registry.setHint(owner, ToolLoopExitReason.unknown), isFalse);
    expect(
      registry.setGoalOutcome(owner, GoalUpdateAckOutcome.completionRejected),
      isFalse,
    );
    expect(registry.markGoalClaimed(owner), isFalse);
    expect(registry.transforms(peer), ['b']);

    expect(registry.begin(newerOwner), isTrue);
    registry.clear();
    expect(registry.isEmpty, isTrue);
    expect(registry.begin(peer), isFalse);
    expect(registry.begin(newerOwner), isFalse);
    expect(registry.begin(newerPeer), isTrue);
    registry.clear();
    registry.clear();
    expect(registry.isEmpty, isTrue);
  });
}
