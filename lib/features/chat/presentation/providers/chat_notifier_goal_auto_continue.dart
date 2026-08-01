// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

const _goalAutoContinuePolicy = ConversationGoalAutoContinuePolicy();
const _goalValidationToolNames = <String>{'local_execute_command', 'run_tests'};
const _goalRepairToolNames = <String>{
  'read_file',
  'write_file',
  'edit_file',
  'delete_file',
};

final class _GoalAutoContinueTracker {
  _GoalAutoContinueTracker({
    this.consecutiveAutoContinuations = 0,
    this.diagnosticRepairContinuations = 0,
    this.diagnosticRepairExtensionUsed = false,
    this.noProgressStreak = 0,
    this.consecutiveValidationMisses = 0,
    this.failedVerificationObserved = false,
    this.previousEvidence,
    this.verifierReplayCandidate,
    this.verifierReplayCandidateTaskId,
    this.previousDiagnosticSignature = '',
    this.identicalDiagnosticSignatureStreak = 0,
    this.pendingPostRepairReplayOutcome = false,
    this.pendingRepairContractOutcome = false,
    this.repairNoMutationRetryUsed = false,
    this.completionElicitationMutationGeneration,
  });

  int consecutiveAutoContinuations;
  int diagnosticRepairContinuations;
  bool diagnosticRepairExtensionUsed;
  int noProgressStreak;
  int consecutiveValidationMisses;
  bool failedVerificationObserved;
  ToolResultCompletionEvidence? previousEvidence;
  ToolCallInfo? verifierReplayCandidate;
  String? verifierReplayCandidateTaskId;
  int verifierReplayCandidatePriority = 0;
  String previousDiagnosticSignature;
  int identicalDiagnosticSignatureStreak;
  bool pendingPostRepairReplayOutcome;
  bool pendingRepairContractOutcome;
  bool repairNoMutationRetryUsed;

  /// The mutation generation at which a completion elicitation was last spent,
  /// or null when none has been. The goal may be asked again only once work has
  /// actually advanced past it.
  ///
  /// Resetting on any continuation was not enough: in session 76864d26 the
  /// elicitation turn's own answer produced the incomplete evidence that
  /// triggered the continuation, which cleared the flag and let the same
  /// elicitation fire again — six turns, no completion, ending in
  /// no_progress_stop.
  int? completionElicitationMutationGeneration;
  final Set<int> replayedMutationGenerations = <int>{};
  final Set<int> replayedInteractionGenerations = <int>{};
  final CommandDiagnosticStreakTracker commandDiagnosticStreakTracker =
      CommandDiagnosticStreakTracker();
  CommandDiagnosticRepairFocus? activeCommandDiagnosticRepairFocus;
}

