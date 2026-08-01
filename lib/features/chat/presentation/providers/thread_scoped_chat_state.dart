import 'chat_state.dart';

/// The parts of [ChatState] that belong to one thread rather than to the app.
///
/// ChatState is rebuilt from scratch on every thread switch, which dropped
/// both the plan draft and any approval the thread was waiting on. The plan
/// artifact itself is persisted, so a thread still rendered a plan behind the
/// expand control, but the review sheet auto-presents from these fields and so
/// never appeared; a pending approval simply vanished.
class ThreadScopedChatState {
  const ThreadScopedChatState({
    this.pendingWorkflowDecision,
    this.isGeneratingWorkflowProposal = false,
    this.workflowProposalDraft,
    this.workflowProposalError,
    this.isGeneratingTaskProposal = false,
    this.taskProposalDraft,
    this.taskProposalError,
    this.pendingSshConnect,
    this.pendingSshCommand,
    this.pendingGitCommand,
    this.pendingLocalCommand,
    this.pendingComputerUseAction,
    this.pendingBrowserAction,
    this.pendingFileOperation,
    this.pendingBleConnect,
    this.pendingSerialOpen,
    this.pendingParticipantToolApproval,
    this.participantTurnRuntime,
  });

  factory ThreadScopedChatState.from(ChatState state) {
    return ThreadScopedChatState(
      pendingWorkflowDecision: state.pendingWorkflowDecision,
      isGeneratingWorkflowProposal: state.isGeneratingWorkflowProposal,
      workflowProposalDraft: state.workflowProposalDraft,
      workflowProposalError: state.workflowProposalError,
      isGeneratingTaskProposal: state.isGeneratingTaskProposal,
      taskProposalDraft: state.taskProposalDraft,
      taskProposalError: state.taskProposalError,
      pendingSshConnect: state.pendingSshConnect,
      pendingSshCommand: state.pendingSshCommand,
      pendingGitCommand: state.pendingGitCommand,
      pendingLocalCommand: state.pendingLocalCommand,
      pendingComputerUseAction: state.pendingComputerUseAction,
      pendingBrowserAction: state.pendingBrowserAction,
      pendingFileOperation: state.pendingFileOperation,
      pendingBleConnect: state.pendingBleConnect,
      pendingSerialOpen: state.pendingSerialOpen,
      pendingParticipantToolApproval: state.pendingParticipantToolApproval,
      participantTurnRuntime: state.participantTurnRuntime,
    );
  }

  static const ThreadScopedChatState empty = ThreadScopedChatState();

  /// Stores what [state] is drafting under [threadId], or forgets that thread
  /// when there is nothing worth restoring.
  static void remember(
    Map<String, ThreadScopedChatState> byThread,
    String? threadId,
    ChatState state,
  ) {
    if (threadId == null) return;
    final draft = ThreadScopedChatState.from(state);
    if (draft.hasContent) {
      byThread[threadId] = draft;
    } else {
      byThread.remove(threadId);
    }
  }

  /// Removes and returns [threadId]'s stash: once restored into ChatState it
  /// is live there, and leaving the thread stashes it again.
  static ThreadScopedChatState take(
    Map<String, ThreadScopedChatState> byThread,
    String? threadId,
  ) => byThread.remove(threadId) ?? empty;

  final PendingWorkflowDecision? pendingWorkflowDecision;
  final bool isGeneratingWorkflowProposal;
  final WorkflowProposalDraft? workflowProposalDraft;
  final String? workflowProposalError;
  final bool isGeneratingTaskProposal;
  final WorkflowTaskProposalDraft? taskProposalDraft;
  final String? taskProposalError;

  // Approvals the thread is waiting on.
  final PendingSshConnect? pendingSshConnect;
  final PendingSshCommand? pendingSshCommand;
  final PendingGitCommand? pendingGitCommand;
  final PendingLocalCommand? pendingLocalCommand;
  final PendingComputerUseAction? pendingComputerUseAction;
  final PendingBrowserAction? pendingBrowserAction;
  final PendingFileOperation? pendingFileOperation;
  final PendingBleConnect? pendingBleConnect;
  final PendingSerialOpen? pendingSerialOpen;
  final PendingParticipantToolApproval? pendingParticipantToolApproval;
  final ParticipantTurnRuntime? participantTurnRuntime;

  /// Whether the thread is blocked waiting for the user to answer something.
  /// A thread in this state is not working, so the sidebar must say so rather
  /// than spin.
  /// A finished plan is waiting to be reviewed, which is an approval in
  /// everything but name — the thread has stopped and cannot proceed alone.
  bool get hasCompletedPlanDraft =>
      workflowProposalDraft != null && taskProposalDraft != null;

