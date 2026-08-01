import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/types/workspace_mode.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'stalled_diagnostic_repair_contract.dart';
import 'tool_result_prompt_builder.dart';

// ChatNotifier decomposition collaborator: goal-auto-continue-tracker-registry
typedef VerifierReplayIdFactory = String Function(int mutationGeneration);
typedef GoalAutoContinueConversationTaskSnapshot = ({
  ChatTurnOwner owner,
  WorkspaceMode workspaceMode,
  String? activeTaskId,
  int mutationGeneration,
  int verificationGeneration,
});
typedef GoalVerifierReplayCandidateSnapshot = ({
  String id,
  String name,
  Map<String, dynamic> arguments,
  String? taskId,
  int priority,
});
typedef GoalAutoContinueTrackerSnapshot = ({
  int consecutiveAutoContinuations,
  int diagnosticRepairContinuations,
  bool diagnosticRepairExtensionUsed,
  int noProgressStreak,
  int consecutiveValidationMisses,
  bool failedVerificationObserved,
  ToolResultCompletionEvidence? previousEvidence,
  String previousDiagnosticSignature,
  int identicalDiagnosticSignatureStreak,
  bool pendingPostRepairReplayOutcome,
  bool pendingRepairContractOutcome,
  bool repairNoMutationRetryUsed,
  int? completionElicitationMutationGeneration,
  CommandDiagnosticRepairFocus? activeCommandDiagnosticRepairFocus,
  GoalVerifierReplayCandidateSnapshot? verifierReplayCandidate,
  Set<int> replayedMutationGenerations,
  Set<int> replayedInteractionGenerations,
  bool budgetNoticePresented,
});
typedef GoalCommandDiagnosticEvent = ({
  ChatTurnOwner owner,
  String commandKey,
  int streak,
  bool signatureChanged,
  bool focusActivated,
  CommandDiagnosticRepairFocus repairFocus,
});

enum GoalVerifierReplayCandidateDisposition {
  ignored,
  recorded,
  retainedHigherPriority,
}

typedef GoalVerifierReplayCandidateEvent = ({
  ChatTurnOwner owner,
  GoalVerifierReplayCandidateDisposition disposition,
  bool taskChanged,
  int priority,
  GoalVerifierReplayCandidateSnapshot? candidate,
});
typedef GoalVerifierReplaySelection = ({
  ChatTurnOwner owner,
  int mutationGeneration,
  String? taskId,
  int priority,
  ToolCallInfo toolCall,
});

final class GoalAutoContinueTrackerRegistry {
  GoalAutoContinueTrackerRegistry({
    required VerifierReplayIdFactory replayIdFactory,
  }) : _replayIdFactory = replayIdFactory;

  final VerifierReplayIdFactory _replayIdFactory;
  final Map<String, _GoalTrackerState> _trackers = {};
  final Set<ChatTurnOwner> _replayedOwners = {};
  final Set<String> _budgetNotifiedConversations = {};
  GoalAutoContinueTrackerSnapshot create(ChatTurnOwner owner) =>
      _snapshot(owner, _trackers.putIfAbsent(owner.conversationId, _newState));

  GoalAutoContinueTrackerSnapshot? read(ChatTurnOwner owner) {
    final state = _trackers[owner.conversationId];
    return state == null ? null : _snapshot(owner, state);
  }

