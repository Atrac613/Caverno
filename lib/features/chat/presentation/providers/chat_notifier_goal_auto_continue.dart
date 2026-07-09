// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

const _goalAutoContinuePolicy = ConversationGoalAutoContinuePolicy();

final class _GoalAutoContinueTracker {
  _GoalAutoContinueTracker({
    this.consecutiveAutoContinuations = 0,
    this.noProgressStreak = 0,
    this.previousEvidence,
  });

  int consecutiveAutoContinuations;
  int noProgressStreak;
  ToolResultCompletionEvidence? previousEvidence;
}

extension ChatNotifierGoalAutoContinue on ChatNotifier {
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
    final decision = _goalAutoContinuePolicy.decide(
      GoalAutoContinuePolicyInput(
        goal: goal,
        safeBoundary: _goalAutoContinueSafeBoundaryFromState(),
        evidence: evidence,
        consecutiveAutoContinuations:
            tracker?.consecutiveAutoContinuations ?? 0,
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
        'conversation=$currentConversationId',
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
      nextTurnNumber: decision.nextTurnNumber,
      effectiveTurnBudget: decision.effectiveTurnBudget,
      languageCode: languageCode,
    );

    if (tracker != null) {
      tracker.noProgressStreak = candidateNoProgressStreak;
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
      tracker?.previousEvidence = evidence;
      final continuationFuture = sendHiddenPrompt(
        continuationPrompt,
        isVoiceMode: false,
        languageCode: languageCode,
        persistAssistantResponse: true,
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
            'boundedToolLoopExhausted': evidence.boundedToolLoopExhausted,
            'unexecutedToolNames': evidence.unexecutedToolNames,
            'unresolvedErrorCount': evidence.unresolvedErrorCount,
            'unresolvedErrorPaths': evidence.unresolvedErrorPaths,
            'unverifiedChangePaths': evidence.unverifiedChangePaths,
          },
        );
  }
}
