import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/goal_auto_continue_decision_coordinator.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';
import '../../domain/services/goal_completion_elicitation_prompt.dart';
import '../../domain/services/goal_continuation_log_record_builder.dart';
import '../../domain/services/tool_result_prompt_builder.dart';

/// Owner-aware access to the current turn lifecycle.
abstract interface class TurnRuntimeOwnerLeasePort {
  bool isCurrent(ChatTurnOwner owner);
}

/// Owner-aware access to conversation goal state and persistence.
abstract interface class TurnRuntimeConversationGoalPort {
  Conversation? conversationFor(ChatTurnOwner owner);

  Future<void> markGoalStatus(TurnRuntimeGoalStatusUpdate update);
}

/// Conversation-spanning continuation history used by one turn runtime.
abstract interface class TurnRuntimeGoalTrackerPort {
  GoalAutoContinueTrackerSnapshot snapshotFor(ChatTurnOwner owner);

  GoalAutoContinueTrackerSnapshot applyDelta(
    ChatTurnOwner owner,
    GoalAutoContinueTrackerDelta delta,
  );

  bool markBudgetNoticePresented(ChatTurnOwner owner);

  GoalAutoContinueTrackerSnapshot clearPendingRepairContract(
    ChatTurnOwner owner,
  );

  void removeTracker(ChatTurnOwner owner);
}

/// Captures pending thread state as one immutable continuation boundary.
abstract interface class TurnRuntimeGoalSafeBoundaryPort {
  GoalAutoContinueSafeBoundary capture(ChatTurnOwner owner);
}

/// Persists a fully projected continuation record outside the runtime.
abstract interface class TurnRuntimeGoalContinuationLogPort {
  Future<void> record(GoalAutoContinueLogRecord record);
}

/// The five longer-lived capabilities available to goal continuation.
final class TurnRuntimeGoalContinuationPorts {
  const TurnRuntimeGoalContinuationPorts({
    required this.ownerLease,
    required this.conversationGoal,
    required this.tracker,
    required this.safeBoundary,
    required this.log,
  });

  final TurnRuntimeOwnerLeasePort ownerLease;
  final TurnRuntimeConversationGoalPort conversationGoal;
  final TurnRuntimeGoalTrackerPort tracker;
  final TurnRuntimeGoalSafeBoundaryPort safeBoundary;
  final TurnRuntimeGoalContinuationLogPort log;
}

/// Immutable policy input for goal continuation within the runtime's owner.
final class TurnRuntimeGoalContinuationInput {
  TurnRuntimeGoalContinuationInput({
    required this.finalizedAssistantResponse,
    required this.languageCode,
    required ToolResultCompletionEvidence evidence,
    required this.isVoiceMode,
  }) : evidence = _copyEvidence(evidence);

  final String finalizedAssistantResponse;
  final String languageCode;
  final ToolResultCompletionEvidence evidence;
  final bool isVoiceMode;
}

/// Exact goal status mutation requested by a runtime owner.
final class TurnRuntimeGoalStatusUpdate {
  const TurnRuntimeGoalStatusUpdate({
    required this.owner,
    required this.status,
    this.blockedReason,
  });

  final ChatTurnOwner owner;
  final ConversationGoalStatus status;
  final String? blockedReason;
}

/// Owner-bound UI projection returned to the presentation wrapper.
sealed class TurnRuntimeGoalUiEffect {
  const TurnRuntimeGoalUiEffect({required this.owner});

  final ChatTurnOwner owner;
}

final class TurnRuntimeClearGoalIndicator extends TurnRuntimeGoalUiEffect {
  const TurnRuntimeClearGoalIndicator({required super.owner});
}

final class TurnRuntimeShowGoalProgress extends TurnRuntimeGoalUiEffect {
  const TurnRuntimeShowGoalProgress({
    required super.owner,
    required this.count,
    required this.budget,
  });

  final int count;
  final int budget;
}

final class TurnRuntimeShowGoalNotice extends TurnRuntimeGoalUiEffect {
  const TurnRuntimeShowGoalNotice({
    required super.owner,
    required this.noticeKey,
  });

  final String noticeKey;
}

enum TurnRuntimeHiddenTurnKind { continuation, completionElicitation }

/// Owner-bound hidden turn returned to the presentation wrapper for dispatch.
final class TurnRuntimeHiddenTurnRequest {
  TurnRuntimeHiddenTurnRequest({
    required this.owner,
    required this.kind,
    required this.prompt,
    required this.languageCode,
    required ToolResultCompletionEvidence evidence,
    this.replayVerifierImmediatelyAfterMutation = false,
    this.verifierOnlyContinuation = false,
    Set<String>? allowedToolNames,
  }) : evidence = _copyEvidence(evidence),
       allowedToolNames = allowedToolNames == null
           ? null
           : Set<String>.unmodifiable(allowedToolNames);

  final ChatTurnOwner owner;
  final TurnRuntimeHiddenTurnKind kind;
  final String prompt;
  final String languageCode;
  final ToolResultCompletionEvidence evidence;
  final bool replayVerifierImmediatelyAfterMutation;
  final bool verifierOnlyContinuation;
  final Set<String>? allowedToolNames;
}

