import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/stalled_diagnostic_repair_contract.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = StalledDiagnosticRepairContract();
  const evidence = ToolResultCompletionEvidence(
    unresolvedErrorCount: 2,
    unresolvedErrorPaths: ['lib/main.dart'],
    unresolvedErrorDiagnostics: [
      UnresolvedErrorDiagnostic(
        path: 'lib/main.dart',
        code: 'undefined_identifier',
        message: 'Undefined name store.',
      ),
    ],
  );
  const snapshot = ExecutionSnapshot(
    contractHash: 'contract',
    workflowStage: ConversationWorkflowStage.implement,
    action: ExecutionSnapshotAction.repair,
    activeTaskId: 'task-1',
    activeTaskStatus: ConversationWorkflowTaskStatus.inProgress,
    validationStatus: ConversationExecutionValidationStatus.failed,
    completedTaskCount: 0,
    remainingTaskCount: 1,
    unresolvedQuestionCount: 0,
    requiresValidation: true,
    latestDiagnostic: 'Undefined name store at lib/main.dart:12',
    activeTaskTargetFiles: ['lib/main.dart'],
    acceptanceCriteria: ['The command exits successfully.'],
  );

  test('does not build a contract for the first diagnostic result', () {
    expect(
      builder.build(
        evidence: evidence,
        executionSnapshot: snapshot,
        noProgressStreak: 0,
      ),
      isNull,
    );
  });

  test('builds a compact sourced contract after a diagnostic plateau', () {
    final contract = builder.build(
      evidence: evidence,
      executionSnapshot: snapshot,
      noProgressStreak: 1,
    );

    expect(contract, contains('<repair_contract>'));
    expect(contract, contains('lib/main.dart'));
    expect(contract, contains('Undefined name store'));
    expect(contract, contains('[undefined_identifier] Undefined name store.'));
    expect(contract, contains('The command exits successfully.'));
    expect(contract, contains('harness will re-run the recorded verifier'));
    expect(contract, contains('write_file when a required file is missing'));
    expect(contract, contains('edit_file when an existing file is faulty'));
    expect(contract, contains('delete_file'));
  });

  test('preserves missing-file diagnostics as actionable repair guidance', () {
    const missingEvidence = ToolResultCompletionEvidence(
      unresolvedErrorCount: 1,
      unresolvedErrorPaths: ['bin/todo_cli.dart'],
      unresolvedErrorDiagnostics: [
        UnresolvedErrorDiagnostic(
          path: 'bin/todo_cli.dart',
          code: 'todo_cli_missing',
          message: 'bin/todo_cli.dart does not exist.',
        ),
      ],
    );

    final contract = builder.build(
      evidence: missingEvidence,
      executionSnapshot: snapshot,
      noProgressStreak: 1,
    );

    expect(
      contract,
      contains(
        'bin/todo_cli.dart: [todo_cli_missing] '
        'bin/todo_cli.dart does not exist.',
      ),
    );
    expect(contract, isNot(contains('then edit it')));
  });

  test('increments only for an identical non-empty signature', () {
    expect(
      builder.nextSignatureStreak(
        previousSignature: 'same',
        currentSignature: 'same',
        currentStreak: 1,
      ),
      2,
    );
    expect(
      builder.nextSignatureStreak(
        previousSignature: 'old',
        currentSignature: 'changed',
        currentStreak: 2,
      ),
      0,
    );
    expect(
      builder.nextSignatureStreak(
        previousSignature: '',
        currentSignature: '',
        currentStreak: 2,
      ),
      0,
    );
  });
}
