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
    bool step = false,
    String response = 'Done.',
    bool boundary = true,
    GoalUpdateAckOutcome? ack,
    bool offerStatus = true,
  }) => TurnFinalizationRecoveryPlan(
    goal: goal,
    implementationTurn: implementation,
    stepTurn: step,
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
  test(
    'subtask recovery requires its marker and never forces overall completion',
    () {
      final recovery = plan(implementation: false, step: true);
      expect(recovery.structuredTask, isFalse);
      expect(recovery.structuredStep, isTrue);
      expect(recovery.shouldRecover, isTrue);
      expect(recovery.forcedCode, 'structured_project_subtask');
      expect(recovery.requestTools, hasLength(2));
      expect(recovery.prompt, contains('Never mark the overall goal complete'));
      expect(
        recovery.acceptsCalls([
          ToolCallInfo(
            id: 'early',
            name: 'update_goal',
            arguments: const {'completed': true},
          ),
        ]),
        isFalse,
      );
      expect(
        recovery.acceptsCalls([
          ToolCallInfo(
            id: 'blocker',
            name: 'update_goal',
            arguments: const {
              'completed': false,
              'blocked_reason': 'Missing runtime',
            },
          ),
        ]),
        isTrue,
      );
      expect(
        plan(
          implementation: false,
          step: true,
          response: 'Done.\nPROJECT_TASK_SUBTASK_DONE',
        ).shouldRecover,
        isFalse,
      );
      expect(
        plan(implementation: false, step: true, boundary: false).shouldRecover,
        isFalse,
      );
    },
  );
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
