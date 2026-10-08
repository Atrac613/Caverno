import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/turn_finalization_recovery_plan.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
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
    bool terminalStatusOnly = false,
    bool offerExecution = false,
    bool repair = false,
    List<ToolResultInfo> results = const [],
  }) => TurnFinalizationRecoveryPlan(
    goal: goal,
    implementationTurn: implementation,
    terminalStatusOnly: terminalStatusOnly,
    allowVerificationRepair: repair,
    stepTurn: step,
    boundarySafe: boundary,
    acknowledgement: ack,
    parentTurn: false,
    response: response,
    completedResults: results,
    hasSavedValidation: false,
    hasGitLifecycle: false,
    skipCompletedAnswer: true,
    allTools: [
      tool('write_file'),
      if (repair) ...[
        tool('read_file'),
        tool('edit_file'),
        tool('git_execute_command'),
        tool('send_email'),
      ],
      if (offerStatus) tool('update_goal'),
      if (offerExecution) ...[tool('local_execute_command'), tool('run_tests')],
    ],
    prefixStable: true,
  );

  test('repair exposes project tools while preserving terminal boundaries', () {
    final results = [
      ToolResultInfo(
        id: 'failed',
        name: 'local_execute_command',
        arguments: const {'command': 'python watcher.py --dry-run'},
        result: '{"stdout":"HTTP Error 404: Not Found"}',
        outcome: const ToolOutcome(exitCode: 1),
      ),
    ];
    final recovery = plan(repair: true, results: results, offerExecution: true);
    expect(recovery.shouldRecover, isTrue);
    expect(recovery.verificationRepair, isTrue);
    expect(recovery.forcedCode, 'project_verification_repair');
    final names = recovery.requestTools.map(
      (tool) => (tool['function'] as Map)['name'],
    );
    expect(
      names,
      containsAll(['read_file', 'write_file', 'local_execute_command']),
    );
    expect(names, isNot(contains('git_execute_command')));
    expect(names, isNot(contains('send_email')));
    expect(names, isNot(contains('update_goal')));
    expect(
      recovery.acceptsCalls([
        ToolCallInfo(
          id: 'edit',
          name: 'write_file',
          arguments: const {'path': 'client.py'},
        ),
      ]),
      isTrue,
    );
    expect(
      recovery.acceptsCalls([
        ToolCallInfo(id: 'external', name: 'send_email', arguments: const {}),
      ]),
      isFalse,
    );
    expect(
      recovery.acceptsCalls([
        ToolCallInfo(
          id: 'premature-completion',
          name: 'update_goal',
          arguments: const {'completed': true},
        ),
      ]),
      isFalse,
    );
    expect(plan(repair: true).verificationRepair, isFalse);
    for (final arguments in [
      {'completed': false, 'blocked_reason': 'The sandbox has no network.'},
      {'completed': false, 'message': 'Further work remains.'},
    ]) {
      expect(
        recovery.acceptsCalls([
          ToolCallInfo(
            id: 'premature-status',
            name: 'update_goal',
            arguments: arguments,
          ),
        ]),
        isFalse,
      );
    }
    for (final ack in [
      GoalUpdateAckOutcome.blockerLogged,
      GoalUpdateAckOutcome.completionRecorded,
    ]) {
      expect(
        plan(repair: true, results: results, ack: ack).shouldRecover,
        isFalse,
      );
    }
    expect(
      plan(repair: true, results: results, boundary: false).shouldRecover,
      isFalse,
    );
    final status = plan(
      repair: true,
      results: results,
      terminalStatusOnly: true,
      offerExecution: true,
    );
    expect(status.verificationRepair, isFalse);
    expect(status.requestTools.single['function'], {'name': 'update_goal'});
    final step = plan(
      implementation: false,
      step: true,
      repair: true,
      results: results,
    );
    expect(step.verificationRepair, isTrue);
    expect(
      step.acceptsCalls([
        ToolCallInfo(
          id: 'completion',
          name: 'update_goal',
          arguments: const {'completed': true},
        ),
      ]),
      isFalse,
    );
  });

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
  test('a terminal verification status request offers only update_goal', () {
    final recovery = plan(terminalStatusOnly: true, offerExecution: true);
    expect(recovery.shouldRecover, isTrue);
    expect(recovery.requestTools.single['function'], {'name': 'update_goal'});
    expect(recovery.prompt, contains('Report its captured outcome now'));
    expect(
      recovery.acceptsCalls([
        ToolCallInfo(
          id: 'repeat',
          name: 'local_execute_command',
          arguments: const {'command': 'python watcher.py --dry-run'},
        ),
      ]),
      isFalse,
    );
    expect(
      plan(terminalStatusOnly: true, boundary: false).shouldRecover,
      isFalse,
    );
    expect(
      plan(
        terminalStatusOnly: true,
        ack: GoalUpdateAckOutcome.blockerLogged,
      ).shouldRecover,
      isFalse,
    );
    expect(
      plan(terminalStatusOnly: true, offerStatus: false).shouldRecover,
      isFalse,
    );
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