/// Owner-bound effects required to dispatch one goal continuation.
final class TurnRuntimeGoalContinuationDispatch {
  const TurnRuntimeGoalContinuationDispatch({
    required this.uiEffect,
    required this.hiddenTurn,
  });

  final TurnRuntimeShowGoalProgress uiEffect;
  final TurnRuntimeHiddenTurnRequest hiddenTurn;
}

/// Owner-bound effects required to elicit one goal completion report.
final class TurnRuntimeGoalCompletionElicitationDispatch {
  const TurnRuntimeGoalCompletionElicitationDispatch({
    required this.uiEffect,
    required this.hiddenTurn,
  });

  final TurnRuntimeClearGoalIndicator uiEffect;
  final TurnRuntimeHiddenTurnRequest hiddenTurn;
}

/// Turn-lifetime owner and state for the bounded production prototype.
final class TurnRuntime {
  TurnRuntime({required this.owner, required this.goalContinuation});

  final ChatTurnOwner owner;
  final TurnRuntimeGoalContinuationPorts goalContinuation;
  bool _isSchedulingGoalContinuation = false;

  bool get isSchedulingGoalContinuation => _isSchedulingGoalContinuation;

  bool beginGoalContinuationScheduling() {
    if (_isSchedulingGoalContinuation) {
      return false;
    }
    _isSchedulingGoalContinuation = true;
    return true;
  }

  TurnRuntimeClearGoalIndicator clearGoalIndicator() =>
      TurnRuntimeClearGoalIndicator(owner: owner);

  TurnRuntimeShowGoalNotice showGoalNotice(String noticeKey) =>
      TurnRuntimeShowGoalNotice(owner: owner, noticeKey: noticeKey);

  TurnRuntimeGoalCompletionElicitationDispatch
  goalCompletionElicitationDispatch({
    required String languageCode,
    required ToolResultCompletionEvidence evidence,
  }) => TurnRuntimeGoalCompletionElicitationDispatch(
    uiEffect: clearGoalIndicator(),
    hiddenTurn: TurnRuntimeHiddenTurnRequest(
      owner: owner,
      kind: TurnRuntimeHiddenTurnKind.completionElicitation,
      prompt: GoalCompletionElicitationPrompt.build(languageCode: languageCode),
      languageCode: languageCode,
      evidence: evidence,
      allowedToolNames: const {'update_goal'},
    ),
  );

  TurnRuntimeGoalContinuationDispatch? beginGoalContinuationDispatch({
    required String prompt,
    required String languageCode,
    required ToolResultCompletionEvidence evidence,
    required int count,
    required int budget,
    required bool replayVerifierImmediatelyAfterMutation,
    required bool verifierOnlyContinuation,
    Set<String>? allowedToolNames,
  }) {
    if (!beginGoalContinuationScheduling()) {
      return null;
    }
    return TurnRuntimeGoalContinuationDispatch(
      uiEffect: TurnRuntimeShowGoalProgress(
        owner: owner,
        count: count,
        budget: budget,
      ),
      hiddenTurn: TurnRuntimeHiddenTurnRequest(
        owner: owner,
        kind: TurnRuntimeHiddenTurnKind.continuation,
        prompt: prompt,
        languageCode: languageCode,
        evidence: evidence,
        replayVerifierImmediatelyAfterMutation:
            replayVerifierImmediatelyAfterMutation,
        verifierOnlyContinuation: verifierOnlyContinuation,
        allowedToolNames: allowedToolNames,
      ),
    );
  }

  void endGoalContinuationScheduling() {
    _isSchedulingGoalContinuation = false;
  }
}

ToolResultCompletionEvidence _copyEvidence(
  ToolResultCompletionEvidence evidence,
) => ToolResultCompletionEvidence(
  boundedToolLoopExhausted: evidence.boundedToolLoopExhausted,
  unexecutedToolNames: List<String>.unmodifiable(evidence.unexecutedToolNames),
  unresolvedErrorCount: evidence.unresolvedErrorCount,
  unresolvedErrorPaths: List<String>.unmodifiable(
    evidence.unresolvedErrorPaths,
  ),
  unresolvedErrorDiagnostics: List<UnresolvedErrorDiagnostic>.unmodifiable(
    evidence.unresolvedErrorDiagnostics,
  ),
  unverifiedChangePaths: List<String>.unmodifiable(
    evidence.unverifiedChangePaths,
  ),
  mutatedWithoutExecutionVerification:
      evidence.mutatedWithoutExecutionVerification,
  hasExecutionVerification: evidence.hasExecutionVerification,
  hasSuccessfulExecutionVerification:
      evidence.hasSuccessfulExecutionVerification,
  hasFailedExecutionVerification: evidence.hasFailedExecutionVerification,
  hasAuthoritativeDiagnosticSnapshot:
      evidence.hasAuthoritativeDiagnosticSnapshot,
  hasUnexecutedActionClaim: evidence.hasUnexecutedActionClaim,
  diagnosticSignature: evidence.diagnosticSignature,
);
