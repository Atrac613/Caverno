import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final goal = ConversationGoal(
    id: 'task',
    objective: 'Implement the task',
    projectTaskAutoReview: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  GoalUpdateAck complete(
    List<ToolResultInfo> results, {
    bool successful = true,
  }) => const GoalUpdateAckResolver().resolve(
    input: const GoalUpdateInput(completed: true),
    goal: goal,
    taskToolResults: results,
    evidence: ToolResultCompletionEvidence(
      hasSuccessfulExecutionVerification: successful,
      hasFailedExecutionVerification: !successful,
    ),
  );
  final change = _result(
    'edit_file',
    const ToolOutcome(
      fileMutations: [
        ToolFileMutation(path: '/workspace/test.py', changed: true),
      ],
    ),
  );
  final verify = _result(
    'local_execute_command',
    const ToolOutcome(exitCode: 0),
  );

  test('accepts a typed change followed by a terminal successful verifier', () {
    expect(complete([change, verify]).completionAccepted, isTrue);
  });
  test(
    'a new structured completion supersedes progress but retains execution gaps',
    () {
      final ack = const GoalUpdateAckResolver().resolve(
        input: const GoalUpdateInput(completed: true),
        goal: goal,
        taskToolResults: [change, verify],
        evidence: const ToolResultCompletionEvidence(
          hasSuccessfulExecutionVerification: true,
          hasReportedRemainingWork: true,
          remainingWorkMessage: 'Run verification.',
        ),
      );
      expect(ack.completionAccepted, isTrue);
    },
  );
  test('rejects a completion without captured changes', () {
    expect(complete([verify]).gaps.join(), contains('file-change evidence'));
  });
  test('rejects a verifier run before the latest change', () {
    expect(complete([verify, change]).completionRejected, isTrue);
  });
  test('rejects changed unknown, unchanged, and prose-only mutations', () {
    for (final outcome in [
      null,
      const ToolOutcome(
        fileMutations: [ToolFileMutation(path: '/workspace/test.py')],
      ),
      const ToolOutcome(
        fileMutations: [
          ToolFileMutation(path: '/workspace/test.py', changed: false),
        ],
      ),
    ]) {
      expect(
        complete([_result('edit_file', outcome), verify]).completionRejected,
        isTrue,
      );
    }
  });
  test('rejects missing, failed, and still-running verification outcomes', () {
    for (final outcome in [
      null,
      const ToolOutcome(exitCode: 1),
      const ToolOutcome(exitCode: 0, testFailedCount: 2),
      const ToolOutcome(exitCode: 0, diagnosticErrorCount: 1),
      const ToolOutcome(exitCode: 0, processState: ToolProcessState.running),
    ]) {
      expect(
        complete([
          change,
          _result('local_execute_command', outcome),
        ]).completionRejected,
        isTrue,
      );
    }
  });
  test('rejects masked failures despite a typed zero exit code', () {
    expect(
      complete([change, verify], successful: false).completionRejected,
      isTrue,
    );
  });
  test(
    'accepts an exited background verifier but not a non-execution tool',
    () {
      expect(
        complete([
          change,
          _result(
            'process_wait',
            const ToolOutcome(
              exitCode: 0,
              processState: ToolProcessState.exited,
            ),
          ),
        ]).completionAccepted,
        isTrue,
      );
      expect(
        complete([
          change,
          _result('read_file', const ToolOutcome(exitCode: 0)),
        ]).completionRejected,
        isTrue,
      );
    },
  );
}

ToolResultInfo _result(String name, ToolOutcome? outcome) => ToolResultInfo(
  id: name,
  name: name,
  arguments: const {},
  result: 'Completed successfully.',
  outcome: outcome,
);