  GoalAutoContinueTrackerSnapshot update(
    ChatTurnOwner owner, {
    int consecutiveAutoContinuationsDelta = 0,
    int diagnosticRepairContinuationsDelta = 0,
    bool? diagnosticRepairExtensionUsed,
    int? noProgressStreak,
    int? consecutiveValidationMisses,
    bool? failedVerificationObserved,
    ToolResultCompletionEvidence? previousEvidence,
    bool clearPreviousEvidence = false,
    String? previousDiagnosticSignature,
    int? identicalDiagnosticSignatureStreak,
    bool? pendingPostRepairReplayOutcome,
    bool? pendingRepairContractOutcome,
    bool? repairNoMutationRetryUsed,
    int? completionElicitationMutationGeneration,
    bool clearCompletionElicitationMutationGeneration = false,
  }) {
    if (clearPreviousEvidence && previousEvidence != null) {
      throw ArgumentError(
        'previousEvidence cannot be set and cleared in the same update.',
      );
    }
    if (clearCompletionElicitationMutationGeneration &&
        completionElicitationMutationGeneration != null) {
      throw ArgumentError(
        'completionElicitationMutationGeneration cannot be set and cleared '
        'in the same update.',
      );
    }
    final state = _trackers.putIfAbsent(owner.conversationId, _newState);
    state
      ..consecutiveAutoContinuations += consecutiveAutoContinuationsDelta
      ..diagnosticRepairContinuations += diagnosticRepairContinuationsDelta
      ..diagnosticRepairExtensionUsed =
          diagnosticRepairExtensionUsed ?? state.diagnosticRepairExtensionUsed
      ..noProgressStreak = noProgressStreak ?? state.noProgressStreak
      ..consecutiveValidationMisses =
          consecutiveValidationMisses ?? state.consecutiveValidationMisses
      ..failedVerificationObserved =
          failedVerificationObserved ?? state.failedVerificationObserved
      ..previousEvidence = clearPreviousEvidence
          ? null
          : previousEvidence == null
          ? state.previousEvidence
          : _copyEvidence(previousEvidence)
      ..previousDiagnosticSignature =
          previousDiagnosticSignature ?? state.previousDiagnosticSignature
      ..identicalDiagnosticSignatureStreak =
          identicalDiagnosticSignatureStreak ??
          state.identicalDiagnosticSignatureStreak
      ..pendingPostRepairReplayOutcome =
          pendingPostRepairReplayOutcome ?? state.pendingPostRepairReplayOutcome
      ..pendingRepairContractOutcome =
          pendingRepairContractOutcome ?? state.pendingRepairContractOutcome
      ..repairNoMutationRetryUsed =
          repairNoMutationRetryUsed ?? state.repairNoMutationRetryUsed
      ..completionElicitationMutationGeneration =
          clearCompletionElicitationMutationGeneration
          ? null
          : completionElicitationMutationGeneration ??
                state.completionElicitationMutationGeneration;
    return _snapshot(owner, state);
  }

  bool markBudgetNoticePresented(ChatTurnOwner owner) =>
      _budgetNotifiedConversations.add(owner.conversationId);

  void removeTracker(ChatTurnOwner owner) {
    _trackers.remove(owner.conversationId);
    _replayedOwners.removeWhere(
      (key) => key.conversationId == owner.conversationId,
    );
  }

  void resetConversation(String? conversationId) {
    if (conversationId == null) {
      _trackers.clear();
      _replayedOwners.clear();
      _budgetNotifiedConversations.clear();
      return;
    }
    _trackers.remove(conversationId);
    _replayedOwners.removeWhere((key) => key.conversationId == conversationId);
    _budgetNotifiedConversations.remove(conversationId);
  }

  GoalCommandDiagnosticEvent? recordCommandDiagnostic({
    required GoalAutoContinueConversationTaskSnapshot context,
    required String commandKey,
    required ToolResultInfo toolResult,
  }) {
    if (!_isCoding(context)) return null;
    final state = _trackers.putIfAbsent(
      context.owner.conversationId,
      _newState,
    );
    final observation = state.commandDiagnosticStreakTracker.observe(
      commandKey: commandKey,
      toolResult: toolResult,
    );
    if (observation == null) return null;
    final focusActivated =
        state.activeCommandDiagnosticRepairFocus?.commandKey != commandKey;
    state.activeCommandDiagnosticRepairFocus = _copyFocus(
      observation.repairFocus,
    );
    return (
      owner: context.owner,
      commandKey: commandKey,
      streak: observation.streak,
      signatureChanged: observation.signatureChanged,
      focusActivated: focusActivated,
      repairFocus: _copyFocus(observation.repairFocus),
    );
  }

  bool resetCommandDiagnostic(ChatTurnOwner owner, String commandKey) {
    final state = _trackers[owner.conversationId];
    if (state == null) return false;
    state.commandDiagnosticStreakTracker.reset(commandKey);
    final clearsFocus =
        state.activeCommandDiagnosticRepairFocus?.commandKey == commandKey;
    if (clearsFocus) state.activeCommandDiagnosticRepairFocus = null;
    return clearsFocus;
  }

  CommandDiagnosticRepairFocus? commandDiagnosticRepairFocusFor(
    GoalAutoContinueConversationTaskSnapshot context,
  ) {
    if (!_isCoding(context)) return null;
    final focus = _trackers[context.owner.conversationId]
        ?.activeCommandDiagnosticRepairFocus;
    return focus == null ? null : _copyFocus(focus);
  }

