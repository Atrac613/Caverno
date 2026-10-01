import 'package:caverno/features/chat/application/runtime/pending_edit_budget_extension.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_exhaustion_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

ToolLoopExhaustionDecisionInput _input({
  int iteration = 12,
  bool hasPendingFileMutation = true,
  bool hasPendingWriteGitCommand = false,
  bool hasPendingUserQuestion = false,
}) => ToolLoopExhaustionDecisionInput(
  iteration: iteration,
  maxIterations: 12,
  recoveryAlreadyAttempted: false,
  hasPendingToolCalls: true,
  hasCurrentBatchToolResults: true,
  hasPendingFileMutation: hasPendingFileMutation,
  hasPendingWriteGitCommand: hasPendingWriteGitCommand,
  hasPendingUserQuestion: hasPendingUserQuestion,
);

void main() {
  // Session 78bbf53c: a farm subtask hit the limit with an edit pending, ran
  // it, and had to finalize mid-implementation.
  const extension = PendingEditBudgetExtension();
  final changed = ToolResultInfo(
    id: 'edit-1',
    name: 'edit_file',
    arguments: const {'path': 'watcher.py'},
    result: '{"changed":true}',
    outcome: const ToolOutcome(
      fileMutations: [ToolFileMutation(path: 'watcher.py', changed: true)],
    ),
  );
  final readOnly = ToolResultInfo(
    id: 'read-1',
    name: 'read_file',
    arguments: const {'path': 'watcher.py'},
    result: '{}',
  );

  test('extends a turn that changed files and has an edit pending', () {
    expect(
      extension.applies(_input(), executedToolResults: [readOnly, changed]),
      isTrue,
    );
  });

  test(
    'does not extend without a prior change, a pending edit, or the limit',
    () {
      expect(
        extension.applies(_input(), executedToolResults: [readOnly]),
        isFalse,
      );
      expect(
        extension.applies(
          _input(hasPendingFileMutation: false),
          executedToolResults: [changed],
        ),
        isFalse,
      );
      expect(
        extension.applies(_input(iteration: 5), executedToolResults: [changed]),
        isFalse,
      );
    },
  );

  test('leaves git writes and user questions to finalization', () {
    for (final input in [
      _input(hasPendingWriteGitCommand: true),
      _input(hasPendingUserQuestion: true),
    ]) {
      expect(extension.applies(input, executedToolResults: [changed]), isFalse);
    }
  });
}
