import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../providers/chat_state.dart';
import '../providers/conversations_notifier.dart';

enum WorkflowEditorAction { save, clear }

final class WorkflowEditorSubmission {
  const WorkflowEditorSubmission.save({
    required this.workflowStage,
    required this.workflowSpec,
  }) : action = WorkflowEditorAction.save;

  const WorkflowEditorSubmission.clear()
    : action = WorkflowEditorAction.clear,
      workflowStage = ConversationWorkflowStage.idle,
      workflowSpec = const ConversationWorkflowSpec();

  final WorkflowEditorAction action;
  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowSpec workflowSpec;
}

enum WorkflowEditorApplyOutcome { saved, cleared }

final class WorkflowEditorActionCoordinator {
  WorkflowEditorActionCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required void Function() dismissWorkflowProposal,
  }) : _conversationsNotifier = conversationsNotifier,
       _dismissWorkflowProposal = dismissWorkflowProposal;

  final ConversationsNotifier _conversationsNotifier;
  final void Function() _dismissWorkflowProposal;

  Future<WorkflowEditorApplyOutcome> applySubmission(
    WorkflowEditorSubmission submission, {
    required bool dismissWorkflowProposalOnSave,
  }) async {
    final outcome = switch (submission.action) {
      WorkflowEditorAction.clear => await _clearWorkflow(),
      WorkflowEditorAction.save => await _saveWorkflow(submission),
    };
    if (dismissWorkflowProposalOnSave) {
      _dismissWorkflowProposal();
    }
    return outcome;
  }

  Future<WorkflowEditorApplyOutcome> _clearWorkflow() async {
    await _conversationsNotifier.updateCurrentWorkflow(
      workflowStage: ConversationWorkflowStage.idle,
      clearWorkflowSpec: true,
    );
    await _conversationsNotifier.updateCurrentPlanArtifact(
      clearPlanArtifact: true,
    );
    return WorkflowEditorApplyOutcome.cleared;
  }

  Future<WorkflowEditorApplyOutcome> _saveWorkflow(
    WorkflowEditorSubmission submission,
  ) async {
    await _conversationsNotifier.updateCurrentWorkflow(
      workflowStage: submission.workflowStage,
      workflowSpec: submission.workflowSpec.hasContent
          ? submission.workflowSpec
          : null,
      clearWorkflowSpec: !submission.workflowSpec.hasContent,
    );
    return WorkflowEditorApplyOutcome.saved;
  }

  Future<void> applyWorkflowProposal({
    required Conversation currentConversation,
    required WorkflowProposalDraft proposal,
  }) async {
    final nextSpec = proposal.workflowSpec.copyWith(
      tasks: currentConversation.effectiveWorkflowSpec.tasks,
    );
    await _conversationsNotifier.updateCurrentWorkflow(
      workflowStage: proposal.workflowStage,
      workflowSpec: nextSpec.hasContent ? nextSpec : null,
      clearWorkflowSpec: !nextSpec.hasContent,
    );
    _dismissWorkflowProposal();
  }
}
