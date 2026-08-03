import '../../../../core/types/workspace_mode.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/conversation.dart';
import '../entities/conversation_goal.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_goal_auto_continue_policy.dart';
import 'execution_snapshot_projector.dart';
import 'goal_auto_continue_tracker_registry.dart';
import 'short_prompt_contract_builder.dart';
import 'stalled_diagnostic_repair_contract.dart';
import 'tool_result_prompt_builder.dart';

// ChatNotifier decomposition collaborator: goal-auto-continue-decision-coordinator

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

final class GoalAutoContinueDecisionInput {
  const GoalAutoContinueDecisionInput({
    required this.owner,
    required this.ownerConversation,
    required this.tracker,
    required this.completionEvidence,
    required this.finalizedAssistantResponse,
    required this.safeBoundary,
    required this.isVoiceMode,
  });

  final ChatTurnOwner owner;
  final Conversation ownerConversation;
  final GoalAutoContinueTrackerSnapshot tracker;
  final ToolResultCompletionEvidence completionEvidence;
  final String finalizedAssistantResponse;
  final GoalAutoContinueSafeBoundary safeBoundary;
  final bool isVoiceMode;
}

final class GoalAutoContinueDecisionCoordinator {
  const GoalAutoContinueDecisionCoordinator();

  static const _policy = ConversationGoalAutoContinuePolicy();
  static const _projector = ExecutionSnapshotProjector();
  static const _repairContract = StalledDiagnosticRepairContract();
  static const _validationToolNames = <String>{
    'local_execute_command',
    'run_tests',
  };
  static const _repairToolNames = <String>{
    'read_file',
    'write_file',
    'edit_file',
    'delete_file',
  };

