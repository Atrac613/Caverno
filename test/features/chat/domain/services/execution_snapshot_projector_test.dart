import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/verification_cadence_policy.dart';

void main() {
  const projector = ExecutionSnapshotProjector();

  Conversation conversation({
    ConversationWorkflowStage stage = ConversationWorkflowStage.implement,
    ConversationWorkflowSpec workflowSpec = const ConversationWorkflowSpec(),
    List<ConversationExecutionTaskProgress> progress = const [],
    List<ConversationOpenQuestionProgress> questions = const [],
    int mutationGeneration = 0,
    int verificationGeneration = -1,
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
      mutationGeneration: mutationGeneration,
      verificationGeneration: verificationGeneration,
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

  test('a ready task is offered for delegation, with its runner', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Add full-text search',
          tasks: [
            ConversationWorkflowTask(
              id: 'choose-index',
              title: 'Choose the index format',
            ),
            ConversationWorkflowTask(
              id: 'build-ui',
              title: 'Build the query UI',
              targetFiles: ['lib/search/query_view.dart'],
            ),
          ],
        ),
      ),
    );

    expect(snapshot.delegatableTasks, [
      'Choose the index format (subagent)',
      'Build the query UI (worktree)',
    ]);
    expect(
      snapshot.toPromptContext(),
      isNot(contains('Choose the index format (subagent)')),
      reason:
          'The delegation queue belongs to the Anabasis parent. An ordinary '
          'turn would read it as a suggestion to spawn children.',
    );
  });

  test('an unready task tells the model what it waits on', () {
    const assumed = 'The index format is chosen';
    const provenanceService = ConversationContractProvenanceService();
    final assumedId = provenanceService.itemId(
      kind: ConversationContractItemKind.constraint,
      value: assumed,
    );
    final snapshot = projector.project(
      conversation(
        workflowSpec: ConversationWorkflowSpec(
          goal: 'Add full-text search',
          constraints: const [assumed],
          tasks: [
            const ConversationWorkflowTask(
              id: 'choose-index',
              title: 'Choose the index format',
            ),
            ConversationWorkflowTask(
              id: 'build-ui',
              title: 'Build the query UI',
              preconditions: [
                const ConversationTaskPrecondition(
                  kind: ConversationTaskPreconditionKind.task,
                  ref: 'choose-index',
                ),
                ConversationTaskPrecondition(
                  kind: ConversationTaskPreconditionKind.assumption,
                  ref: assumedId,
                ),
              ],
            ),
          ],
          provenance: [
            ConversationContractItemProvenance(
              itemId: assumedId,
              kind: ConversationContractItemKind.constraint,
              assumption: true,
              material: true,
            ),
          ],
        ),
      ),
    );

    expect(snapshot.waitingTasks, hasLength(1));
    final prompt = snapshot.toPromptContext();
    expect(prompt, contains('Tasks not ready: Build the query UI'));
    expect(
      prompt,
      contains('assumption: $assumed'),
      reason:
          'An item id is a hash; a prompt line naming one tells the model '
          'nothing it can act on.',
    );
    expect(
      prompt,
      contains('task: choose-index'),
      reason:
          'A task edge names a task id, which the plan also lists, so it '
          'resolves for the reader as written.',
    );
    expect(
      snapshot.waitingTasks.single,
      isNot(contains('Choose the index format —')),
      reason: 'A task with nothing holding it is not waiting on anything.',
    );
  });

  test('the assumption line names the claim, not a sample of questions', () {
    // The defect this pins: blocking-assumption questions used to be unioned
    // into the open-question list, and the prompt rendered *that* list under
    // "material assumptions requiring user confirmation", sampled to three.
    // With three open questions the sample could contain no assumption at all
    // while claiming to list them.
    const assumed = 'The store is single-writer.';
    const provenanceService = ConversationContractProvenanceService();
    final snapshot = projector.project(
      conversation(
        workflowSpec: ConversationWorkflowSpec(
          goal: 'Ship the CLI',
          constraints: const [assumed],
          provenance: [
            ConversationContractItemProvenance(
              itemId: provenanceService.itemId(
                kind: ConversationContractItemKind.constraint,
                value: assumed,
              ),
              kind: ConversationContractItemKind.constraint,
              assumption: true,
              material: true,
              clarificationQuestion: 'Is the store single-writer?',
            ),
          ],
          tasks: const [
            ConversationWorkflowTask(id: 'task-1', title: 'Implement it'),
          ],
        ),
        questions: const [
          ConversationOpenQuestionProgress(
            questionId: 'question-1',
            question: 'Which shell should the installer target?',
            status: ConversationOpenQuestionStatus.needsUserInput,
          ),
        ],
      ),
    );

    expect(
      snapshot.blockingAssumptions,
      [assumed],
      reason:
          'The plan asserted this; the prompt should say what is assumed '
          'rather than the question about it.',
    );
    final prompt = snapshot.toPromptContext();
    expect(prompt, contains('Unconfirmed material assumptions: $assumed'));
    expect(
      prompt,
      contains('Open questions: '),
      reason:
          'A blocked contract still has open questions, and the old '
          'else-branch hid them the moment an assumption blocked.',
    );
    expect(
      prompt,
      isNot(contains('Unconfirmed material assumptions: Which shell')),
    );
    expect(
      prompt,
      isNot(contains('Ask one focused clarification question')),
      reason:
          'Caverno asks at the refusal site now (ANA0 PR 4b-2); telling '
          'the model to ask is the humility instruction this track replaces.',
    );
  });

  test('projects planning before execution for a sourced draft contract', () {
    final snapshot = projector.project(
      conversation(
        stage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Plan the CLI',
          tasks: [
            ConversationWorkflowTask(id: 'task-1', title: 'Build the CLI'),
          ],
        ),
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.plan);
    expect(snapshot.toPromptContext(), contains('Required next action: plan'));
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
      contains('State mutation is blocked until the user confirms'),
    );
    expect(
      snapshot.blockingAssumptions,
      ['Which runtime must be supported?'],
      reason:
          'This item carries a hand-written id that matches no constraint, so '
          'the claim cannot be resolved and the question stands in for it. '
          'Dropping it would hide the assumption that is blocking the turn.',
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

  test('snapshot aggregates use progress-owned task status', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'legacy-completed',
              title: 'Legacy completed task',
              status: ConversationWorkflowTaskStatus.completed,
            ),
            ConversationWorkflowTask(
              id: 'progress-completed',
              title: 'Progress completed task',
            ),
            ConversationWorkflowTask(
              id: 'progress-pending',
              title: 'Progress pending task',
              status: ConversationWorkflowTaskStatus.completed,
            ),
          ],
        ),
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'progress-completed',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          ConversationExecutionTaskProgress(
            taskId: 'progress-pending',
            status: ConversationWorkflowTaskStatus.pending,
          ),
        ],
      ),
    );

    expect(snapshot.action, ExecutionSnapshotAction.execute);
    expect(snapshot.activeTaskId, 'legacy-completed');
    expect(snapshot.activeTaskStatus, ConversationWorkflowTaskStatus.pending);
    expect(snapshot.completedTaskCount, 1);
    expect(snapshot.remainingTaskCount, 2);
    expect(snapshot.remainingTaskIds, ['legacy-completed', 'progress-pending']);
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

  test('the prompt reports saved-task progress from execution progress', () {
    const workflow = ConversationWorkflowSpec(
      goal: 'Ship the game',
      tasks: [
        ConversationWorkflowTask(id: 'task-1', title: 'Build the scene'),
        ConversationWorkflowTask(id: 'task-2', title: 'Build the cave'),
      ],
    );
    final snapshot = projector.project(
      conversation(
        workflowSpec: workflow,
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: ConversationWorkflowTaskStatus.completed,
          ),
        ],
      ),
    );

    // The authored task status stays `pending`, so without this line the
    // prompt's only progress signal is a saved-task list that never advances.
    expect(
      snapshot.toPromptContext(),
      contains('Saved task progress: 1 of 2 completed'),
    );
    expect(snapshot.toPromptContext(), isNot(contains('Every saved task')));
  });

  test('the prompt calls out a fully completed task list', () {
    const workflow = ConversationWorkflowSpec(
      goal: 'Ship the game',
      tasks: [
        ConversationWorkflowTask(id: 'task-1', title: 'Build the scene'),
        ConversationWorkflowTask(id: 'task-2', title: 'Build the cave'),
      ],
    );
    final snapshot = projector.project(
      conversation(
        workflowSpec: workflow,
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

    final prompt = snapshot.toPromptContext();
    expect(prompt, contains('Saved task progress: 2 of 2 completed'));
    expect(prompt, contains('Every saved task is complete.'));
  });

  test('a conversation with no saved tasks reports no progress line', () {
    final snapshot = projector.project(
      conversation(
        workflowSpec: const ConversationWorkflowSpec(goal: 'Ship the game'),
      ),
    );

    expect(snapshot.toPromptContext(), isNot(contains('Saved task progress:')));
  });
  group('verification cadence reproduction (session cfaa8297)', () {
    // Production showed mutation generation 5, verification generation -1 and
    // cadence `required` in the prompt, one second before goal auto-continue
    // skipped on "no incomplete evidence" — meaning the policy received some
    // other cadence. These pin down whether the projector is the culprit.
    test('reports required for the exact production counters', () {
      final snapshot = projector.project(
        conversation(mutationGeneration: 5, verificationGeneration: -1),
      );

      expect(snapshot.verificationCadence, VerificationCadence.required);
    });

    test('the shared derivation ignores the workflow-context gate', () {
      // The fix: callers needing only the cadence use verificationCadenceFor,
      // which computes from the generations regardless of whether a plan
      // exists, so "not computed" can no longer masquerade as "not due".
      final idle = conversation(
        stage: ConversationWorkflowStage.idle,
        mutationGeneration: 5,
        verificationGeneration: -1,
      );

      expect(
        ExecutionSnapshotProjector.verificationCadenceFor(idle),
        VerificationCadence.required,
      );
      // …while the snapshot itself still reports the empty default.
      expect(
        projector.project(idle).verificationCadence,
        VerificationCadence.notDue,
      );
    });

    test('an idle conversation with no spec silently reports notDue', () {
      // The early return skips the cadence computation entirely and falls back
      // to the ExecutionSnapshot default. For the prompt that is harmless (the
      // whole snapshot is empty), but a caller reading only `verificationCadence`
      // cannot tell "not due" from "not computed".
      final snapshot = projector.project(
        conversation(
          stage: ConversationWorkflowStage.idle,
          mutationGeneration: 5,
          verificationGeneration: -1,
        ),
      );

      expect(snapshot.hasContract, isFalse);
      expect(snapshot.verificationCadence, VerificationCadence.notDue);
    });
  });
}
