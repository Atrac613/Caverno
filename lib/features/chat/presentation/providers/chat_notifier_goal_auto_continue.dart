// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

const _goalAutoContinuePolicy = ConversationGoalAutoContinuePolicy();

final class _GoalAutoContinueTracker {
  _GoalAutoContinueTracker({
    this.consecutiveAutoContinuations = 0,
    this.diagnosticRepairContinuations = 0,
    this.diagnosticRepairExtensionUsed = false,
    this.noProgressStreak = 0,
    this.previousEvidence,
  });

  int consecutiveAutoContinuations;
  int diagnosticRepairContinuations;
  bool diagnosticRepairExtensionUsed;
  int noProgressStreak;
  ToolResultCompletionEvidence? previousEvidence;
}

extension ChatNotifierGoalAutoContinue on ChatNotifier {
  Future<bool> _finishExplicitTerminalSuccess(
    String? message, {
    required int interactionGeneration,
  }) async {
    if (message == null ||
        !await _acceptTerminalSuccessForCurrentGeneration()) {
      return false;
    }
    appLog('[Tool] Terminal success accepted for current generation');
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

    final candidateNoProgressStreak = _candidateGoalAutoContinueProgressStreak(
      tracker: tracker,
      evidence: evidence,
    );
    final previousEvidence = tracker?.previousEvidence;
    final diagnosticEvidenceImproved =
        previousEvidence != null &&
        evidence.hasDiagnosticEvidence &&
        evidence.compareProgress(previousEvidence) ==
            GoalEvidenceProgress.improved;
    final decision = _goalAutoContinuePolicy.decide(
      GoalAutoContinuePolicyInput(
        goal: goal,
        safeBoundary: _goalAutoContinueSafeBoundaryFromState(),
        evidence: evidence,
        consecutiveAutoContinuations:
            tracker?.consecutiveAutoContinuations ?? 0,
        diagnosticRepairContinuations:
            tracker?.diagnosticRepairContinuations ?? 0,
        diagnosticRepairExtensionUsed:
            tracker?.diagnosticRepairExtensionUsed ?? false,
        diagnosticEvidenceImproved: diagnosticEvidenceImproved,
        noProgressStreak: candidateNoProgressStreak,
        finalAnswerEndsWithQuestion: _endsWithQuestionMark(
          finalizedAssistantResponse,
        ),
      ),
    );

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
      if (noticeKey != null &&
          _goalAutoContinueBudgetNotifiedConversations.add(
            currentConversationId,
          )) {
        await _recordGoalAutoContinueSessionLog(
          decision: _goalAutoContinueSessionDecisionForStop(decision.stopCause),
          reason: decision.reason,
          goal: goal,
          nextTurnNumber: goal?.turnsUsed,
          effectiveTurnBudget: _effectiveGoalAutoContinueBudget(goal),
          tracker: tracker,
          evidence: evidence,
        );
        appLog(
          '[GoalAutoContinue] stopped; goal remains active for '
          'manual continuation. conversation=$currentConversationId',
        );
        state = state.copyWith(goalAutoContinueNotice: noticeKey);
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

    final continuationPrompt = _buildGoalAutoContinuePrompt(
      goal: goal!,
      evidence: evidence,
      executionSnapshot: const ExecutionSnapshotProjector().project(
        currentConversation,
      ),
      nextTurnNumber: decision.nextTurnNumber,
      effectiveTurnBudget: decision.effectiveTurnBudget,
      languageCode: languageCode,
    );

    if (tracker != null) {
      tracker.noProgressStreak = candidateNoProgressStreak;
      if (decision.usesDiagnosticRepairExtension) {
        tracker.diagnosticRepairExtensionUsed = true;
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
      tracker?.previousEvidence = evidence;
      final continuationFuture = sendHiddenPrompt(
        continuationPrompt,
        isVoiceMode: false,
        languageCode: languageCode,
        persistAssistantResponse: true,
        preserveGoalAutoContinueEvidence: true,
      );
      _isSchedulingGoalAutoContinue = false;
      await continuationFuture;
    } on Object catch (error, stackTrace) {
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
      '',
      'Continue the work now. Use the available diagnostics and tools to make '
          'progress, then verify the result when a verification path is '
          'available. If you are genuinely blocked, state the blocking '
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
            'hasBlockingEvidence': evidence.hasBlockingEvidence,
            'noProgressStreak': tracker?.noProgressStreak ?? 0,
            'diagnosticRepairContinuations':
                tracker?.diagnosticRepairContinuations ?? 0,
            'diagnosticRepairExtensionUsed':
                tracker?.diagnosticRepairExtensionUsed ?? false,
            'previousUnresolvedErrorCount':
                tracker?.previousEvidence?.unresolvedErrorCount,
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
}