  bool clearCommandDiagnosticRepairFocus(ChatTurnOwner owner) {
    final state = _trackers[owner.conversationId];
    if (state?.activeCommandDiagnosticRepairFocus == null) return false;
    state!.activeCommandDiagnosticRepairFocus = null;
    return true;
  }

  GoalVerifierReplayCandidateEvent recordExecutedVerifierReplayCandidate({
    required GoalAutoContinueConversationTaskSnapshot context,
    required ToolCallInfo toolCall,
  }) {
    if (!isReplayEligibleVerifierToolCall(toolCall) ||
        const ToolCapabilityClassifier()
                .classify(toolCall.name, arguments: toolCall.arguments)
                .commandEffect !=
            ToolCommandEffect.verification ||
        !_isCoding(context)) {
      return _candidateEvent(
        context.owner,
        GoalVerifierReplayCandidateDisposition.ignored,
      );
    }
    final state = _trackers.putIfAbsent(
      context.owner.conversationId,
      _newState,
    );
    final activeTaskId = _activeTaskId(context);
    final taskChanged = state.candidateTaskId != activeTaskId;
    if (taskChanged) {
      state
        ..candidate = null
        ..candidatePriority = 0;
    }
    final priority = verifierReplayPriority(toolCall);
    if (priority < state.candidatePriority) {
      return _candidateEvent(
        context.owner,
        GoalVerifierReplayCandidateDisposition.retainedHigherPriority,
        taskChanged: taskChanged,
        state: state,
      );
    }
    state
      ..candidate = _copyToolCall(toolCall)
      ..candidateTaskId = activeTaskId
      ..candidatePriority = priority;
    return _candidateEvent(
      context.owner,
      GoalVerifierReplayCandidateDisposition.recorded,
      taskChanged: taskChanged,
      state: state,
    );
  }

  bool hasVerifierReplayCandidate(
    GoalAutoContinueConversationTaskSnapshot context,
  ) {
    final state = _trackers[context.owner.conversationId];
    return state?.candidate != null &&
        state?.candidateTaskId == _activeTaskId(context);
  }

  GoalVerifierReplaySelection? takePostMutationVerifierReplay({
    required GoalAutoContinueConversationTaskSnapshot context,
    required ToolResultCompletionEvidence evidence,
  }) {
    if (!evidence.mutatedWithoutExecutionVerification ||
        !_isCoding(context) ||
        context.verificationGeneration >= context.mutationGeneration) {
      return null;
    }
    final state = _trackers[context.owner.conversationId];
    final candidate = state?.candidate;
    if (state == null ||
        candidate == null ||
        state.candidateTaskId != _activeTaskId(context) ||
        state.replayedMutationGenerations.contains(
          context.mutationGeneration,
        )) {
      return null;
    }
    if (_replayedOwners.contains(context.owner)) return null;
    state.replayedMutationGenerations.add(context.mutationGeneration);
    _replayedOwners.add(context.owner);
    final replayCall = ToolCallInfo(
      id: _replayIdFactory(context.mutationGeneration),
      name: candidate.name,
      arguments: candidate.arguments,
    );
    return (
      owner: context.owner,
      mutationGeneration: context.mutationGeneration,
      taskId: state.candidateTaskId,
      priority: state.candidatePriority,
      toolCall: _copyToolCall(replayCall),
    );
  }

  bool isReplayEligibleVerifierToolCall(ToolCallInfo toolCall) {
    final name = toolCall.name.trim().toLowerCase();
    if (name == 'run_tests') return true;
    if (name != 'local_execute_command' ||
        toolCall.arguments['background'] == true) {
      return false;
    }
    final command = (toolCall.arguments['command'] as String? ?? '').trim();
    return command.isNotEmpty &&
        !RegExp(r'[\r\n;&|`<>]|\$\(').hasMatch(command);
  }

