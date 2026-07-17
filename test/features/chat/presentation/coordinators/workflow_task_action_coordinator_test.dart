import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/coordinators/workflow_task_action_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

final _fixedNow = DateTime(2026, 7, 17, 15);

const _task = ConversationWorkflowTask(
  id: 'task-1',
  title: 'Build the feature',
  status: ConversationWorkflowTaskStatus.pending,
);

final class _WorkflowWrite {
  const _WorkflowWrite({
    required this.stage,
    required this.spec,
    required this.clearSpec,
    required this.preserveProjection,
  });

  final ConversationWorkflowStage? stage;
  final ConversationWorkflowSpec? spec;
  final bool clearSpec;
  final bool preserveProjection;
}

final class _ProgressWrite {
  const _ProgressWrite({
    required this.taskId,
    required this.status,
    required this.summary,
    required this.blockedReason,
    required this.eventType,
    required this.lastValidationCommand,
  });

  final String taskId;
  final ConversationWorkflowTaskStatus status;
  final String? summary;
  final String? blockedReason;
  final ConversationExecutionTaskEventType? eventType;
  final String? lastValidationCommand;
}

class _TaskActionConversationsNotifier extends ConversationsNotifier {
  _TaskActionConversationsNotifier(
    this.conversation, {
    this.throwOnWorkflowWrite = false,
  });

  final Conversation conversation;
  final bool throwOnWorkflowWrite;
  final List<String> operations = [];
  final List<_WorkflowWrite> workflowWrites = [];
  final List<_ProgressWrite> progressWrites = [];

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

  @override
  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    String? workflowSourceHash,
    DateTime? workflowDerivedAt,
    bool clearWorkflowSpec = false,
    bool preserveWorkflowProjection = false,
  }) async {
    operations.add('workflow');
    if (throwOnWorkflowWrite) {
      throw StateError('workflow persistence failed');
    }
    workflowWrites.add(
      _WorkflowWrite(
        stage: workflowStage,
        spec: workflowSpec,
        clearSpec: clearWorkflowSpec,
        preserveProjection: preserveWorkflowProjection,
      ),
    );
    final current = state.currentConversation!;
    _replaceCurrent(
      current.copyWith(
        workflowStage: workflowStage ?? current.workflowStage,
        workflowSpec: clearWorkflowSpec
            ? null
            : workflowSpec ?? current.workflowSpec,
      ),
    );
  }

  @override
  Future<void> updateCurrentExecutionTaskProgress({
    required String taskId,
    required ConversationWorkflowTaskStatus status,
    bool allowStatusRegression = false,
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? summary,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
    String? eventSummary,
    DateTime? eventTimestamp,
  }) async {
    operations.add('progress');
    progressWrites.add(
      _ProgressWrite(
        taskId: taskId,
        status: status,
        summary: summary,
        blockedReason: blockedReason,
        eventType: eventType,
        lastValidationCommand: lastValidationCommand,
      ),
    );
  }

  void replaceCurrent(Conversation nextConversation) {
    _replaceCurrent(nextConversation);
  }

  void _replaceCurrent(Conversation nextConversation) {
    state = state.copyWith(
      conversations: [nextConversation],
      currentConversationId: nextConversation.id,
    );
  }
}

final class _Harness {
  _Harness({required this.container, required this.notifier}) {
    coordinator = WorkflowTaskActionCoordinator(
      conversationsNotifier: notifier,
      readCurrentConversation: () =>
          container.read(conversationsNotifierProvider).currentConversation,
      createTaskId: () => 'generated-task',
      dismissTaskProposal: () {
        dismissCount += 1;
        notifier.operations.add('dismiss');
      },
    );
  }

  final ProviderContainer container;
  final _TaskActionConversationsNotifier notifier;
  late final WorkflowTaskActionCoordinator coordinator;
  var dismissCount = 0;

  Conversation get conversation =>
      container.read(conversationsNotifierProvider).currentConversation!;

  void dispose() => container.dispose();
}

