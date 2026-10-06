import 'package:caverno/features/chat/application/runtime/productive_turn_budget_extension.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_exhaustion_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

ToolLoopExhaustionDecisionInput _input({
  int iteration = 16,
  bool recoveryAlreadyAttempted = true,
  bool hasPendingFileMutation = false,
  bool hasPendingWriteGitCommand = false,
  bool hasPendingUserQuestion = false,
}) => ToolLoopExhaustionDecisionInput(
  iteration: iteration,
  maxIterations: 16,
  recoveryAlreadyAttempted: recoveryAlreadyAttempted,
  hasPendingToolCalls: true,
  hasCurrentBatchToolResults: true,
  hasPendingFileMutation: hasPendingFileMutation,
  hasPendingWriteGitCommand: hasPendingWriteGitCommand,
  hasPendingUserQuestion: hasPendingUserQuestion,
);

void main() {
  const extension = ProductiveTurnBudgetExtension();
  final changed = ToolResultInfo(
    id: 'edit-1',
    name: 'edit_file',
    arguments: const {'path': 'state.py'},
    result: '{"changed":true}',
    outcome: const ToolOutcome(
      fileMutations: [ToolFileMutation(path: 'state.py', changed: true)],
    ),
  );
  final readOnly = ToolResultInfo(
    id: 'read-1',
    name: 'read_file',
    arguments: const {'path': 'state.py'},
    result: '{}',
  );

  test('extends a turn that changed files with an edit pending', () {
    // Session 78bbf53c.
    expect(
      extension.applies(
        _input(hasPendingFileMutation: true, recoveryAlreadyAttempted: false),
        executedToolResults: [readOnly, changed],
      ),
      isTrue,
    );
  });

  test('extends after recovery is spent with a read pending', () {
    // Session 02fec5c8: 16/16 with read_file pending right after an edit, so
    // the verification the completion gate requires never ran.
    expect(
      extension.applies(_input(), executedToolResults: [changed, readOnly]),
      isTrue,
    );
  });

  test('leaves the turn to the one-time recovery when it will run', () {
    expect(
      extension.applies(
        _input(recoveryAlreadyAttempted: false),
        executedToolResults: [changed],
      ),
      isFalse,
    );
  });

  test('needs a changed file, the limit, and no git write or question', () {
    expect(
      extension.applies(_input(), executedToolResults: [readOnly]),
      isFalse,
    );
    expect(
      extension.applies(_input(iteration: 5), executedToolResults: [changed]),
      isFalse,
    );
    for (final input in [
      _input(hasPendingWriteGitCommand: true),
      _input(hasPendingUserQuestion: true),
    ]) {
      expect(extension.applies(input, executedToolResults: [changed]), isFalse);
    }
  });
}
