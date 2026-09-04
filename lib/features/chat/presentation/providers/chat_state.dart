export '../../domain/services/ask_user_question_policy.dart'
    show AskUserQuestionAnswer, AskUserQuestionOption, AskUserQuestionSelection;

import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/workflow_proposal_draft.dart';
import '../../domain/services/context_surgery_observation_service.dart';

import 'queued_chat_message.dart';

// Re-exported so every existing chat_state.dart import still sees the queue
// entry that used to live here; the freezed part file needs the import above.
export 'pending_tool_approvals.dart';
import 'pending_tool_approvals.dart';
export 'queued_chat_message.dart';
// The model-initiated question holder moved out when this file reached its
// ratchet ceiling; re-exported so every existing importer still sees it.
export 'pending_ask_user_question.dart';
// Clearing an answered approval out of this state is a per-type dispatch
// that grows with the hierarchy, so it lives beside it rather than in
// ThreadScopedChatState; re-exported for the callers that already import
// chat_state.dart.
export 'pending_tool_approval_projection.dart';
import 'pending_ask_user_question.dart';

export '../../domain/entities/workflow_proposal_draft.dart';

part 'chat_state.freezed.dart';

enum ContextTokenPressureLevel { normal, warning, critical }

class PendingWorkflowDecision {
  PendingWorkflowDecision({
    required this.id,
    required this.decision,
    required this.completer,
  });

  final String id;
  final WorkflowPlanningDecision decision;
  final Completer<WorkflowPlanningDecisionAnswer?> completer;
}

@freezed
abstract class WorkflowTaskProposalDraft with _$WorkflowTaskProposalDraft {
  const factory WorkflowTaskProposalDraft({
    required List<ConversationWorkflowTask> tasks,
  }) = _WorkflowTaskProposalDraft;
}

@freezed
abstract class ParticipantTurnRuntime with _$ParticipantTurnRuntime {
  const factory ParticipantTurnRuntime({
    String? activeParticipantId,
    @Default('') String activeParticipantName,
    @Default('') String activeParticipantRoleLabel,
    int? activeParticipantColorValue,
    @Default(1) int currentRound,
    @Default(1) int maxRounds,
    @Default(false) bool multiRound,
    @Default(false) bool stopRequested,
    @Default(false) bool paused,
    @Default('') String activeToolName,
  }) = _ParticipantTurnRuntime;
}

@freezed
abstract class ChatState with _$ChatState {
  const factory ChatState({
    required List<Message> messages,
    @Default([]) List<QueuedChatMessage> queuedMessages,
    // Interruptions filed against the running turn but not yet carried by one
    // of its requests. They join the transcript the moment a request takes
    // them, so this list is what the user has typed and cannot see yet.
    @Default([]) List<QueuedChatMessage> steeringMessages,
    required bool isLoading,
    // Conversations with a running response, including ones the user is not
    // looking at. Lives in the state (not only in ActiveResponseRegistry) so
    // clearing the last entry notifies listeners; the thread list renders its
    // busy spinner from this.
    @Default(<String>{}) Set<String> busyConversationIds,
    // Threads blocked on an approval the user has not answered. Such a thread
    // is not working, so the sidebar says so instead of spinning forever.
    @Default(<String>{}) Set<String> approvalRequiredConversationIds,
    String? error,
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default(0) int totalTokens,
    @Default(0) int estimatedPromptTokens,
    @Default(ContextTokenPressureLevel.normal)
    ContextTokenPressureLevel contextTokenPressureLevel,
    @Default(false) bool promptCompactionActive,
    @Default(ContextSurgeryObservationSnapshot.empty)
    ContextSurgeryObservationSnapshot contextSurgerySnapshot,
    ParticipantTurnRuntime? participantTurnRuntime,
    // SSH tool UI flow — holders contain Completers so they live outside
    // the freezed equality graph.
    PendingSshConnect? pendingSshConnect,
    PendingSshCommand? pendingSshCommand,
    // Git tool UI flow — same Completer-based pattern as SSH.
    PendingGitCommand? pendingGitCommand,
    // Local shell tool UI flow.
    PendingLocalCommand? pendingLocalCommand,
    // macOS computer-use tool UI flow.
    PendingComputerUseAction? pendingComputerUseAction,
    // Built-in browser sensitive-action UI flow.
    PendingBrowserAction? pendingBrowserAction,
    // File mutation tool UI flow.
    PendingFileOperation? pendingFileOperation,
    // BLE tool UI flow — same Completer-based pattern as SSH.
    PendingBleConnect? pendingBleConnect,
    // Serial port open UI flow — same Completer-based approval as BLE.
    PendingSerialOpen? pendingSerialOpen,
    // Participant read-only tool UI flow.
    PendingParticipantToolApproval? pendingParticipantToolApproval,
    // ANA0 material contract assumption confirmation UI flow.
    PendingAssumptionConfirmation? pendingAssumptionConfirmation,
    // Generic model-initiated question UI flow.
    PendingAskUserQuestion? pendingAskUserQuestion,
    // Workflow planning choice UI flow.
    PendingWorkflowDecision? pendingWorkflowDecision,
    @Default(false) bool isGeneratingWorkflowProposal,
    WorkflowProposalDraft? workflowProposalDraft,
    String? workflowProposalError,
    @Default(false) bool isGeneratingTaskProposal,
    WorkflowTaskProposalDraft? taskProposalDraft,
    String? taskProposalError,
    @Default(0) int goalAutoContinueCount,
    @Default(0) int goalAutoContinueBudget,
    String? goalAutoContinueNotice,
  }) = _ChatState;

  factory ChatState.initial() =>
      const ChatState(messages: [], isLoading: false);
}