  GoalAutoContinueDecisionPlan coordinate(GoalAutoContinueDecisionInput input) {
    final conversation = input.ownerConversation;
    if (conversation.id != input.owner.conversationId) {
      return _veto(
        GoalAutoContinueCoordinationReasonCode.ownerConversationMismatch,
        'owner conversation does not match turn owner',
      );
    }
    if (conversation.workspaceMode != WorkspaceMode.coding) {
      return _veto(
        GoalAutoContinueCoordinationReasonCode.nonCodingWorkspace,
        'conversation is not in coding workspace',
      );
    }
    if (input.isVoiceMode) {
      return _veto(
        GoalAutoContinueCoordinationReasonCode.voiceModeActive,
        'voice mode is active',
      );
    }
    if (_savedWorkflowOwnsContinuation(conversation)) {
      return _veto(
        GoalAutoContinueCoordinationReasonCode.savedWorkflowOwnsContinuation,
        'saved workflow execution owns pending task continuation',
      );
    }

    final tracker = input.tracker;
    final evidence = input.completionEvidence;
    final candidateNoProgressStreak = _candidateProgressStreak(
      tracker,
      evidence,
    );
    final previousEvidence = tracker.previousEvidence;
    final diagnosticSignatureChanged =
        evidence.diagnosticSignature.isNotEmpty &&
        tracker.previousDiagnosticSignature.isNotEmpty &&
        evidence.diagnosticSignature != tracker.previousDiagnosticSignature;
    final postRepairVerifierAdvanced =
        tracker.pendingPostRepairReplayOutcome && diagnosticSignatureChanged;
    final candidateDiagnosticSignatureStreak = _repairContract
        .nextSignatureStreak(
          previousSignature: tracker.previousDiagnosticSignature,
          currentSignature: evidence.diagnosticSignature,
          currentStreak: tracker.identicalDiagnosticSignatureStreak,
        );
    final diagnosticEvidenceImproved =
        previousEvidence != null &&
        evidence.hasDiagnosticEvidence &&
        evidence.compareProgress(previousEvidence) ==
            GoalEvidenceProgress.improved;
    final verificationCadence =
        ExecutionSnapshotProjector.verificationCadenceFor(conversation);
    var consecutiveValidationMisses = tracker.consecutiveValidationMisses;
    var failedVerificationObserved = tracker.failedVerificationObserved;
    if (evidence.hasExecutionVerification) {
      consecutiveValidationMisses = 0;
      failedVerificationObserved = !evidence.hasSuccessfulExecutionVerification;
    }
    final policyInput = GoalAutoContinuePolicyInput(
      goal: conversation.goal,
      safeBoundary: input.safeBoundary,
      evidence: evidence,
      consecutiveAutoContinuations: tracker.consecutiveAutoContinuations,
      diagnosticRepairContinuations: tracker.diagnosticRepairContinuations,
      diagnosticRepairExtensionUsed: tracker.diagnosticRepairExtensionUsed,
      diagnosticEvidenceImproved: diagnosticEvidenceImproved,
      postRepairVerifierAdvanced: postRepairVerifierAdvanced,
      repairContractProducedNoMutation: tracker.pendingRepairContractOutcome,
      repairNoMutationRetryUsed: tracker.repairNoMutationRetryUsed,
      consecutiveValidationMisses: consecutiveValidationMisses,
      failedVerificationObserved: failedVerificationObserved,
      noProgressStreak: candidateNoProgressStreak,
      identicalDiagnosticSignatureStreak: candidateDiagnosticSignatureStreak,
      finalAnswerEndsWithQuestion: _endsWithQuestionMark(
        input.finalizedAssistantResponse,
      ),
      verificationCadence: verificationCadence,
    );
    final decision = _policy.decide(policyInput);
    final effectiveTurnBudget = _effectiveTurnBudget(conversation);

    if (!decision.shouldContinue) {
      final stopNotice = _stopNotice(decision, tracker);
      final elicitation = _elicitation(input, decision);
      return (
        policyDecision: decision,
        policyInput: policyInput,
        trackerDelta: _trackerDelta(
          input: input,
          policyInput: policyInput,
          decision: decision,
          candidateNoProgressStreak: candidateNoProgressStreak,
          candidateDiagnosticSignatureStreak:
              candidateDiagnosticSignatureStreak,
          failedVerificationObserved: failedVerificationObserved,
          consecutiveValidationMisses: consecutiveValidationMisses,
          repairContract: null,
          completionElicitationMutationGeneration:
              elicitation.mutationGeneration,
          markBudgetNoticePresented: stopNotice != null,
        ),
        executionSnapshot: null,
        repairContract: null,
        capabilityProfile: null,
        continuationLimits: null,
        stopNotice: stopNotice,
        elicitationEligibility: elicitation.eligibility,
        shouldMarkAwaitingConfirmation: elicitation.markAwaitingConfirmation,
        effectiveTurnBudget: effectiveTurnBudget,
        reason: (
          code: decision.shouldBlock
              ? GoalAutoContinueCoordinationReasonCode.policyStopAndBlock
              : GoalAutoContinueCoordinationReasonCode.policySkip,
          detail: decision.reason,
        ),
      );
    }

    final executionSnapshot = _projector.project(conversation);
    final repairContract = _repairContract.build(
      evidence: evidence,
      executionSnapshot: executionSnapshot,
      noProgressStreak: tracker.verifierReplayCandidate == null
          ? 0
          : candidateDiagnosticSignatureStreak,
    );
    final capabilityProfile = _policy.selectCapabilityProfile(
      evidence: evidence,
      hasRepairContract: repairContract != null,
    );
    final continuationLimits = _continuationLimits(
      decision,
      capabilityProfile,
      hasRepairContract: repairContract != null,
    );
    return (
      policyDecision: decision,
      policyInput: policyInput,
      trackerDelta: _trackerDelta(
        input: input,
        policyInput: policyInput,
        decision: decision,
        candidateNoProgressStreak: candidateNoProgressStreak,
        candidateDiagnosticSignatureStreak: candidateDiagnosticSignatureStreak,
        failedVerificationObserved: failedVerificationObserved,
        consecutiveValidationMisses: consecutiveValidationMisses,
        repairContract: repairContract,
        completionElicitationMutationGeneration: null,
        markBudgetNoticePresented: false,
      ),
      executionSnapshot: executionSnapshot,
      repairContract: repairContract,
      capabilityProfile: capabilityProfile,
      continuationLimits: continuationLimits,
      stopNotice: null,
      elicitationEligibility:
          GoalCompletionElicitationEligibility.notApplicable,
      shouldMarkAwaitingConfirmation: false,
      effectiveTurnBudget: effectiveTurnBudget,
      reason: (
        code: GoalAutoContinueCoordinationReasonCode.policyContinue,
        detail: decision.reason,
      ),
    );
  }

