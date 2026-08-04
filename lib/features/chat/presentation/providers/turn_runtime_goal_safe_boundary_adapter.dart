import '../../application/runtime/turn_runtime.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/goal_auto_continue_safe_boundary_builder.dart';
import 'chat_state.dart';
import 'thread_scoped_chat_state.dart';
import 'thread_scoped_message_queue.dart';

/// Captures the presentation-owned blockers for goal continuation.
final class TurnRuntimeGoalSafeBoundaryAdapter
    implements TurnRuntimeGoalSafeBoundaryPort {
  TurnRuntimeGoalSafeBoundaryAdapter({
    required TurnRuntimeOwnerLeasePort ownerLease,
    required ThreadScopedMessageQueue queuedMessages,
    required Map<String, ThreadScopedChatState> threadStates,
    required Map<String, PendingAskUserQuestion> pendingQuestions,
  }) : _ownerLease = ownerLease,
       _queuedMessages = queuedMessages,
       _threadStates = threadStates,
       _pendingQuestions = pendingQuestions;

  final TurnRuntimeOwnerLeasePort _ownerLease;
  final ThreadScopedMessageQueue _queuedMessages;
  final Map<String, ThreadScopedChatState> _threadStates;
  final Map<String, PendingAskUserQuestion> _pendingQuestions;
  ThreadScopedChatState _visibleThreadState = ThreadScopedChatState.empty;
  bool _visibleIsLoading = false;
  String? _visibleError;

  void synchronizeVisibleState(
    ThreadScopedChatState threadState, {
    required bool isLoading,
    required String? error,
  }) {
    _visibleThreadState = threadState;
    _visibleIsLoading = isLoading;
    _visibleError = error;
  }

  @override
  GoalAutoContinueSafeBoundary capture(ChatTurnOwner owner) {
    final ownerIsVisible = _ownerLease.isCurrent(owner);
    final threadState = ownerIsVisible
        ? _visibleThreadState
        : _threadStates[owner.conversationId] ?? ThreadScopedChatState.empty;
    bool owns(PendingToolApproval<dynamic>? approval) =>
        approval?.owner == owner;
    return const GoalAutoContinueSafeBoundaryBuilder().build(
      GoalAutoContinuePendingState(
        owner: owner,
        isLoading: ownerIsVisible && _visibleIsLoading,
        queuedUserInputCount: _queuedMessages.pendingFor(owner.conversationId),
        hasPendingSshConnect: owns(threadState.pendingSshConnect),
        hasPendingSshCommand: owns(threadState.pendingSshCommand),
        hasPendingGitCommand: owns(threadState.pendingGitCommand),
        hasPendingLocalCommand: owns(threadState.pendingLocalCommand),
        hasPendingComputerUseAction: owns(threadState.pendingComputerUseAction),
        hasPendingBrowserAction: owns(threadState.pendingBrowserAction),
        hasPendingFileOperation: owns(threadState.pendingFileOperation),
        hasPendingBleConnect: owns(threadState.pendingBleConnect),
        hasPendingSerialOpen: owns(threadState.pendingSerialOpen),
        hasPendingParticipantToolApproval: owns(
          threadState.pendingParticipantToolApproval,
        ),
        hasPendingAskUserQuestion: _pendingQuestions.containsKey(
          owner.conversationId,
        ),
        hasPendingWorkflowDecision: threadState.pendingWorkflowDecision != null,
        hasParticipantTurnRuntime: threadState.participantTurnRuntime != null,
        error: ownerIsVisible ? _visibleError : null,
      ),
    );
  }
}
