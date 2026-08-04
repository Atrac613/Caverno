import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_status_transition.dart';
import 'package:test/test.dart';

void main() {
  const transition = ConversationGoalStatusTransition();
  final now = DateTime(2026, 8, 3);

  test('projects a blocked goal and preserves blocker evidence', () {
    final result = transition.apply(
      goal: _goal().copyWith(
        blockerSignature: 'permission denied',
        blockerRepeatCount: 2,
        lastBlockerSeenAt: now.subtract(const Duration(minutes: 1)),
      ),
      status: ConversationGoalStatus.blocked,
      blockedReason: '  Access is unavailable  ',
      now: now,
    );

    expect(result?.status, ConversationGoalStatus.blocked);
    expect(result?.blockedReason, 'Access is unavailable');
    expect(result?.blockerSignature, 'permission denied');
    expect(result?.blockerRepeatCount, 2);
    expect(result?.blockedAt, now);
  });

  test('projects completion and clears blocker evidence', () {
    final result = transition.apply(
      goal: _goal().copyWith(
        blockedReason: 'Old blocker',
        blockerSignature: 'old blocker',
        blockerRepeatCount: 2,
        lastBlockerSeenAt: now,
      ),
      status: ConversationGoalStatus.completed,
      completionSummary: '  Verified  ',
      now: now,
    );

    expect(result?.status, ConversationGoalStatus.completed);
    expect(result?.completionSummary, 'Verified');
    expect(result?.blockedReason, isEmpty);
    expect(result?.blockerSignature, isEmpty);
    expect(result?.blockerRepeatCount, 0);
    expect(result?.lastBlockerSeenAt, isNull);
    expect(result?.completedAt, now);
  });

  test('rejects a missing goal or objective', () {
    expect(
      transition.apply(goal: null, status: ConversationGoalStatus.blocked),
      isNull,
    );
    expect(
      transition.apply(
        goal: _goal().copyWith(objective: '  '),
        status: ConversationGoalStatus.blocked,
      ),
      isNull,
    );
  });
}

ConversationGoal _goal() => ConversationGoal(
  id: 'goal-a',
  objective: 'Complete the task',
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
);
