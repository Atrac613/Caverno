import '../entities/conversation_goal.dart';
import 'tool_result_prompt_builder.dart';

const int kGoalAutoContinueDefaultTurnBudget = 10;
const int kGoalAutoContinueDiagnosticRepairBudget = 2;

enum GoalAutoContinueDecisionKind { continueTurn, skip, stopAndBlock }

enum GoalAutoContinueStopCause { turnBudget, goalBudget, noProgress }

class GoalAutoContinueSafeBoundary {
  const GoalAutoContinueSafeBoundary({
    required this.isLoading,
    required this.hasQueuedUserInput,
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
    required this.hasError,
  });

  final bool isLoading;
  final bool hasQueuedUserInput;
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
  final bool hasError;

  String? get firstVetoReason {
    if (isLoading) return 'response still loading';
    if (hasQueuedUserInput) return 'queued user input is waiting';
    if (hasPendingSshConnect) return 'SSH connection approval is pending';
    if (hasPendingSshCommand) return 'SSH command approval is pending';
    if (hasPendingGitCommand) return 'git command approval is pending';
    if (hasPendingLocalCommand) return 'local command approval is pending';
    if (hasPendingComputerUseAction) {
      return 'computer-use approval is pending';
    }
    if (hasPendingBrowserAction) return 'browser action approval is pending';
    if (hasPendingFileOperation) return 'file operation approval is pending';
    if (hasPendingBleConnect) return 'BLE connection approval is pending';
    if (hasPendingSerialOpen) return 'serial port approval is pending';
    if (hasPendingParticipantToolApproval) {
      return 'participant tool approval is pending';
    }
    if (hasPendingAskUserQuestion) return 'assistant question is pending';
    if (hasPendingWorkflowDecision) return 'workflow decision is pending';
    if (hasParticipantTurnRuntime) return 'participant turn is active';
    if (hasError) return 'chat state has an error';
    return null;
  }

  bool get isSafe => firstVetoReason == null;
}

class GoalAutoContinuePolicyInput {
  const GoalAutoContinuePolicyInput({
    required this.goal,
    required this.safeBoundary,
    required this.evidence,
    required this.consecutiveAutoContinuations,
    required this.diagnosticRepairContinuations,
    required this.diagnosticRepairExtensionUsed,
    required this.diagnosticEvidenceImproved,
    required this.validationContinuations,
    required this.noProgressStreak,
    required this.finalAnswerEndsWithQuestion,
  });

  final ConversationGoal? goal;
  final GoalAutoContinueSafeBoundary safeBoundary;
  final ToolResultCompletionEvidence evidence;
  final int consecutiveAutoContinuations;
  final int diagnosticRepairContinuations;
  final bool diagnosticRepairExtensionUsed;
  final bool diagnosticEvidenceImproved;
  final int validationContinuations;
  final int noProgressStreak;
  final bool finalAnswerEndsWithQuestion;
}

class GoalAutoContinueDecision {
  const GoalAutoContinueDecision._({
    required this.kind,
    required this.reason,
    this.effectiveTurnBudget = kGoalAutoContinueDefaultTurnBudget,
    this.nextTurnNumber = 0,
    this.blockedReason,
    this.stopCause,
    this.usesDiagnosticRepairExtension = false,
  });

  final GoalAutoContinueDecisionKind kind;
  final String reason;
  final int effectiveTurnBudget;
  final int nextTurnNumber;
  final String? blockedReason;
  final GoalAutoContinueStopCause? stopCause;
  final bool usesDiagnosticRepairExtension;

  bool get shouldContinue => kind == GoalAutoContinueDecisionKind.continueTurn;

  bool get shouldBlock => kind == GoalAutoContinueDecisionKind.stopAndBlock;

  factory GoalAutoContinueDecision.continueTurn({
    required String reason,
    required int effectiveTurnBudget,
    required int nextTurnNumber,
    bool usesDiagnosticRepairExtension = false,
  }) {
    return GoalAutoContinueDecision._(
      kind: GoalAutoContinueDecisionKind.continueTurn,
      reason: reason,
      effectiveTurnBudget: effectiveTurnBudget,
      nextTurnNumber: nextTurnNumber,
      usesDiagnosticRepairExtension: usesDiagnosticRepairExtension,
    );
  }

  factory GoalAutoContinueDecision.skip(
    String reason, {
    GoalAutoContinueStopCause? stopCause,
  }) {
    return GoalAutoContinueDecision._(
      kind: GoalAutoContinueDecisionKind.skip,
      reason: reason,
      stopCause: stopCause,
    );
  }

