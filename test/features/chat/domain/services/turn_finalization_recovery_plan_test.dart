import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/turn_finalization_recovery_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final goal = ConversationGoal(
    id: 'goal',
    objective: 'Task',
    projectTaskAutoReview: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  Map<String, dynamic> tool(String name) => {
    'type': 'function',
    'function': {'name': name},
  };
  TurnFinalizationRecoveryPlan plan({
    bool implementation = true,
    String response = 'Done.',
    bool boundary = true,
    GoalUpdateAckOutcome? ack,
    bool offerStatus = true,
  }) => TurnFinalizationRecoveryPlan(
    goal: goal,
    implementationTurn: implementation,
    boundarySafe: boundary,
    acknowledgement: ack,
    parentTurn: false,
    response: response,
    completedResults: [],
    hasSavedValidation: false,
    hasGitLifecycle: false,
    skipCompletedAnswer: true,
    allTools: [tool('write_file'), if (offerStatus) tool('update_goal')],
    prefixStable: true,
  );

  test('implementation metadata overrides apparent completion prose', () {
    for (final response in [
      'Done.',
      '...',
      'Listo.',
      '\u8ffd\u52a0\u3057\u307e\u3059',
    ]) {
      final recovery = plan(response: response);
      expect(recovery.shouldRecover, isTrue);
      expect(recovery.skipFinalAnswer, isFalse);
      expect(recovery.requestTools.single['function'], {'name': 'update_goal'});
      expect(recovery.selection.tools, hasLength(2));
    }
  });
  test('does not widen ordinary completed answers', () {
    expect(plan(implementation: false).shouldRecover, isFalse);
  });
  test('stops for accepted completion, unsafe boundaries, or missing tool', () {
    expect(
      plan(ack: GoalUpdateAckOutcome.completionRecorded).shouldRecover,
      isFalse,
    );
    expect(plan(boundary: false).shouldRecover, isFalse);
    expect(plan(offerStatus: false).shouldRecover, isFalse);
  });
  test('only the offered status tool may execute in the status response', () {
    final recovery = plan();
    ToolCallInfo call(String name) =>
        ToolCallInfo(id: name, name: name, arguments: const {});
    expect(recovery.acceptsCalls([call('update_goal')]), isTrue);
    expect(recovery.acceptsCalls([call('write_file')]), isFalse);
    expect(
      recovery.acceptsCalls([call('update_goal'), call('write_file')]),
      isFalse,
    );
    expect(recovery.acceptsCalls([]), isFalse);
  });
}