  GoalAutoContinueDecisionPlan _veto(
    GoalAutoContinueCoordinationReasonCode code,
    String detail,
  ) {
    return (
      policyDecision: GoalAutoContinueDecision.skip(detail),
      policyInput: null,
      trackerDelta: _emptyTrackerDelta(),
      executionSnapshot: null,
      repairContract: null,
      capabilityProfile: null,
      continuationLimits: null,
      stopNotice: null,
      elicitationEligibility:
          GoalCompletionElicitationEligibility.notApplicable,
      shouldMarkAwaitingConfirmation: false,
      effectiveTurnBudget: null,
      reason: (code: code, detail: detail),
    );
  }
}

GoalAutoContinueContinuationLimits _continuationLimits(
  GoalAutoContinueDecision decision,
  GoalAutoContinueCapabilityProfile capabilityProfile, {
  required bool hasRepairContract,
}) {
  return (
    nextTurnNumber: decision.nextTurnNumber,
    effectiveTurnBudget: decision.effectiveTurnBudget,
    allowedToolNames: switch (capabilityProfile) {
      GoalAutoContinueCapabilityProfile.repair =>
        GoalAutoContinueDecisionCoordinator._repairToolNames,
      GoalAutoContinueCapabilityProfile.validation =>
        GoalAutoContinueDecisionCoordinator._validationToolNames,
      GoalAutoContinueCapabilityProfile.unrestricted => null,
    },
    replayVerifierImmediatelyAfterMutation: hasRepairContract,
    verifierOnlyContinuation:
        capabilityProfile == GoalAutoContinueCapabilityProfile.validation,
  );
}

bool _savedWorkflowOwnsContinuation(Conversation conversation) {
  final taskViews = conversation.executionTaskViews;
  return taskViews.isNotEmpty &&
      !ShortPromptContractBuilder.isSyntheticRequestContract(
        conversation.effectiveWorkflowSpec,
      ) &&
      taskViews.any(
        (view) => view.status != ConversationWorkflowTaskStatus.completed,
      );
}

int _candidateProgressStreak(
  GoalAutoContinueTrackerSnapshot tracker,
  ToolResultCompletionEvidence evidence,
) {
  final previousEvidence = tracker.previousEvidence;
  if (previousEvidence == null || !evidence.hasIncompleteEvidence) {
    return tracker.noProgressStreak;
  }
  return evidence.compareProgress(previousEvidence) ==
          GoalEvidenceProgress.improved
      ? 0
      : tracker.noProgressStreak + 1;
}

bool _endsWithQuestionMark(String content) =>
    content.trimRight().endsWith('?') || content.trimRight().endsWith('？');

int? _effectiveTurnBudget(Conversation conversation) =>
    conversation.goal == null
    ? null
    : conversation.goal!.hasTurnBudget
    ? conversation.goal!.turnBudget
    : kGoalAutoContinueDefaultTurnBudget;

String? _stopNotice(
  GoalAutoContinueDecision decision,
  GoalAutoContinueTrackerSnapshot tracker,
) {
  final key = GoalAutoContinueStopPresentation.noticeKeyFor(decision.stopCause);
  if (key == null || tracker.budgetNoticePresented) {
    return null;
  }
  return key;
}

