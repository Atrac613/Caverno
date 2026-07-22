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
  final Set<int> replayedMutationGenerations = <int>{};
  final Set<int> replayedInteractionGenerations = <int>{};
  final CommandDiagnosticStreakTracker commandDiagnosticStreakTracker =
      CommandDiagnosticStreakTracker();
  CommandDiagnosticRepairFocus? activeCommandDiagnosticRepairFocus;
}

extension ChatNotifierGoalAutoContinue on ChatNotifier {
  void _recordCommandDiagnosticStreak({
    required String commandKey,
    required ToolResultInfo toolResult,
  }) {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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

  void _resetCommandDiagnosticStreak(String commandKey) {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) {
      return;
    }
    final tracker = _goalAutoContinueTrackers[conversation.id];
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

  void _clearCommandDiagnosticRepairFocus() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) {
      return;
    }
    _goalAutoContinueTrackers[conversation.id]
            ?.activeCommandDiagnosticRepairFocus =
        null;
  }

  void _recordExecutedVerifierReplayCandidate(ToolCallInfo toolCall) {
    if (!_isReplayEligibleVerifierToolCall(toolCall)) {
      return;
    }
    final capability = const ToolCapabilityClassifier().classify(
      toolCall.name,
      arguments: toolCall.arguments,
    );
    if (capability.commandEffect != ToolCommandEffect.verification) {
      return;
    }
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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
    final priority = _verifierReplayPriority(toolCall);
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
  void recordExecutedVerifierReplayCandidateForTest(ToolCallInfo toolCall) {
    _recordExecutedVerifierReplayCandidate(toolCall);
  }

  @visibleForTesting
  bool hasVerifierReplayCandidateForCurrentTaskForTest() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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

  bool _isReplayEligibleVerifierToolCall(ToolCallInfo toolCall) {
    final name = toolCall.name.trim().toLowerCase();
    if (name == 'run_tests') {
      return true;
    }
    if (name != 'local_execute_command' ||
        toolCall.arguments['background'] == true) {
      return false;
    }
    final command = (toolCall.arguments['command'] as String? ?? '').trim();
    if (command.isEmpty || RegExp(r'[\r\n;&|`<>]|\$\(').hasMatch(command)) {
      return false;
    }
    return true;
  }

  int _verifierReplayPriority(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() == 'run_tests') {
      return 2;
    }
    final command = (toolCall.arguments['command'] as String? ?? '')
        .toLowerCase();
    return RegExp(r'(^|[/_-])verif(y|ier)').hasMatch(command) ? 2 : 1;
  }

  @visibleForTesting
  bool isVerifierReplayEligibleForTest(ToolCallInfo toolCall) {
    return _isReplayEligibleVerifierToolCall(toolCall) &&
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
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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
    required int interactionGeneration,
  }) async {
    final evidence = ToolResultPromptBuilder.completionEvidence(
      executedToolResults,
    ).carryForwardIncompleteFrom(_latestGoalAutoContinueEvidence);
    final replay = _takePostMutationVerifierReplay(
      evidence: evidence,
      interactionGeneration: interactionGeneration,
    );
    if (replay == null) return false;

    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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
    if (message == null ||
        !await _acceptTerminalSuccessForCurrentGeneration()) {
      return false;
    }
    appLog('[Tool] Terminal success accepted for current generation');
    _explicitTerminalSuccessSummariesByGeneration[interactionGeneration] =
        message;
    _recordHiddenAssistantResponse(message);
    _appendRecoveredAssistantResponse(
      message,
      interactionGeneration: interactionGeneration,
    );
    return true;
  }

  Future<bool> _acceptTerminalSuccessForCurrentGeneration() async {
    try {
      final notifier = ref.read(conversationsNotifierProvider.notifier);
      await notifier.recordCurrentVerificationGeneration();
      final conversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      if (conversation == null ||
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
    ToolResultCompletionEvidence evidence,
  ) async {
    if (!evidence.hasSuccessfulExecutionVerification) {
      return;
    }
    try {
      await ref
          .read(conversationsNotifierProvider.notifier)
          .recordCurrentVerificationGeneration();
    } catch (error) {
      appLog(
        '[ExecutionEvidence] Failed to persist successful verification '
        'generation: $error',
      );
    }
  }

  ToolResultCompletionEvidence _settleFinalEvidenceForSuccessfulSavedValidation(
    ToolResultCompletionEvidence evidence, {
    required bool savedValidationSucceeded,
  }) {
    if (!savedValidationSucceeded || evidence.hasBlockingEvidence) {
      return evidence;
    }
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) {
      return evidence;
    }
    return evidence.settleForExecutionGenerations(
      mutationGeneration: conversation.mutationGeneration,
      verificationGeneration: conversation.mutationGeneration,
    );
  }

  void _reconcileGoalAutoContinueEvidenceForFinalization() {
    _latestGoalAutoContinueEvidence =
        ToolResultPromptBuilder.reconcileFinalizationEvidence(
          authoritativeEvidence: _latestGoalAutoContinueEvidence,
          completedToolResults: _latestCompletedToolResults,
          contentToolResults: _latestContentToolResults,
        );
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) {
      return;
    }
    _latestGoalAutoContinueEvidence = _latestGoalAutoContinueEvidence
        .settleForExecutionGenerations(
          mutationGeneration: conversation.mutationGeneration,
          verificationGeneration: conversation.verificationGeneration,
        );
  }

  @visibleForTesting
  void seedContentToolDedupeGuardsForTest({
    required String executedCallKey,
    required String seenCallHash,
  }) {
    _executedContentToolCalls.add(executedCallKey);
    _seenContentToolCallHashes.add(seenCallHash);
  }

  @visibleForTesting
  bool hasContentToolDedupeGuardsForTest({
    required String executedCallKey,
    required String seenCallHash,
  }) {
    return _executedContentToolCalls.contains(executedCallKey) &&
        _seenContentToolCallHashes.contains(seenCallHash);
  }

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

  /// The harness's verification-cadence verdict for the current conversation.
  ///
  /// Reuses [ExecutionSnapshotProjector], which already computes this for the
  /// execution snapshot shown to the model, so the continuation policy and the
  /// prompt cannot drift apart.
  VerificationCadence _currentVerificationCadence() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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
    required String finalizedAssistantResponse,
    required String languageCode,
  }) async {
    if (_isSchedulingGoalAutoContinue || !ref.mounted) {
      return;
    }

    final conversationsState = ref.read(conversationsNotifierProvider);
    final currentConversation = conversationsState.currentConversation;
    final goal = currentConversation?.goal;
    final currentConversationId = currentConversation?.id ?? conversationId;
    final evidence = _latestGoalAutoContinueEvidence;
    final tracker = currentConversationId == null
        ? null
        : _goalAutoContinueTrackers.putIfAbsent(
            currentConversationId,
            _GoalAutoContinueTracker.new,
          );

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
    if (currentConversationId == null) {
      _logGoalAutoContinueSkip('conversation id is unavailable');
      _clearGoalAutoContinueIndicator();
      return;
    }
    final savedTasks = currentConversation!.projectedExecutionTasks;
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
      verificationCadence: _currentVerificationCadence(),
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
        decision: 'stop_and_block',
        reason: decision.reason,
        goal: goal,
        nextTurnNumber: goal?.turnsUsed,
        effectiveTurnBudget: _effectiveGoalAutoContinueBudget(goal),
        tracker: tracker,
        evidence: evidence,
        safeBoundary: safeBoundary,
      );
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
      _clearGoalAutoContinueIndicator();
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
      final noticeKey = _goalAutoContinueNoticeKeyForStop(decision.stopCause);
      if (noticeKey != null) {
        if (_goalAutoContinueBudgetNotifiedConversations.add(
          currentConversationId,
        )) {
          await _recordGoalAutoContinueSessionLog(
            decision: _goalAutoContinueSessionDecisionForStop(
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
          appLog(
            '[GoalAutoContinue] stopped; goal remains active for '
            'manual continuation. conversation=$currentConversationId',
          );
          state = state.copyWith(goalAutoContinueNotice: noticeKey);
        }
      } else if (goal?.isActive == true && goal!.autoContinue) {
        await _recordGoalAutoContinueSessionLog(
          decision: 'skip',
          reason: decision.reason,
          goal: goal,
          nextTurnNumber: goal.turnsUsed,
          effectiveTurnBudget: _effectiveGoalAutoContinueBudget(goal),
          tracker: tracker,
          evidence: evidence,
          safeBoundary: safeBoundary,
        );
      }
      _clearGoalAutoContinueIndicator();
      return;
    }

    if (!ref.mounted || state.isLoading || _queuedChatMessages.isNotEmpty) {
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
    final continuationPrompt = _buildGoalAutoContinuePrompt(
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
      decision: 'continue',
      reason: decision.reason,
      goal: goal,
      nextTurnNumber: decision.nextTurnNumber,
      effectiveTurnBudget: decision.effectiveTurnBudget,
      tracker: tracker,
      evidence: evidence,
      safeBoundary: safeBoundary,
    );

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
      final continuationFuture = sendHiddenPrompt(
        continuationPrompt,
        isVoiceMode: false,
        languageCode: languageCode,
        persistAssistantResponse: true,
        preserveGoalAutoContinueEvidence: true,
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
      _clearGoalAutoContinueIndicator();
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

  String? _goalAutoContinueNoticeKeyForStop(
    GoalAutoContinueStopCause? stopCause,
  ) {
    switch (stopCause) {
      case GoalAutoContinueStopCause.turnBudget:
      case GoalAutoContinueStopCause.goalBudget:
        return 'chat.goal_auto_continue_budget_reached';
      case GoalAutoContinueStopCause.noProgress:
        return 'chat.goal_auto_continue_no_progress';
      case null:
        return null;
    }
  }

  String _goalAutoContinueSessionDecisionForStop(
    GoalAutoContinueStopCause? stopCause,
  ) {
    return switch (stopCause) {
      GoalAutoContinueStopCause.noProgress => 'no_progress_stop',
      GoalAutoContinueStopCause.turnBudget ||
      GoalAutoContinueStopCause.goalBudget => 'budget_stop',
      null => 'skip',
    };
  }

  GoalAutoContinueSafeBoundary _goalAutoContinueSafeBoundaryFromState() {
    return GoalAutoContinueSafeBoundary(
      isLoading: state.isLoading,
      hasQueuedUserInput:
          _queuedChatMessages.isNotEmpty || state.queuedMessages.isNotEmpty,
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

  String _buildGoalAutoContinuePrompt({
    required ConversationGoal goal,
    required ToolResultCompletionEvidence evidence,
    required ExecutionSnapshot executionSnapshot,
    required String? repairContract,
    required bool repairNoMutationRetry,
    required GoalAutoContinueCapabilityProfile capabilityProfile,
    required int nextTurnNumber,
    required int effectiveTurnBudget,
    required String languageCode,
  }) {
    final normalizedLanguageCode = languageCode.trim().isEmpty
        ? 'en'
        : languageCode.trim();
    return [
      'Automatic goal continuation $nextTurnNumber/$effectiveTurnBudget.',
      '',
      'Goal objective:',
      goal.objective.trim(),
      '',
      'Concrete incomplete evidence from the previous turn:',
      evidence.summary,
      if (executionSnapshot.hasContract) ...[
        '',
        'Current execution snapshot:',
        '<execution_snapshot>',
        executionSnapshot.toPromptContext(),
        '</execution_snapshot>',
      ],
      if (repairContract != null) ...['', repairContract],
      if (repairNoMutationRetry) ...[
        '',
        'The previous constrained repair turn ended without a file mutation. '
            'This is the only retry. Do not narrate another future action. '
            'Use read_file only if essential, then call exactly one available '
            'write, edit, or delete tool in this turn. If no safe mutation is '
            'possible, state the concrete blocker instead.',
      ],
      '',
      if (capabilityProfile == GoalAutoContinueCapabilityProfile.repair) ...[
        'This is a repair-only continuation. Use the available file tools to '
            'make the contract repair now. Do not run a verification command; '
            'the harness will replay the saved verifier after a mutation.',
      ] else if (capabilityProfile ==
          GoalAutoContinueCapabilityProfile.validation) ...[
        'This is a validation-only continuation. Only verification-effect '
            'commands are accepted; inspection, setup, and shell-based file '
            'mutation will be rejected. Run the available project verifier '
            'now. A verifier request that was '
            'left unexecuted by the previous tool-loop boundary must be '
            'retried before any other work. Finish immediately if it succeeds. '
            'If it fails, report the concrete failure and finish this turn; '
            'the next bounded continuation will provide repair tools.',
      ] else if (evidence.hasUnexecutedActionClaim) ...[
        'The previous answer claimed file or command actions without tool '
            'evidence. Do not repeat or summarize those claims. Use the '
            'available file and command tools now to perform the requested '
            'work, then verify it with execution evidence.',
      ] else
        'Continue the work now. Use the available diagnostics and tools to '
            'make progress, then verify the result when a verification path '
            'is available. If you are genuinely blocked, state the blocking '
            'condition clearly instead of retrying the same action.',
      'Do not end this turn by saying you will inspect, edit, or verify later; '
          'call an available tool now unless you are already at a concrete '
          'blocking condition.',
      '',
      'Keep the visible response language aligned with language code '
          '"$normalizedLanguageCode".',
    ].join('\n');
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
    await ref
        .read(llmSessionLogStoreProvider)
        .recordGoalAutoContinue(
          context: _currentLlmSessionLogContext(),
          decision: decision,
          reason: reason,
          at: DateTime.now(),
          goalId: goal?.id,
          nextTurnNumber: nextTurnNumber,
          effectiveTurnBudget: effectiveTurnBudget,
          consecutiveAutoContinuations: tracker?.consecutiveAutoContinuations,
          evidence: {
            'summary': evidence.summary,
            'hasIncompleteEvidence': evidence.hasIncompleteEvidence,
            // The cadence is the other half of the continuation gate, and its
            // absence here made a skip undiagnosable from the log alone: a real
            // session showed cadence `required` in the prompt one second before
            // auto-continue skipped, with no way to tell what value the policy
            // actually received. See
            // docs/session_cfaa8297_cadence_not_observable_2026-07-22.md.
            'verificationCadence': _currentVerificationCadence().name,
            'mutationGeneration': ref
                .read(conversationsNotifierProvider)
                .currentConversation
                ?.mutationGeneration,
            'verificationGeneration': ref
                .read(conversationsNotifierProvider)
                .currentConversation
                ?.verificationGeneration,
            'hasBlockingEvidence': evidence.hasBlockingEvidence,
            'hasUnexecutedActionClaim': evidence.hasUnexecutedActionClaim,
            'safeBoundaryVeto': safeBoundary.firstVetoReason,
            'noProgressStreak': tracker?.noProgressStreak ?? 0,
            'diagnosticRepairContinuations':
                tracker?.diagnosticRepairContinuations ?? 0,
            'consecutiveValidationMisses':
                tracker?.consecutiveValidationMisses ?? 0,
            'diagnosticRepairExtensionUsed':
                tracker?.diagnosticRepairExtensionUsed ?? false,
            'previousUnresolvedErrorCount':
                tracker?.previousEvidence?.unresolvedErrorCount,
            'diagnosticSignaturePresent':
                evidence.diagnosticSignature.isNotEmpty,
            'identicalDiagnosticSignatureStreak':
                tracker?.identicalDiagnosticSignatureStreak ?? 0,
            'boundedToolLoopExhausted': evidence.boundedToolLoopExhausted,
            'unexecutedToolNames': evidence.unexecutedToolNames,
            'unresolvedErrorCount': evidence.unresolvedErrorCount,
            'unresolvedErrorPaths': evidence.unresolvedErrorPaths,
            'unverifiedChangePaths': evidence.unverifiedChangePaths,
            'mutatedWithoutExecution':
                evidence.mutatedWithoutExecutionVerification,
          },
        );
  }

  /// Handles the `update_goal` tool call (LL35). Thin adapter: gathers the
  /// current goal and this run's completion evidence and delegates the verdict
  /// to [GoalUpdateAckResolver]. Shadow phase — the goal-status transition is
  /// still owned by [ConversationGoalProgressInference] at turn end; this only
  /// returns the ack the model reads.
  Future<McpToolResult> handleUpdateGoal(ToolCallInfo toolCall) async {
    final ack = const GoalUpdateAckResolver().resolveCall(
      toolCall: toolCall,
      goal: ref.read(conversationsNotifierProvider).currentConversation?.goal,
      evidence: _latestGoalAutoContinueEvidence,
    );
    // Shadow: remember a completion verdict so turn-end can compare it against
    // the lexical path. Progress/blocker/inactive are not completion claims.
    if (ack.isCompletionClaim) {
      _shadowGoalToolCompletionOutcome = ack.outcome;
    }
    return ack.toToolResult(toolCall.name);
  }

  /// Records where the explicit `update_goal` tool and the lexical completion
  /// inference disagreed this turn (LL35 shadow). Adds a stable transform
  /// label so triage can count how often each path decides completion the
  /// other misses, before the lexical path is removed.
  void recordGoalCompletionShadow({required bool lexicalCompleted}) {
    final disagreement = GoalCompletionShadow.compare(
      toolCompletionOutcome: _shadowGoalToolCompletionOutcome,
      lexicalCompleted: lexicalCompleted,
    );
    if (disagreement != null) {
      _appliedTurnTransforms.add(GoalCompletionShadow.labelFor(disagreement));
    }
    _shadowGoalToolCompletionOutcome = null;
  }
}
