import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = GoalUpdateAckResolver();

  group('resolveCall + toToolResult (dispatch entry)', () {
    ToolCallInfo call(Map<String, dynamic> args) =>
        ToolCallInfo(id: 't1', name: 'update_goal', arguments: args);

    test('a rejected completion is a successful result carrying the gaps', () {
      final ack = resolver.resolveCall(
        toolCall: call(const {'completed': true}),
        goal: _goal(),
        evidence: const ToolResultCompletionEvidence(unresolvedErrorCount: 1),
      );
      final result = ack.toToolResult('update_goal');

      // Well-formed call the harness answered → success, verdict in the body.
      expect(ack.isCompletionClaim, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.result, contains('not recorded'));
      expect(result.result, contains('unresolved error'));
    });

    test('no active goal is a tool failure', () {
      final ack = resolver.resolveCall(
        toolCall: call(const {'completed': true}),
        goal: null,
      );
      final result = ack.toToolResult('update_goal');

      expect(ack.outcome, GoalUpdateAckOutcome.rejectedInactive);
      expect(ack.isCompletionClaim, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('no active goal to update'));
    });

    test('parses arguments from the raw call', () {
      final ack = resolver.resolveCall(
        toolCall: call(const {'blocked_reason': 'missing key'}),
        goal: _goal(),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.blockerLogged);
      expect(ack.toToolResult('update_goal').result, contains('missing key'));
    });
  });

  group('inactive goal', () {
    test('rejects any update when there is no active goal', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true),
        goal: _goal(status: ConversationGoalStatus.completed),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.rejectedInactive);
      expect(ack.completionAccepted, isFalse);
    });
  });

  group('completion', () {
    test('records completion when no mechanical evidence contradicts it', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true),
        goal: _goal(),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.completionRecorded);
      expect(ack.completionAccepted, isTrue);
      // The message must not overstate: not contradicted is not verified.
      expect(ack.modelMessage, contains('not been independently verified'));
    });

    test('rejects completion when errors remain unresolved', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true),
        goal: _goal(),
        evidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 2,
          unresolvedErrorPaths: ['lib/a.dart', 'lib/b.dart'],
        ),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.completionRejected);
      expect(ack.gaps, isNotEmpty);
      expect(ack.gaps.first, contains('2 unresolved error'));
      expect(ack.gaps.first, contains('lib/a.dart'));
    });

    test('rejects completion on a failed verification', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true),
        goal: _goal(),
        evidence: const ToolResultCompletionEvidence(
          hasFailedExecutionVerification: true,
        ),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.completionRejected);
      expect(ack.gaps, contains('the last verification command failed'));
    });

    test('rejects completion when a mutation was never verified', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true),
        goal: _goal(),
        evidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          unverifiedChangePaths: ['lib/x.dart'],
        ),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.completionRejected);
      expect(ack.gaps.any((g) => g.contains('lib/x.dart')), isTrue);
    });

    test('surfaces every distinct evidence source, in priority order', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true),
        goal: _goal(),
        evidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 1,
          hasFailedExecutionVerification: true,
          boundedToolLoopExhausted: true,
          unverifiedChangePaths: ['a', 'b'],
          mutatedWithoutExecutionVerification: true,
          hasUnexecutedActionClaim: true,
        ),
      );

      // Six distinct evidence sources, so six gaps, bounded by construction.
      expect(ack.gaps.length, 6);
      expect(ack.gaps.first, contains('unresolved error'));
      expect(ack.gaps[1], contains('verification command failed'));
    });
  });

  group('non-completion updates', () {
    test('logs a blocker against an active goal', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(blockedReason: 'missing API key'),
        goal: _goal(),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.blockerLogged);
      expect(ack.modelMessage, contains('missing API key'));
    });

    test('logs a bare progress message', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(message: 'wrote the parser'),
        goal: _goal(),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.progressLogged);
      expect(ack.modelMessage, contains('wrote the parser'));
    });

    test('a completion claim outranks an accompanying blocker', () {
      final ack = resolver.resolve(
        input: const GoalUpdateInput(completed: true, blockedReason: 'ignored'),
        goal: _goal(),
      );

      expect(ack.outcome, GoalUpdateAckOutcome.completionRecorded);
    });
  });
}

ConversationGoal _goal({
  ConversationGoalStatus status = ConversationGoalStatus.active,
}) {
  return ConversationGoal(
    id: 'goal-1',
    objective: 'Fix analyzer errors',
    enabled: true,
    status: status,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
