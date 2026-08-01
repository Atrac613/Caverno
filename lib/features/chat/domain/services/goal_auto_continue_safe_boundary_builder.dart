import '../entities/chat_turn_owner.dart';
import 'conversation_goal_auto_continue_policy.dart';

// ChatNotifier decomposition collaborator: goal-auto-continue-safe-boundary-builder

/// Owner-specific pending state used to decide whether continuation is safe.
final class GoalAutoContinuePendingState {
  const GoalAutoContinuePendingState({
    required this.owner,
    required this.isLoading,
    required this.queuedUserInputCount,
    required this.hasPendingSshConnect,
    required this.hasPendingSshCommand,
    required this.hasPendingGitCommand,
    required this.hasPendingLocalCommand,
    required this.hasPendingComputerUseAction,
    required this.hasPendingBrowserAction,
    required this.hasPendingFileOperation,
    required this.hasPendingBleConnect,
    required this.hasPendingSerialOpen,
    required this.hasPendingParticipantToolApproval,
    required this.hasPendingAskUserQuestion,
    required this.hasPendingWorkflowDecision,
    required this.hasParticipantTurnRuntime,
    required this.error,
  });

  final ChatTurnOwner owner;
  final bool isLoading;
  final int queuedUserInputCount;
  final bool hasPendingSshConnect;
  final bool hasPendingSshCommand;
  final bool hasPendingGitCommand;
  final bool hasPendingLocalCommand;
  final bool hasPendingComputerUseAction;
  final bool hasPendingBrowserAction;
  final bool hasPendingFileOperation;
  final bool hasPendingBleConnect;
  final bool hasPendingSerialOpen;
  final bool hasPendingParticipantToolApproval;
  final bool hasPendingAskUserQuestion;
  final bool hasPendingWorkflowDecision;
  final bool hasParticipantTurnRuntime;
  final String? error;
}

/// Projects immutable owner state into the existing continuation veto policy.
final class GoalAutoContinueSafeBoundaryBuilder {
  const GoalAutoContinueSafeBoundaryBuilder();

  GoalAutoContinueSafeBoundary build(GoalAutoContinuePendingState state) {
    return GoalAutoContinueSafeBoundary(
      isLoading: state.isLoading,
      hasQueuedUserInput: state.queuedUserInputCount > 0,
      hasPendingSshConnect: state.hasPendingSshConnect,
      hasPendingSshCommand: state.hasPendingSshCommand,
      hasPendingGitCommand: state.hasPendingGitCommand,
      hasPendingLocalCommand: state.hasPendingLocalCommand,
      hasPendingComputerUseAction: state.hasPendingComputerUseAction,
      hasPendingBrowserAction: state.hasPendingBrowserAction,
      hasPendingFileOperation: state.hasPendingFileOperation,
      hasPendingBleConnect: state.hasPendingBleConnect,
      hasPendingSerialOpen: state.hasPendingSerialOpen,
      hasPendingParticipantToolApproval:
          state.hasPendingParticipantToolApproval,
      hasPendingAskUserQuestion: state.hasPendingAskUserQuestion,
      hasPendingWorkflowDecision: state.hasPendingWorkflowDecision,
      hasParticipantTurnRuntime: state.hasParticipantTurnRuntime,
      hasError: state.error?.trim().isNotEmpty ?? false,
    );
  }
}