Conversation _conversation({
  String goal = 'Current goal',
  List<ConversationWorkflowTask> tasks = const [_task],
  bool usePlanDocument = false,
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Task actions',
    messages: const [],
    createdAt: _fixedNow,
    updatedAt: _fixedNow,
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    workflowStage: ConversationWorkflowStage.tasks,
    workflowSpec: ConversationWorkflowSpec(goal: goal, tasks: tasks),
    planArtifact: usePlanDocument
        ? const ConversationPlanArtifact(approvedMarkdown: '# Approved plan')
        : null,
  );
}

_Harness _buildHarness({
  Conversation? conversation,
  bool throwOnWorkflowWrite = false,
}) {
  final notifier = _TaskActionConversationsNotifier(
    conversation ?? _conversation(),
    throwOnWorkflowWrite: throwOnWorkflowWrite,
  );
  final container = ProviderContainer(
    overrides: [conversationsNotifierProvider.overrideWith(() => notifier)],
  );
  container.read(conversationsNotifierProvider);
  return _Harness(container: container, notifier: notifier);
}

void main() {
  test(
    'task proposal uses latest metadata and dismisses after persistence',
    () async {
      final harness = _buildHarness();
      addTearDown(harness.dispose);
      final callerSnapshot = harness.conversation;
      harness.notifier.replaceCurrent(
        harness.conversation.copyWith(
          workflowSpec: harness.conversation.effectiveWorkflowSpec.copyWith(
            goal: 'Latest goal',
          ),
        ),
      );

      await harness.coordinator.applyTaskProposal(
        currentConversation: callerSnapshot,
        proposal: const WorkflowTaskProposalDraft(
          tasks: [
            ConversationWorkflowTask(id: 'proposal-task', title: 'Proposed'),
          ],
        ),
      );

      final write = harness.notifier.workflowWrites.single;
      expect(write.stage, ConversationWorkflowStage.tasks);
      expect(write.spec?.goal, 'Latest goal');
      expect(write.spec?.tasks.single.id, 'proposal-task');
      expect(harness.notifier.operations, ['workflow', 'dismiss']);
    },
  );

  test('proposal persistence failure does not dismiss', () async {
    final harness = _buildHarness(throwOnWorkflowWrite: true);
    addTearDown(harness.dispose);

    await expectLater(
      harness.coordinator.applyTaskProposal(
        currentConversation: harness.conversation,
        proposal: const WorkflowTaskProposalDraft(tasks: [_task]),
      ),
      throwsA(isA<StateError>()),
    );

    expect(harness.dismissCount, 0);
    expect(harness.notifier.operations, ['workflow']);
  });

  test('editor save appends a generated task and replaces in place', () async {
    final harness = _buildHarness();
    addTearDown(harness.dispose);

    final added = await harness.coordinator.applyEditorSubmission(
      currentConversation: harness.conversation,
      submission: const WorkflowTaskEditorSubmission.save(
        task: ConversationWorkflowTask(id: '', title: 'New task'),
      ),
    );
    final afterAdd = harness.conversation;
    final replaced = await harness.coordinator.applyEditorSubmission(
      currentConversation: afterAdd,
      submission: const WorkflowTaskEditorSubmission.save(
        task: ConversationWorkflowTask(
          id: 'task-1',
          title: 'Updated task',
          status: ConversationWorkflowTaskStatus.completed,
        ),
      ),
    );

    expect(added, WorkflowTaskApplyOutcome.saved);
    expect(replaced, WorkflowTaskApplyOutcome.saved);
    expect(afterAdd.effectiveWorkflowSpec.tasks[1].id, 'generated-task');
    expect(
      harness.conversation.effectiveWorkflowSpec.tasks[0].title,
      'Updated task',
    );
    expect(
      harness.conversation.effectiveWorkflowSpec.tasks[1].id,
      'generated-task',
    );
  });

  test(
    'editor delete removes an existing task and ignores an unsaved task',
    () async {
      final harness = _buildHarness(conversation: _conversation(goal: ''));
      addTearDown(harness.dispose);

      final ignored = await harness.coordinator.applyEditorSubmission(
        currentConversation: harness.conversation,
        submission: const WorkflowTaskEditorSubmission.delete(
          task: ConversationWorkflowTask(id: '', title: 'Unsaved'),
        ),
      );
      final deleted = await harness.coordinator.applyEditorSubmission(
        currentConversation: harness.conversation,
        submission: const WorkflowTaskEditorSubmission.delete(task: _task),
      );

      expect(ignored, WorkflowTaskApplyOutcome.ignored);
      expect(deleted, WorkflowTaskApplyOutcome.deleted);
      expect(harness.conversation.effectiveWorkflowSpec.tasks, isEmpty);
      expect(harness.notifier.workflowWrites, hasLength(1));
      expect(harness.notifier.workflowWrites.single.spec, isNull);
      expect(harness.notifier.workflowWrites.single.clearSpec, isTrue);
    },
  );

  test('legacy menu status actions rewrite tasks and stages', () async {
    final cases =
        <
          (
            WorkflowTaskMenuAction,
            ConversationWorkflowTaskStatus,
            ConversationWorkflowStage,
          )
        >[
          (
            WorkflowTaskMenuAction.markPending,
            ConversationWorkflowTaskStatus.pending,
            ConversationWorkflowStage.implement,
          ),
          (
            WorkflowTaskMenuAction.markInProgress,
            ConversationWorkflowTaskStatus.inProgress,
            ConversationWorkflowStage.implement,
          ),
          (
            WorkflowTaskMenuAction.markCompleted,
            ConversationWorkflowTaskStatus.completed,
            ConversationWorkflowStage.review,
          ),
          (
            WorkflowTaskMenuAction.markBlocked,
            ConversationWorkflowTaskStatus.blocked,
            ConversationWorkflowStage.implement,
          ),
        ];

    for (final (action, expectedStatus, expectedStage) in cases) {
      final harness = _buildHarness();
      addTearDown(harness.dispose);

      final outcome = await harness.coordinator.handleMenuAction(
        currentConversation: harness.conversation,
        task: _task,
        action: action,
      );

      expect(outcome, WorkflowTaskMenuOutcome.none);
      expect(harness.notifier.workflowWrites.single.stage, expectedStage);
      expect(
        harness.notifier.workflowWrites.single.spec?.tasks.single.status,
        expectedStatus,
      );
    }
  });

  test('plan status writes progress and preserves projected stages', () async {
    final completedHarness = _buildHarness(
      conversation: _conversation(usePlanDocument: true),
    );
    addTearDown(completedHarness.dispose);

    await completedHarness.coordinator.setTaskStatus(
      currentConversation: completedHarness.conversation,
      task: _task,
      status: ConversationWorkflowTaskStatus.completed,
      summary: 'Validated completion.',
      lastValidationCommand: 'dart test',
      eventType: ConversationExecutionTaskEventType.completed,
    );

    final progress = completedHarness.notifier.progressWrites.single;
    expect(progress.taskId, 'task-1');
    expect(progress.status, ConversationWorkflowTaskStatus.completed);
    expect(progress.summary, 'Validated completion.');
    expect(progress.blockedReason, '');
    expect(progress.lastValidationCommand, 'dart test');
    expect(progress.eventType, ConversationExecutionTaskEventType.completed);
    final workflow = completedHarness.notifier.workflowWrites.single;
    expect(workflow.stage, ConversationWorkflowStage.review);
    expect(workflow.preserveProjection, isTrue);

    final pendingHarness = _buildHarness(
      conversation: _conversation(usePlanDocument: true),
    );
    addTearDown(pendingHarness.dispose);
    await pendingHarness.coordinator.setTaskStatus(
      currentConversation: pendingHarness.conversation,
      task: _task,
      status: ConversationWorkflowTaskStatus.pending,
      blockedReason: 'Discard this blocker',
    );
    expect(pendingHarness.notifier.progressWrites.single.blockedReason, '');
    expect(pendingHarness.notifier.workflowWrites, isEmpty);
  });

  test(
    'plan blocked and unblocked menu actions retain event semantics',
    () async {
      final blockedHarness = _buildHarness(
        conversation: _conversation(usePlanDocument: true),
      );
      addTearDown(blockedHarness.dispose);
      await blockedHarness.coordinator.handleMenuAction(
        currentConversation: blockedHarness.conversation,
        task: _task,
        action: WorkflowTaskMenuAction.markBlocked,
      );
      final blocked = blockedHarness.notifier.progressWrites.single;
      expect(blocked.status, ConversationWorkflowTaskStatus.blocked);
      expect(
        blocked.blockedReason,
        'This task is blocked and needs follow-up.',
      );
      expect(blocked.eventType, ConversationExecutionTaskEventType.blocked);
      expect(
        blockedHarness.notifier.workflowWrites.single.stage,
        ConversationWorkflowStage.implement,
      );

      final unblockedHarness = _buildHarness(
        conversation: _conversation(usePlanDocument: true),
      );
      addTearDown(unblockedHarness.dispose);
      final outcome = await unblockedHarness.coordinator.handleMenuAction(
        currentConversation: unblockedHarness.conversation,
        task: _task,
        action: WorkflowTaskMenuAction.markUnblocked,
      );
      final unblocked = unblockedHarness.notifier.progressWrites.single;
      expect(outcome, WorkflowTaskMenuOutcome.unblocked);
      expect(unblocked.status, ConversationWorkflowTaskStatus.pending);
      expect(unblocked.eventType, ConversationExecutionTaskEventType.unblocked);
      expect(unblockedHarness.notifier.workflowWrites, isEmpty);
    },
  );

  test(
    'UI-only menu actions return typed outcomes without persistence',
    () async {
      final legacyHarness = _buildHarness();
      addTearDown(legacyHarness.dispose);
      final planHarness = _buildHarness(
        conversation: _conversation(usePlanDocument: true),
      );
      addTearDown(planHarness.dispose);

      expect(
        await legacyHarness.coordinator.handleMenuAction(
          currentConversation: legacyHarness.conversation,
          task: _task,
          action: WorkflowTaskMenuAction.edit,
        ),
        WorkflowTaskMenuOutcome.edit,
      );
      expect(
        await planHarness.coordinator.handleMenuAction(
          currentConversation: planHarness.conversation,
          task: _task,
          action: WorkflowTaskMenuAction.edit,
        ),
        WorkflowTaskMenuOutcome.none,
      );
      expect(
        await planHarness.coordinator.handleMenuAction(
          currentConversation: planHarness.conversation,
          task: _task,
          action: WorkflowTaskMenuAction.editBlockedReason,
        ),
        WorkflowTaskMenuOutcome.editBlockedReason,
      );
      expect(
        await planHarness.coordinator.handleMenuAction(
          currentConversation: planHarness.conversation,
          task: _task,
          action: WorkflowTaskMenuAction.replanFromBlocker,
        ),
        WorkflowTaskMenuOutcome.replanFromBlocker,
      );
      expect(legacyHarness.notifier.operations, isEmpty);
      expect(planHarness.notifier.operations, isEmpty);
    },
  );

  test('menu delete persists only for legacy tasks', () async {
    final legacyHarness = _buildHarness();
    addTearDown(legacyHarness.dispose);
    final planHarness = _buildHarness(
      conversation: _conversation(usePlanDocument: true),
    );
    addTearDown(planHarness.dispose);

    expect(
      await legacyHarness.coordinator.handleMenuAction(
        currentConversation: legacyHarness.conversation,
        task: _task,
        action: WorkflowTaskMenuAction.delete,
      ),
      WorkflowTaskMenuOutcome.deleted,
    );
    expect(
      await planHarness.coordinator.handleMenuAction(
        currentConversation: planHarness.conversation,
        task: _task,
        action: WorkflowTaskMenuAction.delete,
      ),
      WorkflowTaskMenuOutcome.none,
    );
    expect(legacyHarness.conversation.effectiveWorkflowSpec.tasks, isEmpty);
    expect(planHarness.notifier.operations, isEmpty);
  });
}
