import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/goal_auto_continue_decision_coordinator.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';
import '../../domain/services/goal_completion_elicitation_prompt.dart';
import '../../domain/services/goal_continuation_log_record_builder.dart';
import '../../domain/services/tool_result_prompt_builder.dart';

// ChatNotifier decomposition collaborator: turn-runtime
// Every port below is bound to one owner when the composition root creates it,
// so none of them re-takes the owner per call. The prototype's first shape
// passed `ChatTurnOwner` into all eight port methods, which measured as
// identity plumbing relocated across the boundary rather than removed; binding
// the owner once is what makes the runtime own its identity.

/// Access to the current turn lifecycle for this runtime's owner.
abstract interface class TurnRuntimeOwnerLeasePort {
  bool get isCurrent;
}

/// Access to conversation goal state and persistence for this runtime's owner.
abstract interface class TurnRuntimeConversationGoalPort {
  Conversation? get conversation;

  Future<void> markGoalStatus(TurnRuntimeGoalStatusUpdate update);
}

/// Conversation-spanning continuation history used by one turn runtime.
abstract interface class TurnRuntimeGoalTrackerPort {
  GoalAutoContinueTrackerSnapshot get snapshot;

  GoalAutoContinueTrackerSnapshot applyDelta(
    GoalAutoContinueTrackerDelta delta,
  );

  bool markBudgetNoticePresented();

  GoalAutoContinueTrackerSnapshot clearPendingRepairContract();

  void removeTracker();
}

/// Captures pending thread state as one immutable continuation boundary.
abstract interface class TurnRuntimeGoalSafeBoundaryPort {
  GoalAutoContinueSafeBoundary capture();
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

sealed class TurnRuntimeGoalCoordinationResult {
  const TurnRuntimeGoalCoordinationResult({required this.owner});

  final ChatTurnOwner owner;
}

final class TurnRuntimeGoalCoordinationUnavailable
    extends TurnRuntimeGoalCoordinationResult {
  const TurnRuntimeGoalCoordinationUnavailable({required super.owner});
}

final class TurnRuntimeGoalCoordinationReady
    extends TurnRuntimeGoalCoordinationResult {
  const TurnRuntimeGoalCoordinationReady({
    required super.owner,
    required this.conversation,
    required this.tracker,
    required this.safeBoundary,
    required this.plan,
  });

  final Conversation conversation;
  final GoalAutoContinueTrackerSnapshot tracker;
  final GoalAutoContinueSafeBoundary safeBoundary;
  final GoalAutoContinueDecisionPlan plan;
}

/// Synchronous tracker changes produced at one branch-specific apply point.
final class TurnRuntimeGoalTrackerTransition {
  const TurnRuntimeGoalTrackerTransition({
    required this.owner,
    required this.snapshot,
    required this.budgetNoticePresented,
    required this.removeTrackerAfterPersistence,
  });

  final ChatTurnOwner owner;
  final GoalAutoContinueTrackerSnapshot snapshot;
  final bool budgetNoticePresented;
  final bool removeTrackerAfterPersistence;
}

/// Tracker cleanup performed only after blocked status persistence completes.
final class TurnRuntimePersistedGoalBlockFinalization {
  const TurnRuntimePersistedGoalBlockFinalization({
    required this.owner,
    required this.trackerRemoved,
  });

  final ChatTurnOwner owner;
  final bool trackerRemoved;
}

/// Tracker cleanup performed only after hidden continuation dispatch fails.
final class TurnRuntimeFailedGoalDispatchFinalization {
  const TurnRuntimeFailedGoalDispatchFinalization({
    required this.owner,
    required this.snapshot,
  });

  final ChatTurnOwner owner;
  final GoalAutoContinueTrackerSnapshot snapshot;
}

/// Exact goal status mutation requested by a runtime owner.
final class TurnRuntimeGoalStatusUpdate {
  const TurnRuntimeGoalStatusUpdate({required this.status, this.blockedReason});

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

/// Shares one active continuation runtime across recursive wrapper entries.
final class TurnRuntimeGoalContinuationLifecycle {
  TurnRuntime? _activeRuntime;

  bool get isScheduling => _activeRuntime != null;

  bool claim(TurnRuntime runtime) {
    if (_activeRuntime != null || !runtime.isSchedulingGoalContinuation) {
      return false;
    }
    _activeRuntime = runtime;
    return true;
  }

  void release(TurnRuntime runtime) {
    if (!identical(_activeRuntime, runtime)) return;
    _activeRuntime = null;
    runtime.endGoalContinuationScheduling();
  }

  void clear() {
    final activeRuntime = _activeRuntime;
    _activeRuntime = null;
    activeRuntime?.endGoalContinuationScheduling();
  }
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

  TurnRuntimeGoalCoordinationResult coordinateGoalContinuation(
    TurnRuntimeGoalContinuationInput input,
  ) {
    final conversation = goalContinuation.conversationGoal.conversation;
    if (conversation == null) {
      return TurnRuntimeGoalCoordinationUnavailable(owner: owner);
    }
    final tracker = goalContinuation.tracker.snapshot;
    final safeBoundary = goalContinuation.safeBoundary.capture();
    final plan = const GoalAutoContinueDecisionCoordinator().coordinate(
      GoalAutoContinueDecisionInput(
        owner: owner,
        ownerConversation: conversation,
        tracker: tracker,
        completionEvidence: input.evidence,
        finalizedAssistantResponse: input.finalizedAssistantResponse,
        safeBoundary: safeBoundary,
        isVoiceMode: input.isVoiceMode,
      ),
    );
    return TurnRuntimeGoalCoordinationReady(
      owner: owner,
      conversation: conversation,
      tracker: tracker,
      safeBoundary: safeBoundary,
      plan: plan,
    );
  }

  TurnRuntimeGoalTrackerTransition applyGoalTrackerTransition(
    GoalAutoContinueTrackerDelta delta,
  ) {
    final snapshot = goalContinuation.tracker.applyDelta(delta);
    final budgetNoticePresented =
        delta.markBudgetNoticePresented &&
        goalContinuation.tracker.markBudgetNoticePresented();
    return TurnRuntimeGoalTrackerTransition(
      owner: owner,
      snapshot: snapshot,
      budgetNoticePresented: budgetNoticePresented,
      removeTrackerAfterPersistence: delta.removeTracker,
    );
  }

  TurnRuntimePersistedGoalBlockFinalization finalizePersistedGoalBlock(
    TurnRuntimeGoalTrackerTransition transition,
  ) {
    if (transition.owner != owner) {
      throw ArgumentError.value(
        transition.owner,
        'transition',
        'Tracker transition owner must match the runtime owner.',
      );
    }
    if (transition.removeTrackerAfterPersistence) {
      goalContinuation.tracker.removeTracker();
    }
    return TurnRuntimePersistedGoalBlockFinalization(
      owner: owner,
      trackerRemoved: transition.removeTrackerAfterPersistence,
    );
  }

  TurnRuntimeFailedGoalDispatchFinalization
  finalizeFailedGoalContinuationDispatch() =>
      TurnRuntimeFailedGoalDispatchFinalization(
        owner: owner,
        snapshot: goalContinuation.tracker.clearPendingRepairContract(),
      );

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
