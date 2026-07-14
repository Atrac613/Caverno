import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/verification_cadence_policy.dart';

void main() {
  const projector = ExecutionSnapshotProjector();

  Conversation conversation({
    ConversationWorkflowStage stage = ConversationWorkflowStage.implement,
    ConversationWorkflowSpec workflowSpec = const ConversationWorkflowSpec(),
    List<ConversationExecutionTaskProgress> progress = const [],
    List<ConversationOpenQuestionProgress> questions = const [],
  }) {
    return Conversation(
      id: 'conversation-1',
      title: 'Execution snapshot',
      messages: const <Message>[],
      createdAt: DateTime(2026, 7, 11, 10),
      updatedAt: DateTime(2026, 7, 11, 10, 5),
      workflowStage: stage,
      workflowSpec: workflowSpec,
      executionProgress: progress,
      openQuestionProgress: questions,
    );
  }

  test('projects idle state when no workflow exists', () {
    final snapshot = projector.project(null);

    expect(snapshot.action, ExecutionSnapshotAction.idle);
    expect(snapshot.hasContract, isFalse);
    expect(snapshot.remainingTaskCount, 0);
  });

  test('projects the current task without changing the contract hash', () {
    const workflow = ConversationWorkflowSpec(
      goal: 'Ship the CLI',
      constraints: ['Keep the command backwards compatible.'],
      acceptanceCriteria: ['The smoke test passes.'],
      tasks: [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the command',
          targetFiles: ['bin/main.dart'],
          validationCommand: 'dart test',
        ),
      ],
    );
    final pending = projector.project(conversation(workflowSpec: workflow));
    final running = projector.project(
      conversation(
        workflowSpec: workflow,
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: ConversationWorkflowTaskStatus.inProgress,
          ),
        ],
      ),
    );

    expect(pending.contractHash, isNotEmpty);
    expect(running.contractHash, pending.contractHash);
    expect(running.activeTaskId, 'task-1');
    expect(running.action, ExecutionSnapshotAction.execute);
  });

  test('contract hash ignores task execution status', () {
    const pendingWorkflow = ConversationWorkflowSpec(
      goal: 'Ship the CLI',
      tasks: [
        ConversationWorkflowTask(id: 'task-1', title: 'Implement the command'),
      ],
    );
    const runningWorkflow = ConversationWorkflowSpec(
      goal: 'Ship the CLI',
      tasks: [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the command',
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    );

    final pending = projector.project(
      conversation(workflowSpec: pendingWorkflow),
    );
    final running = projector.project(
      conversation(workflowSpec: runningWorkflow),
    );

    expect(running.contractHash, pending.contractHash);
  });

  test('projects clarification before autonomous execution', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [ConversationWorkflowTask(id: 'task-1', title: 'Implement')],
        ),
        questions: const [
          ConversationOpenQuestionProgress(
            questionId: 'question-1',
            question: 'Which API version is required?',
            status: ConversationOpenQuestionStatus.needsUserInput,
          ),
        ],
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.clarify);
    expect(snapshot.unresolvedQuestionCount, 1);
    expect(snapshot.hasBlockingAssumptions, isFalse);
    expect(snapshot.toPromptContext(), contains('Open questions:'));
  });

  test('injects sourced contract state and blocks material assumptions', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Ship the CLI',
          constraints: ['Support the selected runtime.'],
          acceptanceCriteria: ['The smoke test passes.'],
          sources: [
            ConversationContractSourceReference(
              id: 'user-message:1',
              kind: ConversationContractSourceKind.userMessage,
              locator: 'message-1',
            ),
          ],
          provenance: [
            ConversationContractItemProvenance(
              itemId: 'goal',
              kind: ConversationContractItemKind.goal,
              sourceIds: ['user-message:1'],
            ),
            ConversationContractItemProvenance(
              itemId: 'constraint:runtime',
              kind: ConversationContractItemKind.constraint,
              assumption: true,
              material: true,
              clarificationQuestion: 'Which runtime must be supported?',
            ),
          ],
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Implement the command',
              validationCommand: 'dart test',
            ),
          ],
        ),
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.clarify);
    expect(snapshot.hasBlockingAssumptions, isTrue);
    expect(snapshot.sourceCount, 1);
    expect(snapshot.sourcedItemCount, 1);
    expect(snapshot.toPromptContext(), contains('Objective: Ship the CLI'));
    expect(
      snapshot.toPromptContext(),
      contains('Do not mutate state until the user confirms'),
    );
  });

  test('keeps both leading and trailing contract requirements in prompts', () {
    const snapshot = ExecutionSnapshot(
      contractHash: 'contract',
      workflowStage: ConversationWorkflowStage.implement,
      action: ExecutionSnapshotAction.execute,
      activeTaskId: null,
      activeTaskStatus: null,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      completedTaskCount: 0,
      remainingTaskCount: 1,
      unresolvedQuestionCount: 0,
      requiresValidation: false,
      latestDiagnostic: null,
      constraints: [
        'In scope: create tasks.',
        'In scope: list tasks.',
        'In scope: complete tasks.',
        'In scope: delete tasks.',
        'Out of scope: due dates.',
        'Out of scope: priorities.',
        'Out of scope: web servers.',
      ],
      acceptanceCriteria: [
        'Criterion 1',
        'Criterion 2',
        'Criterion 3',
        'Criterion 4',
        'Criterion 5',
        'Criterion 6',
        'No feature outside the scope was added.',
      ],
    );

    final prompt = snapshot.toPromptContext();

    expect(prompt, contains('In scope: create tasks.'));
    expect(prompt, contains('Out of scope: web servers.'));
    expect(prompt, contains('No feature outside the scope was added.'));
    expect(prompt, isNot(contains('In scope: complete tasks.')));
  });

  test('overlays repeated command diagnostics as a repair focus', () {
    const snapshot = ExecutionSnapshot(
      contractHash: 'contract',
      workflowStage: ConversationWorkflowStage.implement,
      action: ExecutionSnapshotAction.execute,
      activeTaskId: 'task-1',
      activeTaskStatus: ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      completedTaskCount: 0,
      remainingTaskCount: 1,
      unresolvedQuestionCount: 0,
      requiresValidation: true,
      latestDiagnostic: null,
    );

    final focused = snapshot.withCommandDiagnosticRepairFocus(
      diagnosticSummary:
          'bin/todo_cli.dart: [todo_cli_missing] Required file is missing.',
      streak: 2,
      hasPathBackedDiagnostic: true,
    );
    final prompt = focused.toPromptContext();

    expect(focused.action, ExecutionSnapshotAction.repair);
    expect(
      focused.validationStatus,
      ConversationExecutionValidationStatus.failed,
    );
    expect(prompt, contains('Required next action: repair'));
    expect(prompt, contains('Repeated command diagnostic streak: 2'));
    expect(prompt, contains('make one concrete file mutation'));
    expect(prompt, contains('Do not rerun unchanged validation again.'));
  });

  test('allows inspection but prevents an unchanged streak-one replay', () {
    const snapshot = ExecutionSnapshot(
      contractHash: 'contract',
      workflowStage: ConversationWorkflowStage.implement,
      action: ExecutionSnapshotAction.execute,
      activeTaskId: 'task-1',
      activeTaskStatus: ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      completedTaskCount: 0,
      remainingTaskCount: 1,
      unresolvedQuestionCount: 0,
      requiresValidation: true,
      latestDiagnostic: null,
    );

    final focused = snapshot.withCommandDiagnosticRepairFocus(
      diagnosticSummary:
          'bin/todo_cli.dart: [todo_cli_missing] Required file is missing.',
      streak: 1,
      hasPathBackedDiagnostic: true,
    );
    final prompt = focused.toPromptContext();

    expect(prompt, contains('Required next action: repair'));
    expect(prompt, contains('Command diagnostic streak: 1'));
    expect(prompt, contains('inspect the diagnostic context only as needed'));
    expect(prompt, contains('make one concrete file mutation'));
    expect(
      prompt,
      contains('Do not rerun unchanged validation before corrective action.'),
    );
  });

  test('uses corrective-action wording for a pathless diagnostic', () {
    const snapshot = ExecutionSnapshot(
      contractHash: 'contract',
      workflowStage: ConversationWorkflowStage.implement,
      action: ExecutionSnapshotAction.execute,
      activeTaskId: 'task-1',
      activeTaskStatus: ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      completedTaskCount: 0,
      remainingTaskCount: 1,
      unresolvedQuestionCount: 0,
      requiresValidation: true,
      latestDiagnostic: null,
    );

    final focused = snapshot.withCommandDiagnosticRepairFocus(
      diagnosticSummary:
          '[dependency_resolution_failed] Resolve the dependency constraint.',
      streak: 1,
      hasPathBackedDiagnostic: false,
    );
    final prompt = focused.toPromptContext();

    expect(prompt, contains('take one concrete corrective action'));
    expect(prompt, isNot(contains('file mutation')));
  });

  test('preserves clarification over a repeated diagnostic repair focus', () {
    const snapshot = ExecutionSnapshot(
      contractHash: 'contract',
      workflowStage: ConversationWorkflowStage.implement,
      action: ExecutionSnapshotAction.clarify,
      activeTaskId: 'task-1',
      activeTaskStatus: ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      completedTaskCount: 0,
      remainingTaskCount: 1,
      unresolvedQuestionCount: 1,
      requiresValidation: true,
      latestDiagnostic: null,
      clarificationQuestions: ['Which runtime is required?'],
    );

    final focused = snapshot.withCommandDiagnosticRepairFocus(
      diagnosticSummary: 'lib/main.dart: [compile_error] Build failed.',
      streak: 3,
      hasPathBackedDiagnostic: true,
    );

    expect(focused.action, ExecutionSnapshotAction.clarify);
    expect(
      focused.toPromptContext(),
      isNot(contains('make one concrete file mutation')),
    );
  });

  test('projects repair with the latest failed validation diagnostic', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Implement',
              validationCommand: 'dart test',
            ),
          ],
        ),
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: ConversationWorkflowTaskStatus.inProgress,
            validationStatus: ConversationExecutionValidationStatus.failed,
            lastValidationSummary: 'One test failed.',
          ),
        ],
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.repair);
    expect(
      snapshot.validationStatus,
      ConversationExecutionValidationStatus.failed,
    );
    expect(snapshot.latestDiagnostic, 'One test failed.');
    expect(
      snapshot.toRedactedLogSummary(),
      isNot(contains('One test failed.')),
    );
    expect(snapshot.toRedactedLogSummary(), isNot(contains('task-1')));
    expect(snapshot.toRedactedLogSummary(), contains('hasDiagnostic=true'));
  });

  test('projects verification after an in-progress task has run', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Implement',
              validationCommand: 'dart test',
            ),
          ],
        ),
        progress: [
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: ConversationWorkflowTaskStatus.inProgress,
            lastRunAt: DateTime(2026, 7, 11, 10, 3),
          ),
        ],
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.verify);
    expect(snapshot.requiresValidation, isTrue);
  });

  test('projects completion when all saved tasks are complete', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(id: 'task-1', title: 'Implement'),
            ConversationWorkflowTask(id: 'task-2', title: 'Verify'),
          ],
        ),
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          ConversationExecutionTaskProgress(
            taskId: 'task-2',
            status: ConversationWorkflowTaskStatus.completed,
          ),
        ],
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.complete);
    expect(snapshot.completedTaskCount, 2);
    expect(snapshot.remainingTaskCount, 0);
  });

  test('returns to verification after a post-success mutation', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Implement',
              status: ConversationWorkflowTaskStatus.completed,
              validationCommand: 'dart test',
            ),
          ],
        ),
      ).copyWith(mutationGeneration: 2, verificationGeneration: 1),
    );

    expect(snapshot.verificationCadence, VerificationCadence.required);
    expect(snapshot.action, ExecutionSnapshotAction.verify);
    expect(snapshot.toPromptContext(), contains('Mutation generation: 2'));
  });

  test('does not label a successful validation summary as a diagnostic', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Implement',
              validationCommand: 'dart test',
            ),
          ],
        ),
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: ConversationWorkflowTaskStatus.inProgress,
            validationStatus: ConversationExecutionValidationStatus.passed,
            lastValidationSummary: 'All tests passed.',
          ),
        ],
      ),
    );

    expect(snapshot.latestDiagnostic, isNull);
    expect(snapshot.toRedactedLogSummary(), contains('hasDiagnostic=false'));
  });
}
