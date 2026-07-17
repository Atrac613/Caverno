import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

class _WorkflowEditorConversationsNotifier extends ConversationsNotifier {
  _WorkflowEditorConversationsNotifier(
    this.conversation, {
    this.throwOnWorkflowWrite = false,
  });

  final Conversation conversation;
  final bool throwOnWorkflowWrite;
  final List<String> operations = [];
  ConversationWorkflowStage? lastWorkflowStage;
  ConversationWorkflowSpec? lastWorkflowSpec;
  var lastClearWorkflowSpec = false;
  var lastClearPlanArtifact = false;

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
    lastWorkflowStage = workflowStage;
    lastWorkflowSpec = workflowSpec;
    lastClearWorkflowSpec = clearWorkflowSpec;
  }

  @override
  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    operations.add('plan');
    lastClearPlanArtifact = clearPlanArtifact;
  }
}

class _CoordinatorHarness {
  _CoordinatorHarness({required this.container, required this.notifier}) {
    coordinator = WorkflowEditorActionCoordinator(
      conversationsNotifier: notifier,
      dismissWorkflowProposal: () {
        dismissCount += 1;
        notifier.operations.add('dismiss');
      },
    );
  }

  final ProviderContainer container;
  final _WorkflowEditorConversationsNotifier notifier;
  late final WorkflowEditorActionCoordinator coordinator;
  var dismissCount = 0;

  void dispose() => container.dispose();
}

_CoordinatorHarness _buildHarness({bool throwOnWorkflowWrite = false}) {
  final now = DateTime(2026, 7, 17, 13);
  final conversation = Conversation(
    id: 'conversation-1',
    title: 'Workflow editor',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workspaceMode: WorkspaceMode.coding,
    workflowStage: ConversationWorkflowStage.clarify,
    workflowSpec: const ConversationWorkflowSpec(
      goal: 'Existing goal',
      tasks: [
        ConversationWorkflowTask(
          id: 'existing-task',
          title: 'Keep existing task',
        ),
      ],
    ),
  );
  final notifier = _WorkflowEditorConversationsNotifier(
    conversation,
    throwOnWorkflowWrite: throwOnWorkflowWrite,
  );
  final container = ProviderContainer(
    overrides: [conversationsNotifierProvider.overrideWith(() => notifier)],
  );
  container.read(conversationsNotifierProvider);
  return _CoordinatorHarness(container: container, notifier: notifier);
}

void main() {
  test('applySubmission saves a non-empty workflow spec', () async {
    final harness = _buildHarness();
    addTearDown(harness.dispose);
    const spec = ConversationWorkflowSpec(
      goal: 'Updated goal',
      constraints: ['Stay focused'],
    );

    final outcome = await harness.coordinator.applySubmission(
      const WorkflowEditorSubmission.save(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: spec,
      ),
      dismissWorkflowProposalOnSave: false,
    );

    expect(outcome, WorkflowEditorApplyOutcome.saved);
    expect(harness.notifier.lastWorkflowStage, ConversationWorkflowStage.plan);
    expect(harness.notifier.lastWorkflowSpec, spec);
    expect(harness.notifier.lastClearWorkflowSpec, isFalse);
    expect(harness.dismissCount, 0);
  });

  test('applySubmission clears an empty saved workflow spec', () async {
    final harness = _buildHarness();
    addTearDown(harness.dispose);

    await harness.coordinator.applySubmission(
      const WorkflowEditorSubmission.save(
        workflowStage: ConversationWorkflowStage.tasks,
        workflowSpec: ConversationWorkflowSpec(),
      ),
      dismissWorkflowProposalOnSave: true,
    );

    expect(harness.notifier.lastWorkflowStage, ConversationWorkflowStage.tasks);
    expect(harness.notifier.lastWorkflowSpec, isNull);
    expect(harness.notifier.lastClearWorkflowSpec, isTrue);
    expect(harness.notifier.operations, ['workflow', 'dismiss']);
  });

  test('applySubmission clears workflow before the plan artifact', () async {
    final harness = _buildHarness();
    addTearDown(harness.dispose);

    final outcome = await harness.coordinator.applySubmission(
      const WorkflowEditorSubmission.clear(),
      dismissWorkflowProposalOnSave: true,
    );

    expect(outcome, WorkflowEditorApplyOutcome.cleared);
    expect(harness.notifier.lastWorkflowStage, ConversationWorkflowStage.idle);
    expect(harness.notifier.lastClearWorkflowSpec, isTrue);
    expect(harness.notifier.lastClearPlanArtifact, isTrue);
    expect(harness.notifier.operations, ['workflow', 'plan', 'dismiss']);
  });

  test('applyWorkflowProposal retains current conversation tasks', () async {
    final harness = _buildHarness();
    addTearDown(harness.dispose);
    const proposal = WorkflowProposalDraft(
      workflowStage: ConversationWorkflowStage.review,
      workflowSpec: ConversationWorkflowSpec(
        goal: 'Proposed goal',
        constraints: ['Proposed constraint'],
        tasks: [
          ConversationWorkflowTask(
            id: 'proposal-task',
            title: 'Discard proposal task',
          ),
        ],
      ),
    );
    final currentConversation = harness.container
        .read(conversationsNotifierProvider)
        .currentConversation!;

    await harness.coordinator.applyWorkflowProposal(
      currentConversation: currentConversation,
      proposal: proposal,
    );

    expect(
      harness.notifier.lastWorkflowStage,
      ConversationWorkflowStage.review,
    );
    expect(harness.notifier.lastWorkflowSpec?.goal, 'Proposed goal');
    expect(harness.notifier.lastWorkflowSpec?.tasks.single.id, 'existing-task');
    expect(harness.notifier.operations, ['workflow', 'dismiss']);
  });

  test('persistence failure does not dismiss the workflow proposal', () async {
    final harness = _buildHarness(throwOnWorkflowWrite: true);
    addTearDown(harness.dispose);

    await expectLater(
      harness.coordinator.applySubmission(
        const WorkflowEditorSubmission.clear(),
        dismissWorkflowProposalOnSave: true,
      ),
      throwsA(isA<StateError>()),
    );

    expect(harness.notifier.operations, ['workflow']);
    expect(harness.dismissCount, 0);
  });
}
