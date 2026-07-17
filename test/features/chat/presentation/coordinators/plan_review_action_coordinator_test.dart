import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/coordinators/plan_review_action_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

const _validPlanMarkdown = '''
# Plan

## Stage
implement

## Tasks
1. Build the CLI
   - Task ID: build-cli
   - Status: pending
''';

final _fixedNow = DateTime(2026, 7, 17, 11, 30);

class _CoordinatorConversationsNotifier extends ConversationsNotifier {
  _CoordinatorConversationsNotifier(
    this.conversation, {
    this.refreshResult = true,
    this.onRefresh,
  });

  final Conversation conversation;
  final bool refreshResult;
  final void Function()? onRefresh;
  var enterPlanningCount = 0;
  var exitPlanningCount = 0;
  var planArtifactWriteCount = 0;
  var workflowWriteCount = 0;
  var refreshCount = 0;
  var lastClearPlanArtifact = false;
  ConversationPlanArtifact? lastPlanArtifact;
  ConversationWorkflowStage? lastWorkflowStage;
  ConversationWorkflowSpec? lastWorkflowSpec;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

  @override
  Future<void> enterPlanningSession() async {
    enterPlanningCount += 1;
    replaceCurrent(
      state.currentConversation!.copyWith(
        executionMode: ConversationExecutionMode.planning,
      ),
    );
  }

  @override
  Future<void> exitPlanningSession() async {
    exitPlanningCount += 1;
    replaceCurrent(
      state.currentConversation!.copyWith(
        executionMode: ConversationExecutionMode.normal,
      ),
    );
  }

  @override
  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    planArtifactWriteCount += 1;
    lastClearPlanArtifact = clearPlanArtifact;
    lastPlanArtifact = planArtifact;
    replaceCurrent(
      state.currentConversation!.copyWith(
        planArtifact: clearPlanArtifact ? null : planArtifact,
      ),
    );
  }

  @override
  Future<bool> refreshCurrentWorkflowProjectionFromApprovedPlan() async {
    refreshCount += 1;
    onRefresh?.call();
    return refreshResult;
  }

  @override
  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    String? workflowSourceHash,
    DateTime? workflowDerivedAt,
    bool clearWorkflowSpec = false,
    bool preserveWorkflowProjection = false,
  }) async {
    workflowWriteCount += 1;
    lastWorkflowStage = workflowStage;
    lastWorkflowSpec = workflowSpec;
    final current = state.currentConversation!;
    replaceCurrent(
      current.copyWith(
        workflowStage: workflowStage ?? current.workflowStage,
        workflowSpec: clearWorkflowSpec
            ? null
            : workflowSpec ?? current.workflowSpec,
        workflowSourceHash: workflowSourceHash ?? current.workflowSourceHash,
        workflowDerivedAt: workflowDerivedAt ?? current.workflowDerivedAt,
      ),
    );
  }

  void replaceCurrent(Conversation updated) {
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }
}

class _MountedState {
  var value = true;
}

class _CoordinatorHarness {
  _CoordinatorHarness({
    required this.container,
    required this.notifier,
    required this.mountedState,
  }) {
    coordinator = PlanReviewActionCoordinator(
      conversationsNotifier: notifier,
      readCurrentConversation: () =>
          container.read(conversationsNotifierProvider).currentConversation,
      dismissPlanProposal: () => dismissCount += 1,
      isPageMounted: () => mountedState.value,
      now: () => _fixedNow,
    );
  }

  final ProviderContainer container;
  final _CoordinatorConversationsNotifier notifier;
  final _MountedState mountedState;
  late final PlanReviewActionCoordinator coordinator;
  var dismissCount = 0;

  Conversation get conversation =>
      container.read(conversationsNotifierProvider).currentConversation!;

  void dispose() => container.dispose();
}

_CoordinatorHarness _buildHarness({
  required Conversation conversation,
  bool refreshResult = true,
  void Function()? onRefresh,
}) {
  final notifier = _CoordinatorConversationsNotifier(
    conversation,
    refreshResult: refreshResult,
    onRefresh: onRefresh,
  );
  final container = ProviderContainer(
    overrides: [conversationsNotifierProvider.overrideWith(() => notifier)],
  );
  container.read(conversationsNotifierProvider);
  return _CoordinatorHarness(
    container: container,
    notifier: notifier,
    mountedState: _MountedState(),
  );
}

Conversation _conversation({
  ConversationExecutionMode executionMode = ConversationExecutionMode.normal,
  ConversationPlanArtifact? planArtifact,
  ConversationWorkflowSpec? workflowSpec,
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Plan review',
    messages: const [],
    createdAt: _fixedNow,
    updatedAt: _fixedNow,
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    executionMode: executionMode,
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: workflowSpec,
    planArtifact: planArtifact,
  );
}

