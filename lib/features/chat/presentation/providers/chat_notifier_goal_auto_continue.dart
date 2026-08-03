// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierGoalAutoContinue on ChatNotifier {
  TurnRuntimeProductionComposition _buildTurnRuntimeComposition(
    ConversationsNotifier conversationsNotifier,
  ) => TurnRuntimeProductionComposition(
    ownerLease: _turnRuntimeOwnerLease,
    conversationGoalStore: ConversationsNotifierGoalRuntimeStore(
      notifier: conversationsNotifier,
    ),
    trackerRegistry: _goalAutoContinueTrackerRegistry,
    safeBoundary: _turnRuntimeGoalSafeBoundary,
  );

  TurnRuntimeProductionScope _createGoalContinuationRuntimeScope(
    ChatTurnOwner owner,
  ) {
    return _turnRuntimeComposition.create(
      owner: owner,
      loggingSettingsEnabled: _settings.enableLlmSessionLogs,
    );
  }

  GoalAutoContinueConversationTaskSnapshot? _goalTrackerContext({
    required ChatTurnOwner owner,
    Conversation? conversation,
  }) {
    final ownerConversation =
        conversation ?? _conversationForId(owner.conversationId);
    if (ownerConversation == null ||
        ownerConversation.id != owner.conversationId) {
      return null;
    }
    return (
      owner: owner,
      workspaceMode: ownerConversation.workspaceMode,
      activeTaskId: ConversationPlanExecutionCoordinator.executionFocusTask(
        ownerConversation,
      )?.id.trim(),
      mutationGeneration: ownerConversation.mutationGeneration,
      verificationGeneration: ownerConversation.verificationGeneration,
    );
  }

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
    final context = _goalTrackerContext(
      owner: owner,
      conversation: conversation,
    );
    if (context == null) return;
    final observation = _goalAutoContinueTrackerRegistry
        .recordCommandDiagnostic(
          context: context,
          commandKey: commandKey,
          toolResult: toolResult,
        );
    if (observation == null) {
      return;
    }
    appLog(
      '[CommandDiagnostic] observed; '
      'signatureStreak=${observation.streak}; '
      'signatureChanged=${observation.signatureChanged}',
    );
    if (observation.focusActivated) {
      appLog(
        '[CommandDiagnosticRepairFocus] activated; '
        'signatureStreak=${observation.streak}',
      );
    }
  }

  void _resetCommandDiagnosticStreak(ChatTurnOwner owner, String commandKey) {
    _goalAutoContinueTrackerRegistry.resetCommandDiagnostic(owner, commandKey);
  }

  CommandDiagnosticRepairFocus? _commandDiagnosticRepairFocusFor(
    Conversation? conversation,
  ) {
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding) {
      return null;
    }
    final context = _goalTrackerContext(
      owner: ChatTurnOwner(
        conversationId: conversation.id,
        interactionGeneration: _interactionGeneration,
      ),
      conversation: conversation,
    );
    return context == null
        ? null
        : _goalAutoContinueTrackerRegistry.commandDiagnosticRepairFocusFor(
            context,
          );
  }

  void _clearCommandDiagnosticRepairFocus(ChatTurnOwner owner) {
    _goalAutoContinueTrackerRegistry.clearCommandDiagnosticRepairFocus(owner);
  }

  void _recordExecutedVerifierReplayCandidate(
    ChatTurnOwner owner,
    ToolCallInfo toolCall,
  ) {
    final conversation = _conversationForId(owner.conversationId);
    final context = _goalTrackerContext(
      owner: owner,
      conversation: conversation,
    );
    if (context == null) return;
    _goalAutoContinueTrackerRegistry.recordExecutedVerifierReplayCandidate(
      context: context,
      toolCall: toolCall,
    );
  }

  @visibleForTesting
  void recordExecutedVerifierReplayCandidateForTest(
    ChatTurnOwner owner,
    ToolCallInfo toolCall,
  ) => _recordExecutedVerifierReplayCandidate(owner, toolCall);

  /// The diagnostic plateau length the turn reached, for canaries that need to
  /// assert the harness observed a plateau without depending on how many
  /// continuations the model happened to need.
  @visibleForTesting
  int commandDiagnosticStreakForTest(String conversationId) {
    final conversation = _conversationForId(conversationId);
    return _commandDiagnosticRepairFocusFor(conversation)?.streak ?? 0;
  }

  @visibleForTesting
  bool hasVerifierReplayCandidateForOwnerForTest(ChatTurnOwner owner) {
    final conversation = _conversationForId(owner.conversationId);
    if (conversation == null) {
      return false;
    }
    final context = _goalTrackerContext(
      owner: owner,
      conversation: conversation,
    );
    return context != null &&
        _goalAutoContinueTrackerRegistry.hasVerifierReplayCandidate(context);
  }

  @visibleForTesting
  bool isVerifierReplayEligibleForTest(ToolCallInfo toolCall) =>
      _goalAutoContinueTrackerRegistry.isReplayEligibleVerifierToolCall(
        toolCall,
      ) &&
      const ToolCapabilityClassifier()
              .classify(toolCall.name, arguments: toolCall.arguments)
              .commandEffect ==
          ToolCommandEffect.verification;

  ToolCallInfo? _takePostMutationVerifierReplay({
    required ToolResultCompletionEvidence evidence,
    required int interactionGeneration,
  }) {
    if (!evidence.mutatedWithoutExecutionVerification) {
      return null;
    }
    final owner = _turnOwnerForGeneration(interactionGeneration);
    final conversation = _conversationForGeneration(interactionGeneration);
    if (owner == null || conversation == null) return null;
    final context = _goalTrackerContext(
      owner: owner,
      conversation: conversation,
    );
    if (context == null) return null;
    return _goalAutoContinueTrackerRegistry
        .takePostMutationVerifierReplay(context: context, evidence: evidence)
        ?.toolCall;
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
    if (conversation != null) {
      _goalAutoContinueTrackerRegistry.update(
        owner,
        pendingRepairContractOutcome: false,
        pendingPostRepairReplayOutcome: true,
      );
    }
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
    _goalAutoContinueTrackerRegistry.resetConversation(conversationId);
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
      _turnRuntimeOwnerLease.isCurrent(owner);

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

    final runtimeScope = _createGoalContinuationRuntimeScope(owner);
    final runtime = runtimeScope.runtime;
    final goalContinuation = runtime.goalContinuation;
    bool ownerIsCurrent() => goalContinuation.ownerLease.isCurrent(owner);
    final currentConversation = goalContinuation.conversationGoal
        .conversationFor(owner);
    if (currentConversation == null) {
      _logGoalAutoContinueSkip('conversation id is unavailable');
      _applyTurnRuntimeGoalUiEffect(runtime.clearGoalIndicator());
      return;
    }
    final goal = currentConversation.goal;
    final currentConversationId = owner.conversationId;
    final initialTracker = goalContinuation.tracker.snapshotFor(owner);
    final safeBoundary = _goalAutoContinueSafeBoundaryFor(runtime);
    final plan = const GoalAutoContinueDecisionCoordinator().coordinate(
      GoalAutoContinueDecisionInput(
        owner: owner,
        ownerConversation: currentConversation,
        tracker: initialTracker,
        completionEvidence: evidence,
        finalizedAssistantResponse: finalizedAssistantResponse,
        safeBoundary: safeBoundary,
        isVoiceMode: _isVoiceMode,
      ),
    );
    if (plan.policyInput == null) {
      _logGoalAutoContinueSkip(plan.reason.detail);
      _applyTurnRuntimeGoalUiEffect(runtime.clearGoalIndicator());
      return;
    }
    final decision = plan.policyDecision;
    final delta = plan.trackerDelta;
    var tracker = initialTracker;

    if (decision.shouldBlock) {
      tracker = _applyGoalAutoContinueTrackerDelta(runtime, delta);
      final blockedReason =
          decision.blockedReason ??
          'Goal auto-continue stopped because the task made no progress.';
      await _recordGoalAutoContinueSessionLog(
        runtimeScope: runtimeScope,
        decision: 'stop_and_block',
        reason: decision.reason,
        goal: goal,
        nextTurnNumber: goal?.turnsUsed,
        effectiveTurnBudget: plan.effectiveTurnBudget,
        tracker: tracker,
        evidence: evidence,
        safeBoundary: safeBoundary,
      );
      if (!ownerIsCurrent()) return;
      appLog(
        '[GoalAutoContinue] stopAndBlock: ${decision.reason}; '
        'conversation=$currentConversationId; evidence=${evidence.summary}',
      );
      await goalContinuation.conversationGoal.markGoalStatus(
        TurnRuntimeGoalStatusUpdate(
          owner: owner,
          status: ConversationGoalStatus.blocked,
          blockedReason: blockedReason,
        ),
      );
      if (delta.removeTracker) {
        goalContinuation.tracker.removeTracker(owner);
      }
      if (ownerIsCurrent()) {
        _applyTurnRuntimeGoalUiEffect(runtime.clearGoalIndicator());
      }
      return;
    }

    if (!decision.shouldContinue) {
      tracker = _applyGoalAutoContinueTrackerDelta(runtime, delta);
      final budgetNoticePresented =
          delta.markBudgetNoticePresented &&
          goalContinuation.tracker.markBudgetNoticePresented(owner);
      _logGoalAutoContinueSkip(
        '${decision.reason}; conversation=$currentConversationId',
      );
      final noticeKey = plan.stopNotice;
      if (noticeKey != null) {
        if (budgetNoticePresented) {
          await _recordGoalAutoContinueSessionLog(
            runtimeScope: runtimeScope,
            decision: GoalAutoContinueStopPresentation.sessionDecisionFor(
              decision.stopCause,
            ),
            reason: decision.reason,
            goal: goal,
            nextTurnNumber: goal?.turnsUsed,
            effectiveTurnBudget: plan.effectiveTurnBudget,
            tracker: tracker,
            evidence: evidence,
            safeBoundary: safeBoundary,
          );
          if (!ownerIsCurrent()) return;
          appLog(
            '[GoalAutoContinue] stopped; goal remains active for '
            'manual continuation. conversation=$currentConversationId',
          );
          _applyTurnRuntimeGoalUiEffect(runtime.showGoalNotice(noticeKey));
        }
      } else if (goal?.isActive == true && goal!.autoContinue) {
        await _recordGoalAutoContinueSessionLog(
          runtimeScope: runtimeScope,
          decision: 'skip',
          reason: decision.reason,
          goal: goal,
          nextTurnNumber: goal.turnsUsed,
          effectiveTurnBudget: plan.effectiveTurnBudget,
          tracker: tracker,
          evidence: evidence,
          safeBoundary: safeBoundary,
        );
        if (!ownerIsCurrent()) return;
      }
      if (!ownerIsCurrent()) return;
      // Nothing left to schedule, and the harness cannot say the objective was
      // met. Ask the model once ([GoalCompletionElicitationPrompt] carries the
      // rationale and the measurement behind it); if that does not settle the
      // goal, fall through to `awaitingConfirmation` so a stranded goal stops
      // reading as one still working.
      if (plan.elicitationEligibility ==
          GoalCompletionElicitationEligibility.eligible) {
        await _elicitGoalCompletionReport(
          runtime: runtime,
          languageCode: languageCode,
          evidence: evidence,
        );
        return;
      }
      if (plan.shouldMarkAwaitingConfirmation) {
        await goalContinuation.conversationGoal.markGoalStatus(
          TurnRuntimeGoalStatusUpdate(
            owner: owner,
            status: ConversationGoalStatus.awaitingConfirmation,
          ),
        );
      }
      if (ownerIsCurrent()) {
        _applyTurnRuntimeGoalUiEffect(runtime.clearGoalIndicator());
      }
      return;
    }

    if (!ownerIsCurrent() ||
        state.isLoading ||
        _queuedChatMessages.pendingFor(owner.conversationId) > 0) {
      _logGoalAutoContinueSkip(
        'state changed before continuation dispatch; '
        'conversation=$currentConversationId',
      );
      _applyTurnRuntimeGoalUiEffect(runtime.clearGoalIndicator());
      return;
    }

    tracker = _applyGoalAutoContinueTrackerDelta(runtime, delta);
    final executionSnapshot = plan.executionSnapshot!;
    final repairContract = plan.repairContract;
    if (repairContract != null) {
      appLog(
        '[DiagnosticRepairContract] activated; '
        'signatureStreak=${tracker.identicalDiagnosticSignatureStreak}',
      );
    }
    final capabilityProfile = plan.capabilityProfile!;
    final limits = plan.continuationLimits!;
    final continuationPrompt = GoalAutoContinuePromptBuilder.build(
      goal: goal!,
      evidence: evidence,
      executionSnapshot: executionSnapshot,
      repairContract: repairContract,
      repairNoMutationRetry: decision.usesRepairNoMutationRetry,
      capabilityProfile: capabilityProfile,
      nextTurnNumber: limits.nextTurnNumber,
      effectiveTurnBudget: limits.effectiveTurnBudget,
      languageCode: languageCode,
    );

    await _recordGoalAutoContinueSessionLog(
      runtimeScope: runtimeScope,
      decision: 'continue',
      reason: decision.reason,
      goal: goal,
      nextTurnNumber: limits.nextTurnNumber,
      effectiveTurnBudget: limits.effectiveTurnBudget,
      tracker: tracker,
      evidence: evidence,
      safeBoundary: safeBoundary,
    );
    if (!ownerIsCurrent()) return;

    appLog(
      '[GoalAutoContinue] continue ${limits.nextTurnNumber}/'
      '${limits.effectiveTurnBudget}: ${decision.reason}; '
      'conversation=$currentConversationId; evidence=${evidence.summary}',
    );

    final dispatch = runtime.beginGoalContinuationDispatch(
      prompt: continuationPrompt,
      languageCode: languageCode,
      evidence: evidence,
      count: limits.nextTurnNumber,
      budget: limits.effectiveTurnBudget,
      replayVerifierImmediatelyAfterMutation:
          limits.replayVerifierImmediatelyAfterMutation,
      verifierOnlyContinuation: limits.verifierOnlyContinuation,
      allowedToolNames: limits.allowedToolNames,
    );
    if (dispatch == null) return;
    _isSchedulingGoalAutoContinue = true;
    try {
      if (!ownerIsCurrent()) return;
      _applyTurnRuntimeGoalUiEffect(dispatch.uiEffect);
      if (!ownerIsCurrent()) return;
      final continuationFuture = _dispatchTurnRuntimeHiddenTurn(
        dispatch.hiddenTurn,
      );
      _isSchedulingGoalAutoContinue = false;
      runtime.endGoalContinuationScheduling();
      await continuationFuture;
    } on Object catch (error, stackTrace) {
      goalContinuation.tracker.clearPendingRepairContract(owner);
      appLog(
        '[GoalAutoContinue] hidden continuation failed: '
        '${error.runtimeType}: $error',
      );
      appLog('[GoalAutoContinue] stackTrace: $stackTrace');
      if (ownerIsCurrent()) {
        _applyTurnRuntimeGoalUiEffect(runtime.clearGoalIndicator());
      }
    } finally {
      _isSchedulingGoalAutoContinue = false;
      runtime.endGoalContinuationScheduling();
    }
  }

  void _applyTurnRuntimeGoalUiEffect(TurnRuntimeGoalUiEffect effect) {
    if (!_isGoalAutoContinueOwnerCurrent(effect.owner)) return;
    switch (effect) {
      case TurnRuntimeClearGoalIndicator():
        _clearGoalAutoContinueIndicator();
      case TurnRuntimeShowGoalProgress(:final count, :final budget):
        state = state.copyWith(
          goalAutoContinueCount: count,
          goalAutoContinueBudget: budget,
          goalAutoContinueNotice: null,
        );
      case TurnRuntimeShowGoalNotice(:final noticeKey):
        state = state.copyWith(goalAutoContinueNotice: noticeKey);
    }
  }

  Future<void> _dispatchTurnRuntimeHiddenTurn(
    TurnRuntimeHiddenTurnRequest request,
  ) async {
    if (!_isGoalAutoContinueOwnerCurrent(request.owner)) return;
    await sendHiddenPrompt(
      request.prompt,
      isVoiceMode: false,
      languageCode: request.languageCode,
      persistAssistantResponse: true,
      initialGoalCompletionEvidence: request.evidence,
      replayVerifierImmediatelyAfterMutation:
          request.replayVerifierImmediatelyAfterMutation,
      verifierOnlyContinuation: request.verifierOnlyContinuation,
      allowedToolNames: request.allowedToolNames,
    );
  }

  GoalAutoContinueTrackerSnapshot _applyGoalAutoContinueTrackerDelta(
    TurnRuntime runtime,
    GoalAutoContinueTrackerDelta delta,
  ) => runtime.goalContinuation.tracker.applyDelta(runtime.owner, delta);

  GoalAutoContinueSafeBoundary _goalAutoContinueSafeBoundaryFor(
    TurnRuntime runtime,
  ) {
    _turnRuntimeGoalSafeBoundary.synchronizeVisibleState(
      ThreadScopedChatState.from(state),
      isLoading: state.isLoading,
      error: state.error,
    );
    return runtime.goalContinuation.safeBoundary.capture(runtime.owner);
  }

  /// Spend one hidden turn asking the model to settle a goal that has run dry.
  ///
  /// Restricted to `update_goal` so the turn cannot start new work. Persisted
  /// like an auto-continuation because finalization drops an unpersisted
  /// assistant response before the goal turn is recorded, which is where the
  /// tool's completion claim is read.
  Future<void> _elicitGoalCompletionReport({
    required TurnRuntime runtime,
    required String languageCode,
    required ToolResultCompletionEvidence evidence,
  }) async {
    final owner = runtime.owner;
    if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
    final dispatch = runtime.goalCompletionElicitationDispatch(
      languageCode: languageCode,
      evidence: evidence,
    );
    appLog('[GoalAutoContinue] eliciting a goal completion report');
    try {
      if (!_isGoalAutoContinueOwnerCurrent(owner)) return;
      _applyTurnRuntimeGoalUiEffect(dispatch.uiEffect);
      await _dispatchTurnRuntimeHiddenTurn(dispatch.hiddenTurn);
    } on Object catch (error) {
      appLog('[GoalAutoContinue] completion elicitation failed: $error');
    }
  }

  void _logGoalAutoContinueSkip(String reason) {
    appLog('[GoalAutoContinue] skip: $reason');
  }

  Future<void> _recordGoalAutoContinueSessionLog({
    required TurnRuntimeProductionScope runtimeScope,
    required String decision,
    required String reason,
    required ConversationGoal? goal,
    required int? nextTurnNumber,
    required int? effectiveTurnBudget,
    required GoalAutoContinueTrackerSnapshot tracker,
    required ToolResultCompletionEvidence evidence,
    required GoalAutoContinueSafeBoundary safeBoundary,
  }) async {
    if (!runtimeScope.loggingEnabled) return;
    final runtime = runtimeScope.runtime;
    final owner = runtime.owner;
    final conversation = runtime.goalContinuation.conversationGoal
        .conversationFor(owner);
    final record = const GoalContinuationLogRecordBuilder().buildAutoContinue(
      owner: owner,
      decision: decision,
      reason: reason,
      goal: goal,
      nextTurnNumber: nextTurnNumber,
      effectiveTurnBudget: effectiveTurnBudget,
      tracker: tracker,
      evidence: evidence,
      verificationCadence: _verificationCadenceFor(conversation),
      mutationGeneration: conversation?.mutationGeneration,
      verificationGeneration: conversation?.verificationGeneration,
      safeBoundary: safeBoundary,
    );
    runtimeScope.configureLogging(
      logStore: ref.read(llmSessionLogStoreProvider),
      context: _buildLlmSessionLogContext(
        targetConversationId: record.owner.conversationId,
      ),
    );
    await runtime.goalContinuation.log.record(record);
  }

  /// Handles `update_goal` against the exact owner's current-turn results.
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
    final outcome = const GoalUpdateToolHandler().handleCall(
      owner: owner,
      toolCall: toolCall,
      goal: _conversationForId(owner.conversationId)?.goal,
      toolResults: _turnToolResults.completed(owner),
      completionEvidence:
          _goalCompletionEvidence.evidenceFor(owner) ??
          const ToolResultCompletionEvidence(),
    );
    final shadowOutcome = outcome.shadowOutcome;
    if (shadowOutcome != null) {
      _turnEnd.setGoalOutcome(owner, shadowOutcome);
    }
    if (outcome.completionAccepted) {
      _turnEnd.markGoalClaimed(owner);
    }
    return outcome.toolResult;
  }

  Future<void> _recordGoalCompletionShadow({
    required bool lexicalCompleted,
    required ChatTurnOwner owner,
    required LlmSessionLogContext context,
    required GoalUpdateAckOutcome? toolCompletionOutcome,
  }) async {
    final record = const GoalContinuationLogRecordBuilder()
        .buildCompletionShadow(
          owner: owner,
          lexicalCompleted: lexicalCompleted,
          toolCompletionOutcome: toolCompletionOutcome,
        );
    if (record == null) return;
    final loggingEnabled = LlmSessionLogStore.isEnabled(
      settingsEnabled: _settings.enableLlmSessionLogs,
    );
    if (!loggingEnabled) return;
    await ref
        .read(llmSessionLogStoreProvider)
        .recordGoalCompletionShadow(
          context: context,
          at: DateTime.now(),
          label: record.label,
          toolOutcome: record.toolOutcome,
          lexicalCompleted: record.lexicalCompleted,
          turnId: record.turnId,
        );
  }
}