extension ChatNotifierGoalAutoContinue on ChatNotifier {
  void _recordCommandDiagnosticStreak({
    required ChatTurnOwner owner,
    required String commandKey,
    required ToolResultInfo toolResult,
  }) {
    final conversation = _conversationForId(owner.conversationId);
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding) {
      return;
    }
    final tracker = _goalAutoContinueTrackers.putIfAbsent(
      conversation.id,
      _GoalAutoContinueTracker.new,
    );
    final observation = tracker.commandDiagnosticStreakTracker.observe(
      commandKey: commandKey,
      toolResult: toolResult,
    );
    if (observation == null) {
      return;
    }
    final activeFocus = tracker.activeCommandDiagnosticRepairFocus;
    final activatesFocus = activeFocus?.commandKey != commandKey;
    tracker.activeCommandDiagnosticRepairFocus = observation.repairFocus;
    appLog(
      '[CommandDiagnostic] observed; '
      'signatureStreak=${observation.streak}; '
      'signatureChanged=${observation.signatureChanged}',
    );
    if (activatesFocus) {
      appLog(
        '[CommandDiagnosticRepairFocus] activated; '
        'signatureStreak=${observation.streak}',
      );
    }
  }

  void _resetCommandDiagnosticStreak(ChatTurnOwner owner, String commandKey) {
    final tracker = _goalAutoContinueTrackers[owner.conversationId];
    tracker?.commandDiagnosticStreakTracker.reset(commandKey);
    if (tracker?.activeCommandDiagnosticRepairFocus?.commandKey == commandKey) {
      tracker?.activeCommandDiagnosticRepairFocus = null;
    }
  }

  CommandDiagnosticRepairFocus? _commandDiagnosticRepairFocusFor(
    Conversation? conversation,
  ) {
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding) {
      return null;
    }
    return _goalAutoContinueTrackers[conversation.id]
        ?.activeCommandDiagnosticRepairFocus;
  }

  void _clearCommandDiagnosticRepairFocus(ChatTurnOwner owner) {
    _goalAutoContinueTrackers[owner.conversationId]
            ?.activeCommandDiagnosticRepairFocus =
        null;
  }

  void _recordExecutedVerifierReplayCandidate(
    ChatTurnOwner owner,
    ToolCallInfo toolCall,
  ) {
    if (!verifierReplayCandidatePolicy.isEligible(toolCall)) {
      return;
    }
    final capability = const ToolCapabilityClassifier().classify(
      toolCall.name,
      arguments: toolCall.arguments,
    );
    if (capability.commandEffect != ToolCommandEffect.verification) {
      return;
    }
    final conversation = _conversationForId(owner.conversationId);
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding) {
      return;
    }
    final tracker = _goalAutoContinueTrackers.putIfAbsent(
      conversation.id,
      _GoalAutoContinueTracker.new,
    );
    final activeTaskId =
        ConversationPlanExecutionCoordinator.executionFocusTask(
          conversation,
        )?.id.trim();
    if (tracker.verifierReplayCandidateTaskId != activeTaskId) {
      tracker.verifierReplayCandidate = null;
      tracker.verifierReplayCandidatePriority = 0;
    }
    final priority = verifierReplayCandidatePolicy.priority(toolCall);
    if (priority < tracker.verifierReplayCandidatePriority) {
      return;
    }
    tracker.verifierReplayCandidate = ToolCallInfo(
      id: toolCall.id,
      name: toolCall.name,
      arguments: Map<String, dynamic>.unmodifiable(toolCall.arguments),
    );
    tracker.verifierReplayCandidateTaskId = activeTaskId;
    tracker.verifierReplayCandidatePriority = priority;
  }

  @visibleForTesting
  void recordExecutedVerifierReplayCandidateForTest(
    ChatTurnOwner owner,
    ToolCallInfo toolCall,
  ) => _recordExecutedVerifierReplayCandidate(owner, toolCall);

  @visibleForTesting
  bool hasVerifierReplayCandidateForOwnerForTest(ChatTurnOwner owner) {
    final conversation = _conversationForId(owner.conversationId);
    if (conversation == null) {
      return false;
    }
    final tracker = _goalAutoContinueTrackers[conversation.id];
    final activeTaskId =
        ConversationPlanExecutionCoordinator.executionFocusTask(
          conversation,
        )?.id.trim();
    return tracker?.verifierReplayCandidate != null &&
        tracker?.verifierReplayCandidateTaskId == activeTaskId;
  }

  @visibleForTesting
  bool isVerifierReplayEligibleForTest(ToolCallInfo toolCall) {
    return verifierReplayCandidatePolicy.isEligible(toolCall) &&
        const ToolCapabilityClassifier()
                .classify(toolCall.name, arguments: toolCall.arguments)
                .commandEffect ==
            ToolCommandEffect.verification;
  }

  ToolCallInfo? _takePostMutationVerifierReplay({
    required ToolResultCompletionEvidence evidence,
    required int interactionGeneration,
  }) {
    if (!evidence.mutatedWithoutExecutionVerification) {
      return null;
    }
    final conversation = _conversationForGeneration(interactionGeneration);
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding ||
        conversation.verificationGeneration >=
            conversation.mutationGeneration) {
      return null;
    }
    final tracker = _goalAutoContinueTrackers[conversation.id];
    final candidate = tracker?.verifierReplayCandidate;
    final activeTaskId =
        ConversationPlanExecutionCoordinator.executionFocusTask(
          conversation,
        )?.id.trim();
    if (tracker == null ||
        candidate == null ||
        tracker.verifierReplayCandidateTaskId != activeTaskId ||
        tracker.replayedMutationGenerations.contains(
          conversation.mutationGeneration,
        ) ||
        tracker.replayedInteractionGenerations.contains(
          interactionGeneration,
        )) {
      return null;
    }
    tracker.replayedMutationGenerations.add(conversation.mutationGeneration);
    tracker.replayedInteractionGenerations.add(interactionGeneration);
    return ToolCallInfo(
      id:
          'post_mutation_verifier_${conversation.mutationGeneration}_'
          '${DateTime.now().microsecondsSinceEpoch}',
      name: candidate.name,
      arguments: candidate.arguments,
    );
  }

  Future<bool> _replayVerifierAfterRepairMutation({
    required List<ToolResultInfo> executedToolResults,
    required Map<String, int> verificationFailureCounts,
    required Set<String> transcriptRepairSignatures,
    required ChatTurnOwner owner,
  }) async {
    final interactionGeneration = owner.interactionGeneration;
    final evidence = _goalCompletionEvidence.combinedToolResultsFor(
      owner,
      executedToolResults,
    );
    final replay = _takePostMutationVerifierReplay(
      evidence: evidence,
      interactionGeneration: interactionGeneration,
    );
    if (replay == null) return false;

    final conversation = _conversationForGeneration(interactionGeneration);
    final tracker = conversation == null
        ? null
        : _goalAutoContinueTrackers[conversation.id];
    tracker?.pendingRepairContractOutcome = false;
    tracker?.pendingPostRepairReplayOutcome = true;
    appLog(
      '[CodingVerification] Replaying the last executed verifier '
      'immediately after a repair mutation',
    );
    await _executeToolCalls(
      [replay],
      assistantContent:
          'The repair contract requires immediate verification after the '
          'first successful mutation.',
      stableToolDefinitions: const <Map<String, dynamic>>[],
      completionVerificationFailureCounts: verificationFailureCounts,
      narratedTranscriptRepairSignatures: transcriptRepairSignatures,
      interactionGeneration: interactionGeneration,
    );
    return true;
  }

  Future<bool> _finishExplicitTerminalSuccess(
    String? message, {
    required int interactionGeneration,
  }) async {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null ||
        message == null ||
        !await _acceptTerminalSuccessForOwner(owner)) {
      return false;
    }
    appLog('[Tool] Terminal success accepted for current generation');
    _explicitTerminalSuccessSummariesByGeneration[interactionGeneration] =
        message;
    _recordHiddenEvidence(owner, message);
    _appendRecoveredAssistantResponse(
      message,
      interactionGeneration: interactionGeneration,
    );
    return true;
  }

  Future<bool> _acceptTerminalSuccessForOwner(ChatTurnOwner owner) async {
    try {
      final notifier = ref.read(conversationsNotifierProvider.notifier);
      await notifier.recordVerificationGeneration(
        conversationId: owner.conversationId,
      );
      final conversation = _conversationForId(owner.conversationId);
      if (!_activeResponseRegistry.containsOwner(owner) ||
          conversation == null ||
          conversation.verificationGeneration !=
              conversation.mutationGeneration) {
        appLog(
          '[Tool] Terminal success rejected because execution generations '
          'do not match',
        );
        return false;
      }
      return true;
    } catch (error) {
      appLog('[Tool] Failed to settle terminal success generation: $error');
      return false;
    }
  }

  Future<void> _recordSuccessfulVerificationGenerationIfNeeded(
    ToolResultCompletionEvidence evidence, {
    required ChatTurnOwner owner,
  }) async {
    if (!evidence.hasSuccessfulExecutionVerification) return;
    if (!_activeResponseRegistry.containsOwner(owner)) return;
    try {
      await ref
          .read(conversationsNotifierProvider.notifier)
          .recordVerificationGeneration(conversationId: owner.conversationId);
    } catch (error) {
      appLog(
        '[ExecutionEvidence] Failed to persist successful verification generation: $error',
      );
    }
  }

  Future<ToolResultCompletionEvidence?> _finalizeGoalTurn({
    required ChatTurnOwner owner,
    required String assistantResponse,
    required int tokenUsageDelta,
    required LlmSessionLogContext context,
  }) =>
      TurnGoalCompletionFinalizer(
        recordGoalTurn: ref
            .read(conversationsNotifierProvider.notifier)
            .recordCurrentGoalTurn,
        recordGoalCompletionShadow: _recordGoalCompletionShadow,
      ).finalize(
        owner: owner,
        evidenceRegistry: _goalCompletionEvidence,
        finalizationState: _turnEnd,
        completedToolResults: _turnToolResults.completed(owner),
        contentToolResults: _turnToolResults.content(owner),
        conversation: _conversationForId(owner.conversationId),
        assistantResponse: assistantResponse,
        tokenUsageDelta: tokenUsageDelta,
        context: context,
      );

  @visibleForTesting
  bool Function() markNativeThenEmbeddedContentDedupeForTest(
    ChatTurnOwner owner,
    ToolCallData toolCall,
  ) {
    _markToolCallSeenForContentDedup(
      toolCall.name,
      toolCall.arguments,
      interactionGeneration: owner.interactionGeneration,
    );
    return () => _contentToolTurns.markSeenCall(
      owner,
      _contentToolCallHash(toolCall, owner),
    );
  }

  @visibleForTesting
  Future<ToolResultInfo?> persistToolResultForPromptForTest(
    ToolResultInfo toolResult,
    ChatTurnOwner owner,
  ) => _persistToolResultForPrompt(
    toolResult,
    interactionGeneration: owner.interactionGeneration,
  );

  void _resetGoalAutoContinueTrackerForConversation(String? conversationId) {
    if (conversationId == null) {
      _goalAutoContinueTrackers.clear();
      _goalAutoContinueBudgetNotifiedConversations.clear();
    } else {
      _goalAutoContinueTrackers.remove(conversationId);
      _goalAutoContinueBudgetNotifiedConversations.remove(conversationId);
    }
    _clearGoalAutoContinueIndicator();
  }

  void _clearGoalAutoContinueIndicator() {
    if (!ref.mounted) {
      return;
    }
    if (state.goalAutoContinueCount == 0 && state.goalAutoContinueBudget == 0) {
      return;
    }
    state = state.copyWith(goalAutoContinueCount: 0, goalAutoContinueBudget: 0);
  }

  bool _isGoalAutoContinueOwnerCurrent(ChatTurnOwner owner) =>
      ref.mounted && _queueOwnerIsVisible(owner.conversationId);

  _GoalAutoContinueTracker? _goalAutoContinueTrackerFor(
    String conversationId,
  ) => _goalAutoContinueTrackers.putIfAbsent(
    conversationId,
    _GoalAutoContinueTracker.new,
  );

  /// The harness's verification-cadence verdict for the target conversation.
  ///
  /// Reuses [ExecutionSnapshotProjector], which already computes this for the
  /// execution snapshot shown to the model, so the continuation policy and the
  /// prompt cannot drift apart.
  VerificationCadence _verificationCadenceFor(Conversation? conversation) {
    if (conversation == null) {
      return VerificationCadence.notDue;
    }
    // Derive it directly. Reading it off `project()` looked like the way to
    // keep the policy and the prompt in step, but `project` returns early for a
    // conversation with no workflow context and hands back the snapshot default
    // `notDue` — silently turning "required" into "not due" for a caller that
    // reads only this field.
    return ExecutionSnapshotProjector.verificationCadenceFor(conversation);
  }

  Future<void> _maybeAutoContinueCurrentGoal({
    required ChatTurnOwner owner,
    required String finalizedAssistantResponse,
    required String languageCode,
    required ToolResultCompletionEvidence evidence,
  }) async {
    if (_isSchedulingGoalAutoContinue ||
        !_isGoalAutoContinueOwnerCurrent(owner)) {
      return;
    }

    final currentConversation = _conversationForId(owner.conversationId);
    final goal = currentConversation?.goal;
    final currentConversationId = owner.conversationId;
    final tracker = _goalAutoContinueTrackerFor(currentConversationId);

    if (currentConversation?.workspaceMode != WorkspaceMode.coding) {
      _logGoalAutoContinueSkip('conversation is not in coding workspace');
      _clearGoalAutoContinueIndicator();
      return;
    }
    if (_isVoiceMode) {
      _logGoalAutoContinueSkip('voice mode is active');
      _clearGoalAutoContinueIndicator();
      return;
    }
    if (currentConversation == null) {
      _logGoalAutoContinueSkip('conversation id is unavailable');
      _clearGoalAutoContinueIndicator();
      return;
    }
    final savedTasks = currentConversation.projectedExecutionTasks;
    if (savedTasks.isNotEmpty &&
        !ShortPromptContractBuilder.isSyntheticRequestContract(
          currentConversation.effectiveWorkflowSpec,
        ) &&
        savedTasks.any(
          (task) => task.status != ConversationWorkflowTaskStatus.completed,
        )) {
      _logGoalAutoContinueSkip(
        'saved workflow execution owns pending task continuation',
      );
      _clearGoalAutoContinueIndicator();
      return;
    }

    final candidateNoProgressStreak = _candidateGoalAutoContinueProgressStreak(
      tracker: tracker,
      evidence: evidence,
    );
    final previousEvidence = tracker?.previousEvidence;
    final diagnosticSignatureChanged =
        tracker != null &&
        evidence.diagnosticSignature.isNotEmpty &&
        tracker.previousDiagnosticSignature.isNotEmpty &&
        evidence.diagnosticSignature != tracker.previousDiagnosticSignature;
    final postRepairVerifierAdvanced =
        (tracker?.pendingPostRepairReplayOutcome ?? false) &&
        diagnosticSignatureChanged;
    final repairContractProducedNoMutation =
        tracker?.pendingRepairContractOutcome ?? false;
    if (tracker != null) {
      tracker.pendingPostRepairReplayOutcome = false;
      tracker.pendingRepairContractOutcome = false;
    }
    final candidateDiagnosticSignatureStreak = tracker == null
        ? 0
        : const StalledDiagnosticRepairContract().nextSignatureStreak(
            previousSignature: tracker.previousDiagnosticSignature,
            currentSignature: evidence.diagnosticSignature,
            currentStreak: tracker.identicalDiagnosticSignatureStreak,
          );
    if (diagnosticSignatureChanged) {
      appLog('[DiagnosticRepairContract] diagnostic signature changed');
    }
    if (evidence.hasExecutionVerification) {
      tracker?.consecutiveValidationMisses = 0;
      tracker?.failedVerificationObserved =
          !evidence.hasSuccessfulExecutionVerification;
    }
    final diagnosticEvidenceImproved =
        previousEvidence != null &&
        evidence.hasDiagnosticEvidence &&
        evidence.compareProgress(previousEvidence) ==
            GoalEvidenceProgress.improved;
    final safeBoundary = _goalAutoContinueSafeBoundaryFromState();
    // The harness's own verification-cadence verdict, from the generation
    // counters. Without it the policy sees only tool-result evidence, which a
    // static check satisfies — the gap that let a turn end with mutations 3,
    // verification generation -1 and cadence `required` while auto-continue
    // reported "no incomplete evidence".
    final policyInput = GoalAutoContinuePolicyInput(
      goal: goal,
      safeBoundary: safeBoundary,
      evidence: evidence,
      consecutiveAutoContinuations: tracker?.consecutiveAutoContinuations ?? 0,
      diagnosticRepairContinuations:
          tracker?.diagnosticRepairContinuations ?? 0,
      diagnosticRepairExtensionUsed:
          tracker?.diagnosticRepairExtensionUsed ?? false,
      diagnosticEvidenceImproved: diagnosticEvidenceImproved,
      postRepairVerifierAdvanced: postRepairVerifierAdvanced,
      repairContractProducedNoMutation: repairContractProducedNoMutation,
      repairNoMutationRetryUsed: tracker?.repairNoMutationRetryUsed ?? false,
      consecutiveValidationMisses: tracker?.consecutiveValidationMisses ?? 0,
      failedVerificationObserved: tracker?.failedVerificationObserved ?? false,
      noProgressStreak: candidateNoProgressStreak,
      identicalDiagnosticSignatureStreak: candidateDiagnosticSignatureStreak,
      finalAnswerEndsWithQuestion: _endsWithQuestionMark(
        finalizedAssistantResponse,
      ),
      verificationCadence: _verificationCadenceFor(currentConversation),
    );
    final decision = _goalAutoContinuePolicy.decide(policyInput);

    if (decision.shouldBlock) {
      if (tracker != null) {
        tracker.noProgressStreak = candidateNoProgressStreak;
      }
      final blockedReason =
          decision.blockedReason ??
          'Goal auto-continue stopped because the task made no progress.';
      await _recordGoalAutoContinueSessionLog(
        owner: owner,
        decision: 'stop_and_block',
        reason: decision.reason,
        goal: goal,
        nextTurnNumber: goal?.turnsUsed,
        effectiveTurnBudget: _effectiveGoalAutoContinueBudget(goal),
        tracker: tracker,
        evidence: evidence,
        safeBoundary: safeBoundary,
      );
      if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
      appLog(
        '[GoalAutoContinue] stopAndBlock: ${decision.reason}; '
        'conversation=$currentConversationId; evidence=${evidence.summary}',
      );
      await ref
          .read(conversationsNotifierProvider.notifier)
          .markCurrentGoalStatus(
            status: ConversationGoalStatus.blocked,
            blockedReason: blockedReason,
          );
      _goalAutoContinueTrackers.remove(currentConversationId);
      if (_isGoalAutoContinueOwnerCurrent(owner)) {
        _clearGoalAutoContinueIndicator();
      }
      return;
    }

    if (!decision.shouldContinue) {
      _logGoalAutoContinueSkip(
        '${decision.reason}; conversation=$currentConversationId',
      );
      if (decision.stopCause == GoalAutoContinueStopCause.noProgress &&
          tracker != null) {
        tracker.noProgressStreak = candidateNoProgressStreak;
      }
      final noticeKey = GoalAutoContinueStopPresentation.noticeKeyFor(
        decision.stopCause,
      );
      if (noticeKey != null) {
        if (_goalAutoContinueBudgetNotifiedConversations.add(
          currentConversationId,
        )) {
          await _recordGoalAutoContinueSessionLog(
            owner: owner,
            decision: GoalAutoContinueStopPresentation.sessionDecisionFor(
              decision.stopCause,
            ),
            reason: decision.reason,
            goal: goal,
            nextTurnNumber: goal?.turnsUsed,
            effectiveTurnBudget: _effectiveGoalAutoContinueBudget(goal),
            tracker: tracker,
            evidence: evidence,
            safeBoundary: safeBoundary,
          );
          if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
          appLog(
            '[GoalAutoContinue] stopped; goal remains active for '
            'manual continuation. conversation=$currentConversationId',
          );
          state = state.copyWith(goalAutoContinueNotice: noticeKey);
        }
      } else if (goal?.isActive == true && goal!.autoContinue) {
        await _recordGoalAutoContinueSessionLog(
          owner: owner,
          decision: 'skip',
          reason: decision.reason,
          goal: goal,
          nextTurnNumber: goal.turnsUsed,
          effectiveTurnBudget: _effectiveGoalAutoContinueBudget(goal),
          tracker: tracker,
          evidence: evidence,
          safeBoundary: safeBoundary,
        );
        if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
      }
      if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
      // Nothing left to schedule, and the harness cannot say the objective was
      // met. Ask the model once ([GoalCompletionElicitationPrompt] carries the
      // rationale and the measurement behind it); if that does not settle the
      // goal, fall through to `awaitingConfirmation` so a stranded goal stops
      // reading as one still working.
      if (decision.noRemainingWork &&
          goal?.status == ConversationGoalStatus.active) {
        // Only ask about a goal that produced work: a run that mutated
        // nothing has nothing to confirm, and asking would tax every
        // conversation that merely carries a goal.
        final producedWork = currentConversation.mutationGeneration > 0;
        final mutationGeneration = currentConversation.mutationGeneration;
        final alreadyAsked =
            tracker?.completionElicitationMutationGeneration != null &&
            tracker!.completionElicitationMutationGeneration! >=
                mutationGeneration;
        if (producedWork &&
            goal!.autoContinue &&
            tracker != null &&
            !alreadyAsked) {
          tracker.completionElicitationMutationGeneration = mutationGeneration;
          _clearGoalAutoContinueIndicator();
          await _elicitGoalCompletionReport(
            owner: owner,
            languageCode: languageCode,
            evidence: evidence,
          );
          return;
        }
        await ref
            .read(conversationsNotifierProvider.notifier)
            .markCurrentGoalStatus(
              status: ConversationGoalStatus.awaitingConfirmation,
            );
      }
      if (_isGoalAutoContinueOwnerCurrent(owner)) {
        _clearGoalAutoContinueIndicator();
      }
      return;
    }

    if (!_isGoalAutoContinueOwnerCurrent(owner) ||
        state.isLoading ||
        _queuedChatMessages.pendingFor(conversationId) > 0) {
      _logGoalAutoContinueSkip(
        'state changed before continuation dispatch; '
        'conversation=$currentConversationId',
      );
      _clearGoalAutoContinueIndicator();
      return;
    }

    final executionSnapshot = const ExecutionSnapshotProjector().project(
      currentConversation,
    );
    final repairContract = const StalledDiagnosticRepairContract().build(
      evidence: evidence,
      executionSnapshot: executionSnapshot,
      noProgressStreak: tracker?.verifierReplayCandidate == null
          ? 0
          : candidateDiagnosticSignatureStreak,
    );
    if (repairContract != null) {
      appLog(
        '[DiagnosticRepairContract] activated; '
        'signatureStreak=$candidateDiagnosticSignatureStreak',
      );
    }
    final capabilityProfile = _goalAutoContinuePolicy.selectCapabilityProfile(
      evidence: evidence,
      hasRepairContract: repairContract != null,
    );
    final continuationPrompt = GoalAutoContinuePromptBuilder.build(
      goal: goal!,
      evidence: evidence,
      executionSnapshot: executionSnapshot,
      repairContract: repairContract,
      repairNoMutationRetry: decision.usesRepairNoMutationRetry,
      capabilityProfile: capabilityProfile,
      nextTurnNumber: decision.nextTurnNumber,
      effectiveTurnBudget: decision.effectiveTurnBudget,
      languageCode: languageCode,
    );

    if (tracker != null) {
      tracker.noProgressStreak = candidateNoProgressStreak;
      if (decision.usesDiagnosticRepairExtension) {
        tracker.diagnosticRepairExtensionUsed = true;
      }
      if (decision.usesRepairNoMutationRetry) {
        tracker.repairNoMutationRetryUsed = true;
      }
    }
    await _recordGoalAutoContinueSessionLog(
      owner: owner,
      decision: 'continue',
      reason: decision.reason,
      goal: goal,
      nextTurnNumber: decision.nextTurnNumber,
      effectiveTurnBudget: decision.effectiveTurnBudget,
      tracker: tracker,
      evidence: evidence,
      safeBoundary: safeBoundary,
    );
    if (!_isGoalAutoContinueOwnerCurrent(owner)) return;

    appLog(
      '[GoalAutoContinue] continue ${decision.nextTurnNumber}/'
      '${decision.effectiveTurnBudget}: ${decision.reason}; '
      'conversation=$currentConversationId; evidence=${evidence.summary}',
    );

    _isSchedulingGoalAutoContinue = true;
    state = state.copyWith(
      goalAutoContinueCount: decision.nextTurnNumber,
      goalAutoContinueBudget: decision.effectiveTurnBudget,
      goalAutoContinueNotice: null,
    );
    try {
      tracker?.consecutiveAutoContinuations += 1;
      if (evidence.hasDiagnosticEvidence) {
        tracker?.diagnosticRepairContinuations += 1;
      }
      if (policyInput.validationOutstanding) {
        tracker?.consecutiveValidationMisses += 1;
      }
      tracker?.previousEvidence = evidence;
      if (tracker != null) {
        tracker.previousDiagnosticSignature = evidence.diagnosticSignature;
        tracker.identicalDiagnosticSignatureStreak =
            candidateDiagnosticSignatureStreak;
        tracker.pendingRepairContractOutcome = repairContract != null;
      }
      if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
      final continuationFuture = sendHiddenPrompt(
        continuationPrompt,
        isVoiceMode: false,
        languageCode: languageCode,
        persistAssistantResponse: true,
        initialGoalCompletionEvidence: evidence,
        replayVerifierImmediatelyAfterMutation: repairContract != null,
        verifierOnlyContinuation:
            capabilityProfile == GoalAutoContinueCapabilityProfile.validation,
        allowedToolNames: switch (capabilityProfile) {
          GoalAutoContinueCapabilityProfile.repair => _goalRepairToolNames,
          GoalAutoContinueCapabilityProfile.validation =>
            _goalValidationToolNames,
          GoalAutoContinueCapabilityProfile.unrestricted => null,
        },
      );
      _isSchedulingGoalAutoContinue = false;
      await continuationFuture;
    } on Object catch (error, stackTrace) {
      tracker?.pendingRepairContractOutcome = false;
      appLog(
        '[GoalAutoContinue] hidden continuation failed: '
        '${error.runtimeType}: $error',
      );
      appLog('[GoalAutoContinue] stackTrace: $stackTrace');
      if (_isGoalAutoContinueOwnerCurrent(owner)) {
        _clearGoalAutoContinueIndicator();
      }
    } finally {
      _isSchedulingGoalAutoContinue = false;
    }
  }

  int _candidateGoalAutoContinueProgressStreak({
    required _GoalAutoContinueTracker? tracker,
    required ToolResultCompletionEvidence evidence,
  }) {
    if (tracker == null) {
      return 0;
    }
    final previousEvidence = tracker.previousEvidence;
    if (previousEvidence == null || !evidence.hasIncompleteEvidence) {
      return tracker.noProgressStreak;
    }
    final progress = evidence.compareProgress(previousEvidence);
    return progress == GoalEvidenceProgress.improved
        ? 0
        : tracker.noProgressStreak + 1;
  }

  GoalAutoContinueSafeBoundary _goalAutoContinueSafeBoundaryFromState() {
    return GoalAutoContinueSafeBoundary(
      isLoading: state.isLoading,
      hasQueuedUserInput:
          _queuedChatMessages.pendingFor(conversationId) > 0 ||
          state.queuedMessages.isNotEmpty,
      hasPendingSshConnect: state.pendingSshConnect != null,
      hasPendingSshCommand: state.pendingSshCommand != null,
      hasPendingGitCommand: state.pendingGitCommand != null,
      hasPendingLocalCommand: state.pendingLocalCommand != null,
      hasPendingComputerUseAction: state.pendingComputerUseAction != null,
      hasPendingBrowserAction: state.pendingBrowserAction != null,
      hasPendingFileOperation: state.pendingFileOperation != null,
      hasPendingBleConnect: state.pendingBleConnect != null,
      hasPendingSerialOpen: state.pendingSerialOpen != null,
      hasPendingParticipantToolApproval:
          state.pendingParticipantToolApproval != null,
      hasPendingAskUserQuestion: state.pendingAskUserQuestion != null,
      hasPendingWorkflowDecision: state.pendingWorkflowDecision != null,
      hasParticipantTurnRuntime: state.participantTurnRuntime != null,
      hasError: state.error?.trim().isNotEmpty ?? false,
    );
  }

  bool _endsWithQuestionMark(String content) {
    final trimmed = content.trimRight();
    return trimmed.endsWith('?') || trimmed.endsWith('？');
  }

  /// Spend one hidden turn asking the model to settle a goal that has run dry.
  ///
  /// Restricted to `update_goal` so the turn cannot start new work. Persisted
  /// like an auto-continuation because finalization drops an unpersisted
  /// assistant response before the goal turn is recorded, which is where the
  /// tool's completion claim is read.
  Future<void> _elicitGoalCompletionReport({
    required ChatTurnOwner owner,
    required String languageCode,
    required ToolResultCompletionEvidence evidence,
  }) async {
    if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
    appLog('[GoalAutoContinue] eliciting a goal completion report');
    try {
      if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
      await sendHiddenPrompt(
        GoalCompletionElicitationPrompt.build(languageCode: languageCode),
        isVoiceMode: false,
        languageCode: languageCode,
        persistAssistantResponse: true,
        initialGoalCompletionEvidence: evidence,
        allowedToolNames: const {'update_goal'},
      );
    } on Object catch (error) {
      appLog('[GoalAutoContinue] completion elicitation failed: $error');
    }
  }

  void _logGoalAutoContinueSkip(String reason) {
    appLog('[GoalAutoContinue] skip: $reason');
  }

  int? _effectiveGoalAutoContinueBudget(ConversationGoal? goal) {
    if (goal == null) {
      return null;
    }
    return goal.hasTurnBudget
        ? goal.turnBudget
        : kGoalAutoContinueDefaultTurnBudget;
  }

  Future<void> _recordGoalAutoContinueSessionLog({
    required ChatTurnOwner owner,
    required String decision,
    required String reason,
    required ConversationGoal? goal,
    required int? nextTurnNumber,
    required int? effectiveTurnBudget,
    required _GoalAutoContinueTracker? tracker,
    required ToolResultCompletionEvidence evidence,
    required GoalAutoContinueSafeBoundary safeBoundary,
  }) async {
    if (!LlmSessionLogStore.isEnabled(
      settingsEnabled: _settings.enableLlmSessionLogs,
    )) {
      return;
    }
    final conversation = _conversationForId(owner.conversationId);
    await ref
        .read(llmSessionLogStoreProvider)
        .recordGoalAutoContinue(
          context: _buildLlmSessionLogContext(
            targetConversationId: owner.conversationId,
          ),
          decision: decision,
          reason: reason,
          at: DateTime.now(),
          goalId: goal?.id,
          nextTurnNumber: nextTurnNumber,
          effectiveTurnBudget: effectiveTurnBudget,
          consecutiveAutoContinuations: tracker?.consecutiveAutoContinuations,
          evidence: GoalAutoContinueEvidenceMarker.build(
            evidence: evidence,
            verificationCadence: _verificationCadenceFor(conversation),
            mutationGeneration: conversation?.mutationGeneration,
            verificationGeneration: conversation?.verificationGeneration,
            safeBoundaryVeto: safeBoundary.firstVetoReason,
            noProgressStreak: tracker?.noProgressStreak ?? 0,
            hasVerifierReplayCandidate: tracker?.verifierReplayCandidate != null,
            diagnosticRepairContinuations:
                tracker?.diagnosticRepairContinuations ?? 0,
            consecutiveValidationMisses:
                tracker?.consecutiveValidationMisses ?? 0,
            diagnosticRepairExtensionUsed:
                tracker?.diagnosticRepairExtensionUsed ?? false,
            previousUnresolvedErrorCount:
                tracker?.previousEvidence?.unresolvedErrorCount,
            identicalDiagnosticSignatureStreak:
                tracker?.identicalDiagnosticSignatureStreak ?? 0,
          ),
        );
  }

  /// Handles `update_goal` against the exact owner's current-turn results.
  ///
  /// Accepted claims remain one-shot and are re-checked at turn finalization.
  Future<McpToolResult> handleUpdateGoal(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    if (interactionGeneration == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final ack = const GoalUpdateAckResolver().resolveCall(
      toolCall: toolCall,
      goal: _conversationForId(owner.conversationId)?.goal,
      evidence: _goalCompletionEvidence.combinedToolResultsFor(
        owner,
        _turnToolResults.completed(owner),
      ),
    );
    if (ack.isCompletionClaim) {
      _turnEnd.setGoalOutcome(owner, ack.outcome);
    }
    // Only accepted claims reach finalization; rejected claims must be repaired.
    if (ack.completionAccepted) {
      _turnEnd.markGoalClaimed(owner);
    }
    return ack.toToolResult(toolCall.name);
  }

  Future<void> _recordGoalCompletionShadow({
    required bool lexicalCompleted,
    required ChatTurnOwner owner,
    required LlmSessionLogContext context,
    required GoalUpdateAckOutcome? toolCompletionOutcome,
  }) async {
    final disagreement = GoalCompletionShadow.compare(
      toolCompletionOutcome: toolCompletionOutcome,
      lexicalCompleted: lexicalCompleted,
    );
    if (disagreement == null) return;
    final loggingEnabled = LlmSessionLogStore.isEnabled(
      settingsEnabled: _settings.enableLlmSessionLogs,
    );
    if (!loggingEnabled) return;
    await ref
        .read(llmSessionLogStoreProvider)
        .recordGoalCompletionShadow(
          context: context,
          at: DateTime.now(),
          label: GoalCompletionShadow.labelFor(disagreement),
          toolOutcome: toolCompletionOutcome?.name,
          lexicalCompleted: lexicalCompleted,
          turnId: 'gen-${owner.interactionGeneration}',
        );
  }
}