void main() {
  test('prepareEdit enters planning and returns the approved seed', () async {
    final harness = _buildHarness(
      conversation: _conversation(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown: _validPlanMarkdown,
        ),
      ),
    );
    addTearDown(harness.dispose);

    final seed = await harness.coordinator.prepareEdit(
      currentConversation: harness.conversation,
    );

    expect(harness.notifier.enterPlanningCount, 1);
    expect(harness.conversation.isPlanningSession, isTrue);
    expect(
      seed,
      'Please revise the saved plan for this thread based on the following adjustment:\n- ',
    );
  });

  test('prepareEdit keeps an active planning session and draft seed', () async {
    final harness = _buildHarness(
      conversation: _conversation(
        executionMode: ConversationExecutionMode.planning,
        planArtifact: const ConversationPlanArtifact(
          draftMarkdown: _validPlanMarkdown,
        ),
      ),
    );
    addTearDown(harness.dispose);

    final seed = await harness.coordinator.prepareEdit(
      currentConversation: harness.conversation,
    );

    expect(harness.notifier.enterPlanningCount, 0);
    expect(
      seed,
      'Please adjust the current draft plan for this thread as follows:\n- ',
    );
  });

  test(
    'prepareEdit stops after planning entry when the page unmounts',
    () async {
      final harness = _buildHarness(
        conversation: _conversation(
          planArtifact: const ConversationPlanArtifact(
            draftMarkdown: _validPlanMarkdown,
          ),
        ),
      );
      addTearDown(harness.dispose);
      harness.mountedState.value = false;

      final seed = await harness.coordinator.prepareEdit(
        currentConversation: harness.conversation,
      );

      expect(harness.notifier.enterPlanningCount, 1);
      expect(seed, isNull);
    },
  );

  test(
    'cancelReview restores approved pending edits from latest state',
    () async {
      const approvedMarkdown = '# Plan\n\n## Stage\nreview';
      final harness = _buildHarness(
        conversation: _conversation(
          executionMode: ConversationExecutionMode.planning,
          planArtifact: const ConversationPlanArtifact(
            draftMarkdown: '# Plan\n\n## Stage\nimplement',
            approvedMarkdown: approvedMarkdown,
          ),
        ),
      );
      addTearDown(harness.dispose);

      final completed = await harness.coordinator.cancelReview(
        currentConversation: _conversation(),
      );

      final artifact = harness.conversation.effectivePlanArtifact;
      expect(completed, isTrue);
      expect(artifact.normalizedDraftMarkdown, approvedMarkdown);
      expect(artifact.updatedAt, _fixedNow);
      expect(artifact.revisions.single.createdAt, _fixedNow);
      expect(
        artifact.revisions.single.kind,
        ConversationPlanRevisionKind.restored,
      );
      expect(
        artifact.revisions.single.label,
        'Cancelled draft changes and restored approved plan',
      );
      expect(harness.notifier.exitPlanningCount, 1);
      expect(harness.dismissCount, 1);
    },
  );

  test('cancelReview clears an unapproved draft', () async {
    final harness = _buildHarness(
      conversation: _conversation(
        executionMode: ConversationExecutionMode.planning,
        planArtifact: const ConversationPlanArtifact(
          draftMarkdown: _validPlanMarkdown,
        ),
      ),
    );
    addTearDown(harness.dispose);

    await harness.coordinator.cancelReview(
      currentConversation: harness.conversation,
    );

    expect(harness.notifier.lastClearPlanArtifact, isTrue);
    expect(harness.conversation.hasPlanArtifact, isFalse);
    expect(harness.notifier.exitPlanningCount, 1);
    expect(harness.dismissCount, 1);
  });

  test('cancelReview retains an approved plan without pending edits', () async {
    final harness = _buildHarness(
      conversation: _conversation(
        executionMode: ConversationExecutionMode.planning,
        planArtifact: const ConversationPlanArtifact(
          draftMarkdown: _validPlanMarkdown,
          approvedMarkdown: _validPlanMarkdown,
        ),
      ),
    );
    addTearDown(harness.dispose);

    await harness.coordinator.cancelReview(
      currentConversation: harness.conversation,
    );

    expect(harness.notifier.planArtifactWriteCount, 0);
    expect(harness.conversation.hasPlanArtifact, isTrue);
    expect(harness.notifier.exitPlanningCount, 1);
    expect(harness.dismissCount, 1);
  });

  test(
    'approveCurrentPlan reports a missing document without mutation',
    () async {
      final harness = _buildHarness(conversation: _conversation());
      addTearDown(harness.dispose);

      final outcome = await harness.coordinator.approveCurrentPlan(
        currentConversation: harness.conversation,
      );

      expect(outcome, isA<PlanReviewApprovalMissingDocument>());
      expect(harness.notifier.planArtifactWriteCount, 0);
      expect(harness.notifier.refreshCount, 0);
      expect(harness.notifier.exitPlanningCount, 0);
      expect(harness.dismissCount, 0);
    },
  );

  test(
    'approveCurrentPlan reports validation failure before mutation',
    () async {
      final harness = _buildHarness(
        conversation: _conversation(
          planArtifact: const ConversationPlanArtifact(
            draftMarkdown: '# Plan\n\nMissing the required sections.',
          ),
        ),
      );
      addTearDown(harness.dispose);

      final outcome = await harness.coordinator.approveCurrentPlan(
        currentConversation: harness.conversation,
      );

      expect(outcome, isA<PlanReviewApprovalBlocked>());
      expect(
        (outcome as PlanReviewApprovalBlocked).errorMessage,
        'plan document must include a Stage section',
      );
      expect(harness.notifier.planArtifactWriteCount, 0);
      expect(harness.notifier.workflowWriteCount, 0);
      expect(harness.dismissCount, 0);
    },
  );

  test(
    'approveCurrentPlan persists approval and selects the next task',
    () async {
      const task = ConversationWorkflowTask(
        id: 'build-cli',
        title: 'Build the CLI',
      );
      final harness = _buildHarness(
        conversation: _conversation(
          executionMode: ConversationExecutionMode.planning,
          planArtifact: const ConversationPlanArtifact(
            draftMarkdown: _validPlanMarkdown,
          ),
          workflowSpec: const ConversationWorkflowSpec(tasks: [task]),
        ),
      );
      addTearDown(harness.dispose);

      final outcome = await harness.coordinator.approveCurrentPlan(
        currentConversation: harness.conversation,
      );

      expect(outcome, isA<PlanReviewApprovalReady>());
      final ready = outcome as PlanReviewApprovalReady;
      expect(ready.nextTask?.id, task.id);
      expect(harness.notifier.lastPlanArtifact?.hasApproved, isTrue);
      expect(
        harness.notifier.lastPlanArtifact?.revisions.single.kind,
        ConversationPlanRevisionKind.approved,
      );
      expect(
        harness.notifier.lastPlanArtifact?.revisions.single.label,
        'Approved plan from timeline review',
      );
      expect(harness.notifier.refreshCount, 1);
      expect(harness.notifier.workflowWriteCount, 0);
      expect(harness.notifier.exitPlanningCount, 1);
      expect(harness.dismissCount, 1);
    },
  );

  test(
    'approveCurrentPlan falls back to the parsed workflow projection',
    () async {
      final harness = _buildHarness(
        conversation: _conversation(
          executionMode: ConversationExecutionMode.planning,
          planArtifact: const ConversationPlanArtifact(
            draftMarkdown: _validPlanMarkdown,
          ),
        ),
        refreshResult: false,
      );
      addTearDown(harness.dispose);

      final outcome = await harness.coordinator.approveCurrentPlan(
        currentConversation: harness.conversation,
      );

      expect(outcome, isA<PlanReviewApprovalReady>());
      expect((outcome as PlanReviewApprovalReady).nextTask?.id, 'build-cli');
      expect(harness.notifier.workflowWriteCount, 1);
      expect(
        harness.notifier.lastWorkflowStage,
        ConversationWorkflowStage.implement,
      );
      expect(harness.notifier.lastWorkflowSpec?.tasks.single.id, 'build-cli');
      expect(harness.notifier.exitPlanningCount, 1);
      expect(harness.dismissCount, 1);
    },
  );

  test(
    'approveCurrentPlan aborts after refresh when the page unmounts',
    () async {
      late _MountedState mountedState;
      final harness = _buildHarness(
        conversation: _conversation(
          executionMode: ConversationExecutionMode.planning,
          planArtifact: const ConversationPlanArtifact(
            draftMarkdown: _validPlanMarkdown,
          ),
        ),
        onRefresh: () => mountedState.value = false,
      );
      addTearDown(harness.dispose);
      mountedState = harness.mountedState;

      final outcome = await harness.coordinator.approveCurrentPlan(
        currentConversation: harness.conversation,
      );

      expect(outcome, isA<PlanReviewApprovalAborted>());
      expect(harness.notifier.planArtifactWriteCount, 1);
      expect(harness.notifier.refreshCount, 1);
      expect(harness.notifier.workflowWriteCount, 0);
      expect(harness.notifier.exitPlanningCount, 0);
      expect(harness.dismissCount, 0);
    },
  );
}