  bool get needsApproval =>
      hasCompletedPlanDraft ||
      pendingWorkflowDecision != null ||
      pendingSshConnect != null ||
      pendingSshCommand != null ||
      pendingGitCommand != null ||
      pendingLocalCommand != null ||
      pendingComputerUseAction != null ||
      pendingBrowserAction != null ||
      pendingFileOperation != null ||
      pendingBleConnect != null ||
      pendingSerialOpen != null ||
      pendingParticipantToolApproval != null;

  /// Applies a state update to the thread whose turn produced it.
  ///
  /// A turn running in the background must not put its prompt in front of
  /// whoever the user is currently reading: the prompt is stashed for its own
  /// thread and the thread is listed as waiting, so the sidebar can say so and
  /// the prompt appears when the user goes there.
  static ChatState routeToThread({
    required Map<String, ThreadScopedChatState> byThread,
    required String? turnThread,
    required String? visibleThread,
    required ChatState current,
    required ChatState Function(ChatState) apply,
  }) {
    if (turnThread == null || turnThread == visibleThread) {
      return apply(current);
    }
    final existing = byThread[turnThread] ?? empty;
    byThread[turnThread] = ThreadScopedChatState.from(
      apply(existing.applyTo(ChatState.initial())),
    );
    return current.copyWith(
      approvalRequiredConversationIds: awaitingApproval(byThread),
    );
  }

  /// Threads that are waiting on the user, for the sidebar.
  static Set<String> awaitingApproval(
    Map<String, ThreadScopedChatState> byThread,
  ) {
    return byThread.entries
        .where((entry) => entry.value.needsApproval)
        .map((entry) => entry.key)
        .toSet();
  }

  static ChatState clearPendingToolApproval(
    ChatState current,
    PendingToolApproval<dynamic> pending,
  ) {
    return switch (pending) {
      PendingSshConnect() when identical(current.pendingSshConnect, pending) =>
        current.copyWith(pendingSshConnect: null),
      PendingSshCommand() when identical(current.pendingSshCommand, pending) =>
        current.copyWith(pendingSshCommand: null),
      PendingGitCommand() when identical(current.pendingGitCommand, pending) =>
        current.copyWith(pendingGitCommand: null),
      PendingLocalCommand()
          when identical(current.pendingLocalCommand, pending) =>
        current.copyWith(pendingLocalCommand: null),
      PendingFileOperation()
          when identical(current.pendingFileOperation, pending) =>
        current.copyWith(pendingFileOperation: null),
      PendingComputerUseAction()
          when identical(current.pendingComputerUseAction, pending) =>
        current.copyWith(pendingComputerUseAction: null),
      PendingBrowserAction()
          when identical(current.pendingBrowserAction, pending) =>
        current.copyWith(pendingBrowserAction: null),
      PendingBleConnect() when identical(current.pendingBleConnect, pending) =>
        current.copyWith(pendingBleConnect: null),
      PendingSerialOpen() when identical(current.pendingSerialOpen, pending) =>
        current.copyWith(pendingSerialOpen: null),
      PendingParticipantToolApproval()
          when identical(current.pendingParticipantToolApproval, pending) =>
        current.copyWith(pendingParticipantToolApproval: null),
      _ => current,
    };
  }

  bool get hasContent =>
      pendingWorkflowDecision != null ||
      isGeneratingWorkflowProposal ||
      workflowProposalDraft != null ||
      workflowProposalError != null ||
      isGeneratingTaskProposal ||
      taskProposalDraft != null ||
      taskProposalError != null ||
      pendingSshConnect != null ||
      pendingSshCommand != null ||
      pendingGitCommand != null ||
      pendingLocalCommand != null ||
      pendingComputerUseAction != null ||
      pendingBrowserAction != null ||
      pendingFileOperation != null ||
      pendingBleConnect != null ||
      pendingSerialOpen != null ||
      pendingParticipantToolApproval != null ||
      participantTurnRuntime != null;

  ChatState applyTo(
    ChatState state, {
    Set<String> approvalThreads = const <String>{},
  }) {
    return state.copyWith(
      approvalRequiredConversationIds: approvalThreads,
      pendingWorkflowDecision: pendingWorkflowDecision,
      isGeneratingWorkflowProposal: isGeneratingWorkflowProposal,
      workflowProposalDraft: workflowProposalDraft,
      workflowProposalError: workflowProposalError,
      isGeneratingTaskProposal: isGeneratingTaskProposal,
      taskProposalDraft: taskProposalDraft,
      taskProposalError: taskProposalError,
      pendingSshConnect: pendingSshConnect,
      pendingSshCommand: pendingSshCommand,
      pendingGitCommand: pendingGitCommand,
      pendingLocalCommand: pendingLocalCommand,
      pendingComputerUseAction: pendingComputerUseAction,
      pendingBrowserAction: pendingBrowserAction,
      pendingFileOperation: pendingFileOperation,
      pendingBleConnect: pendingBleConnect,
      pendingSerialOpen: pendingSerialOpen,
      pendingParticipantToolApproval: pendingParticipantToolApproval,
      participantTurnRuntime: participantTurnRuntime,
    );
  }
}
