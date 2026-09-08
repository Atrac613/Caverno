import 'conversation_goal_auto_continue_policy.dart';
import 'execution_snapshot_projector.dart';
import 'tool_result_prompt_builder.dart';

enum GoalAutoContinueCoordinationReasonCode {
  ownerConversationMismatch,
  nonCodingWorkspace,
  voiceModeActive,
  savedWorkflowOwnsContinuation,
  policyContinue,
  policySkip,
  policyStopAndBlock,
}

enum GoalCompletionElicitationEligibility {
  notApplicable,
  goalStatusNotActive,
  noProducedWork,
  alreadySpentForMutation,
  eligible,
}

typedef GoalAutoContinueStructuredReason = ({
  GoalAutoContinueCoordinationReasonCode code,
  String detail,
});

typedef GoalAutoContinueContinuationLimits = ({
  int nextTurnNumber,
  int effectiveTurnBudget,
  Set<String>? allowedToolNames,
  bool replayVerifierImmediatelyAfterMutation,
  bool verifierOnlyContinuation,
});

typedef GoalAutoContinueTrackerDelta = ({
  int consecutiveAutoContinuationsDelta,
  int diagnosticRepairContinuationsDelta,
  bool? diagnosticRepairExtensionUsed,
  int? noProgressStreak,
  int? consecutiveValidationMisses,
  bool? failedVerificationObserved,
  ToolResultCompletionEvidence? previousEvidence,
  String? previousDiagnosticSignature,
  int? identicalDiagnosticSignatureStreak,
  bool? pendingPostRepairReplayOutcome,
  bool? pendingRepairContractOutcome,
  bool? repairNoMutationRetryUsed,
  int? completionElicitationMutationGeneration,
  bool markBudgetNoticePresented,
  bool removeTracker,
});

typedef GoalAutoContinueDecisionPlan = ({
  GoalAutoContinueDecision policyDecision,
  GoalAutoContinuePolicyInput? policyInput,
  GoalAutoContinueTrackerDelta trackerDelta,
  ExecutionSnapshot? executionSnapshot,
  String? repairContract,
  GoalAutoContinueCapabilityProfile? capabilityProfile,
  GoalAutoContinueContinuationLimits? continuationLimits,
  String? stopNotice,
  GoalCompletionElicitationEligibility elicitationEligibility,
  bool shouldMarkAwaitingConfirmation,
  int? effectiveTurnBudget,
  GoalAutoContinueStructuredReason reason,
});