  factory GoalAutoContinueDecision.stopAndBlock({
    required String reason,
    required String blockedReason,
  }) {
    return GoalAutoContinueDecision._(
      kind: GoalAutoContinueDecisionKind.stopAndBlock,
      reason: reason,
      blockedReason: blockedReason,
    );
  }
}

class ConversationGoalAutoContinuePolicy {
  const ConversationGoalAutoContinuePolicy();

  GoalAutoContinueDecision decide(GoalAutoContinuePolicyInput input) {
    final goal = input.goal;
    if (goal == null || !goal.isActive) {
      return GoalAutoContinueDecision.skip('goal is not active');
    }
    if (!goal.autoContinue) {
      return GoalAutoContinueDecision.skip('auto-continue is disabled');
    }
    if (goal.tokenBudgetExceeded) {
      return GoalAutoContinueDecision.skip(
        'goal budget is exhausted',
        stopCause: GoalAutoContinueStopCause.goalBudget,
      );
    }

    final effectiveTurnBudget = goal.hasTurnBudget
        ? goal.turnBudget
        : kGoalAutoContinueDefaultTurnBudget;
    if (goal.turnBudgetExceeded || goal.turnsUsed >= effectiveTurnBudget) {
      return GoalAutoContinueDecision.skip(
        'auto-continue turn budget reached',
        stopCause: GoalAutoContinueStopCause.turnBudget,
      );
    }

    final boundaryVeto = input.safeBoundary.firstVetoReason;
    if (boundaryVeto != null) {
      return GoalAutoContinueDecision.skip(boundaryVeto);
    }
    if (input.finalAnswerEndsWithQuestion) {
      return GoalAutoContinueDecision.skip('final answer asks a question');
    }
    if (!input.evidence.hasIncompleteEvidence) {
      return GoalAutoContinueDecision.skip('no incomplete evidence');
    }

    if (input.evidence.requiresValidationContinuation) {
      if (input.validationContinuations == 0) {
        return GoalAutoContinueDecision.continueTurn(
          reason: input.evidence.hasPendingExecutionVerification
              ? 'execute the pending verification call'
              : 'validate file changes before further editing',
          effectiveTurnBudget: effectiveTurnBudget,
          nextTurnNumber: goal.turnsUsed + 1,
        );
      }
      if (input.validationContinuations == 1 &&
          (input.evidence.hasUnexecutedActionClaim ||
              (input.evidence.hasExecutionVerification &&
                  input.evidence.mutatedWithoutExecutionVerification))) {
        return GoalAutoContinueDecision.continueTurn(
          reason: input.evidence.hasUnexecutedActionClaim
              ? 'retry the unexecuted validation action'
              : 'validate the repair made after failed verification',
          effectiveTurnBudget: effectiveTurnBudget,
          nextTurnNumber: goal.turnsUsed + 1,
        );
      }
      return GoalAutoContinueDecision.stopAndBlock(
        reason: 'validation continuation was ignored',
        blockedReason:
            'Goal auto-continue stopped because execution verification '
            'remained incomplete after a dedicated validation turn.',
      );
    }

    if (input.noProgressStreak >= 2) {
      if (input.evidence.hasDiagnosticEvidence) {
        return GoalAutoContinueDecision.stopAndBlock(
          reason: 'diagnostic evidence stalled',
          blockedReason:
              'Goal auto-continue stopped because two consecutive continued turns made no diagnostic progress.',
        );
      }
      return GoalAutoContinueDecision.skip(
        'no measurable progress',
        stopCause: GoalAutoContinueStopCause.noProgress,
      );
    }

    if (input.evidence.hasDiagnosticEvidence &&
        input.diagnosticRepairContinuations >=
            kGoalAutoContinueDiagnosticRepairBudget) {
      if (input.diagnosticEvidenceImproved &&
          !input.diagnosticRepairExtensionUsed) {
        return GoalAutoContinueDecision.continueTurn(
          reason: 'diagnostics improved; one repair extension granted',
          effectiveTurnBudget: effectiveTurnBudget,
          nextTurnNumber: goal.turnsUsed + 1,
          usesDiagnosticRepairExtension: true,
        );
      }
      return GoalAutoContinueDecision.stopAndBlock(
        reason: 'diagnostic repair continuation budget reached',
        blockedReason:
            'Goal auto-continue stopped because diagnostics remained after '
            '$kGoalAutoContinueDiagnosticRepairBudget continued repair turns'
            '${input.diagnosticRepairExtensionUsed ? ' and one progress-based extension' : ''}.',
      );
    }

    return GoalAutoContinueDecision.continueTurn(
      reason: 'incomplete evidence remains',
      effectiveTurnBudget: effectiveTurnBudget,
      nextTurnNumber: goal.turnsUsed + 1,
    );
  }
}