  int verifierReplayPriority(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() == 'run_tests') return 2;
    final command = (toolCall.arguments['command'] as String? ?? '')
        .toLowerCase();
    return RegExp(r'(^|[/_-])verif(y|ier)').hasMatch(command) ? 2 : 1;
  }

  GoalAutoContinueTrackerSnapshot _snapshot(
    ChatTurnOwner owner,
    _GoalTrackerState state,
  ) {
    final ownerReplayed = _replayedOwners.contains(owner);
    return (
      consecutiveAutoContinuations: state.consecutiveAutoContinuations,
      diagnosticRepairContinuations: state.diagnosticRepairContinuations,
      diagnosticRepairExtensionUsed: state.diagnosticRepairExtensionUsed,
      noProgressStreak: state.noProgressStreak,
      consecutiveValidationMisses: state.consecutiveValidationMisses,
      failedVerificationObserved: state.failedVerificationObserved,
      previousEvidence: state.previousEvidence == null
          ? null
          : _copyEvidence(state.previousEvidence!),
      previousDiagnosticSignature: state.previousDiagnosticSignature,
      identicalDiagnosticSignatureStreak:
          state.identicalDiagnosticSignatureStreak,
      pendingPostRepairReplayOutcome: state.pendingPostRepairReplayOutcome,
      pendingRepairContractOutcome: state.pendingRepairContractOutcome,
      repairNoMutationRetryUsed: state.repairNoMutationRetryUsed,
      completionElicitationMutationGeneration:
          state.completionElicitationMutationGeneration,
      activeCommandDiagnosticRepairFocus:
          state.activeCommandDiagnosticRepairFocus == null
          ? null
          : _copyFocus(state.activeCommandDiagnosticRepairFocus!),
      verifierReplayCandidate: state.candidate == null
          ? null
          : _candidateSnapshot(state),
      replayedMutationGenerations: Set<int>.unmodifiable(
        state.replayedMutationGenerations,
      ),
      replayedInteractionGenerations: Set<int>.unmodifiable({
        if (ownerReplayed) owner.interactionGeneration,
      }),
      budgetNoticePresented: _budgetNotifiedConversations.contains(
        owner.conversationId,
      ),
    );
  }

  GoalVerifierReplayCandidateEvent _candidateEvent(
    ChatTurnOwner owner,
    GoalVerifierReplayCandidateDisposition disposition, {
    bool taskChanged = false,
    _GoalTrackerState? state,
  }) => (
    owner: owner,
    disposition: disposition,
    taskChanged: taskChanged,
    priority: state?.candidatePriority ?? 0,
    candidate: state?.candidate == null ? null : _candidateSnapshot(state!),
  );
}

final class _GoalTrackerState {
  int consecutiveAutoContinuations = 0;
  int diagnosticRepairContinuations = 0;
  bool diagnosticRepairExtensionUsed = false;
  int noProgressStreak = 0;
  int consecutiveValidationMisses = 0;
  bool failedVerificationObserved = false;
  ToolResultCompletionEvidence? previousEvidence;
  String previousDiagnosticSignature = '';
  int identicalDiagnosticSignatureStreak = 0;
  bool pendingPostRepairReplayOutcome = false;
  bool pendingRepairContractOutcome = false;
  bool repairNoMutationRetryUsed = false;
  int? completionElicitationMutationGeneration;
  final CommandDiagnosticStreakTracker commandDiagnosticStreakTracker =
      CommandDiagnosticStreakTracker();
  CommandDiagnosticRepairFocus? activeCommandDiagnosticRepairFocus;
  ToolCallInfo? candidate;
  String? candidateTaskId;
  int candidatePriority = 0;
  final Set<int> replayedMutationGenerations = {};
}

_GoalTrackerState _newState() => _GoalTrackerState();
bool _isCoding(GoalAutoContinueConversationTaskSnapshot context) =>
    context.workspaceMode == WorkspaceMode.coding;
String? _activeTaskId(GoalAutoContinueConversationTaskSnapshot context) =>
    context.activeTaskId?.trim();

GoalVerifierReplayCandidateSnapshot _candidateSnapshot(
  _GoalTrackerState state,
) {
  final candidate = state.candidate!;
  return (
    id: candidate.id,
    name: candidate.name,
    arguments: _freezeMap(candidate.arguments),
    taskId: state.candidateTaskId,
    priority: state.candidatePriority,
  );
}

CommandDiagnosticRepairFocus _copyFocus(CommandDiagnosticRepairFocus focus) =>
    CommandDiagnosticRepairFocus(
      commandKey: focus.commandKey,
      streak: focus.streak,
      diagnosticSummary: focus.diagnosticSummary,
      hasPathBackedDiagnostic: focus.hasPathBackedDiagnostic,
    );

ToolCallInfo _copyToolCall(ToolCallInfo call) => ToolCallInfo(
  id: call.id,
  name: call.name,
  arguments: _freezeMap(call.arguments),
);

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

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    ImmutableJsonSnapshot.freezeMap(value);