({
  GoalCompletionElicitationEligibility eligibility,
  int? mutationGeneration,
  bool markAwaitingConfirmation,
})
_elicitation(
  GoalAutoContinueDecisionInput input,
  GoalAutoContinueDecision decision,
) {
  if (!decision.noRemainingWork) {
    return (
      eligibility: GoalCompletionElicitationEligibility.notApplicable,
      mutationGeneration: null,
      markAwaitingConfirmation: false,
    );
  }
  final conversation = input.ownerConversation;
  final goal = conversation.goal;
  if (goal?.status != ConversationGoalStatus.active) {
    return (
      eligibility: GoalCompletionElicitationEligibility.goalStatusNotActive,
      mutationGeneration: null,
      markAwaitingConfirmation: false,
    );
  }
  if (conversation.mutationGeneration <= 0) {
    return (
      eligibility: GoalCompletionElicitationEligibility.noProducedWork,
      mutationGeneration: null,
      markAwaitingConfirmation: true,
    );
  }
  final lastElicitation = input.tracker.completionElicitationMutationGeneration;
  if (lastElicitation != null &&
      lastElicitation >= conversation.mutationGeneration) {
    return (
      eligibility: GoalCompletionElicitationEligibility.alreadySpentForMutation,
      mutationGeneration: null,
      markAwaitingConfirmation: true,
    );
  }
  return (
    eligibility: GoalCompletionElicitationEligibility.eligible,
    mutationGeneration: conversation.mutationGeneration,
    markAwaitingConfirmation: false,
  );
}

GoalAutoContinueTrackerDelta _trackerDelta({
  required GoalAutoContinueDecisionInput input,
  required GoalAutoContinuePolicyInput policyInput,
  required GoalAutoContinueDecision decision,
  required int candidateNoProgressStreak,
  required int candidateDiagnosticSignatureStreak,
  required bool failedVerificationObserved,
  required int consecutiveValidationMisses,
  required String? repairContract,
  required int? completionElicitationMutationGeneration,
  required bool markBudgetNoticePresented,
}) {
  final continues = decision.shouldContinue;
  var resultingValidationMisses = consecutiveValidationMisses;
  if (continues && policyInput.validationOutstanding) {
    resultingValidationMisses += 1;
  }
  final updateValidation =
      input.completionEvidence.hasExecutionVerification ||
      (continues && policyInput.validationOutstanding);
  final updateNoProgress =
      continues ||
      decision.shouldBlock ||
      decision.stopCause == GoalAutoContinueStopCause.noProgress;
  return (
    consecutiveAutoContinuationsDelta: continues ? 1 : 0,
    diagnosticRepairContinuationsDelta:
        continues && input.completionEvidence.hasDiagnosticEvidence ? 1 : 0,
    diagnosticRepairExtensionUsed: decision.usesDiagnosticRepairExtension
        ? true
        : null,
    noProgressStreak: updateNoProgress ? candidateNoProgressStreak : null,
    consecutiveValidationMisses: updateValidation
        ? resultingValidationMisses
        : null,
    failedVerificationObserved:
        input.completionEvidence.hasExecutionVerification
        ? failedVerificationObserved
        : null,
    previousEvidence: continues ? input.completionEvidence : null,
    previousDiagnosticSignature: continues
        ? input.completionEvidence.diagnosticSignature
        : null,
    identicalDiagnosticSignatureStreak: continues
        ? candidateDiagnosticSignatureStreak
        : null,
    pendingPostRepairReplayOutcome: false,
    pendingRepairContractOutcome: continues ? repairContract != null : false,
    repairNoMutationRetryUsed: decision.usesRepairNoMutationRetry ? true : null,
    completionElicitationMutationGeneration:
        completionElicitationMutationGeneration,
    markBudgetNoticePresented: markBudgetNoticePresented,
    removeTracker: decision.shouldBlock,
  );
}

GoalAutoContinueTrackerDelta _emptyTrackerDelta() {
  return (
    consecutiveAutoContinuationsDelta: 0,
    diagnosticRepairContinuationsDelta: 0,
    diagnosticRepairExtensionUsed: null,
    noProgressStreak: null,
    consecutiveValidationMisses: null,
    failedVerificationObserved: null,
    previousEvidence: null,
    previousDiagnosticSignature: null,
    identicalDiagnosticSignatureStreak: null,
    pendingPostRepairReplayOutcome: null,
    pendingRepairContractOutcome: null,
    repairNoMutationRetryUsed: null,
    completionElicitationMutationGeneration: null,
    markBudgetNoticePresented: false,
    removeTracker: false,
  );
}
