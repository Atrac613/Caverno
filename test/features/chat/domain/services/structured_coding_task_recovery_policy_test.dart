import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/goal/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/structured_coding_task_recovery_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = StructuredCodingTaskRecoveryPolicy();
  final goal = ConversationGoal(
    id: 'task',
    objective: 'Implement the task',
    projectTaskAutoReview: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  test('explicit implementation metadata selects the protocol', () {
    expect(policy.applies(goal: goal, implementationTurn: true), isTrue);
    expect(policy.applies(goal: goal, implementationTurn: false), isFalse);
    expect(policy.applies(goal: null, implementationTurn: true), isFalse);
  });
  test(
    'status separates accepted implementation from pending review and commit',
    () {
      expect(
        policy.prompt,
        contains(
          'review, roadmap update and commit are not remaining implementation work',
        ),
      );
      expect(
        policy.prompt,
        contains(
          'Never report completion without captured change and successful verification evidence',
        ),
      );
      expect(
        policy.prompt,
        contains(
          'PROJECT_TASK_READY_FOR_REVIEW; omit it while incomplete or blocked',
        ),
      );
    },
  );
  test('missing or incomplete acknowledgement requires one status request', () {
    for (final ack in [
      null,
      GoalUpdateAckOutcome.progressLogged,
      GoalUpdateAckOutcome.completionRejected,
    ]) {
      expect(
        policy.shouldRequestStatus(
          goal: goal,
          boundarySafe: true,
          acknowledgement: ack,
        ),
        isTrue,
      );
    }
    for (final ack in [
      GoalUpdateAckOutcome.completionRecorded,
      GoalUpdateAckOutcome.blockerLogged,
      GoalUpdateAckOutcome.confirmationRequired,
      GoalUpdateAckOutcome.pausedAtCap,
    ]) {
      expect(
        policy.shouldRequestStatus(
          goal: goal,
          boundarySafe: true,
          acknowledgement: ack,
        ),
        isFalse,
      );
    }
  });
  test(
    'approval, user input, inactive goals, and exhausted budgets stop recovery',
    () {
      expect(
        policy.shouldRequestStatus(
          goal: goal,
          boundarySafe: false,
          acknowledgement: null,
        ),
        isFalse,
      );
      expect(
        policy.shouldRequestStatus(
          goal: goal.copyWith(status: ConversationGoalStatus.blocked),
          boundarySafe: true,
          acknowledgement: null,
        ),
        isFalse,
      );
      expect(
        policy.shouldRequestStatus(
          goal: goal.copyWith(turnBudget: 1, turnsUsed: 1),
          boundarySafe: true,
          acknowledgement: null,
        ),
        isFalse,
      );
    },
  );
}
