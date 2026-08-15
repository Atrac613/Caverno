// Same-library ChatNotifier extension for final-answer claim recovery.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierUnexecutedActionRecovery on ChatNotifier {
  Future<ChatCompletionResult?> _requestFinalAnswerRecoveryCompletion({
    required ChatTurnOwner owner,
    required ToolResultInfo feedback,
    required String transformId,
    required String logLabel,
    required String logMessage,
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    void Function()? onBlockingFeedbackPrepared,
  }) async {
    final promptFeedback = await _toolResultArtifactStore.persistIfLarge(
      feedback,
      conversationId: owner.conversationId,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != owner) {
      return null;
    }
    batchToolResults.add(promptFeedback);
    executedToolResults.add(promptFeedback);
    onBlockingFeedbackPrepared?.call();
    _turnEnd.addTransform(owner, transformId);
    appLog(logMessage);
    _appendToLastMessageForGeneration(interactionGeneration, '<think>');
    try {
      return await _createToolResultCompletionWithContextRetry(
        logLabel: logLabel,
        interactionGeneration: interactionGeneration,
        buildMessages: (forceCompaction) => _prepareMessagesForLLM(
          forceCompaction: forceCompaction,
          toolDefinitionsOverride: tools,
          interactionGeneration: interactionGeneration,
        ),
        toolResults: [promptFeedback],
        assistantContent: candidateResponse,
        tools: tools,
      );
    } finally {
      if (_isCurrentInteractionGeneration(interactionGeneration) &&
          _turnOwnerForGeneration(interactionGeneration) == owner) {
        _removeTrailingThinkTagForGeneration(interactionGeneration);
      }
    }
  }

  Future<bool> _applyFinalAnswerRecoveryResult({
    required Future<ChatCompletionResult?> result,
    required String streamedFinalAnswer,
    required String toolCallLogMessage,
    required List<Map<String, dynamic>> tools,
    required bool toolSearchEnabled,
    required Set<String> activeToolNames,
    required List<Map<String, dynamic>>? stableToolDefinitions,
    required Map<String, int> verificationFailureCounts,
    required Set<String> transcriptRepairSignatures,
    required int interactionGeneration,
  }) async {
    final recoveryResult = await result;
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        !ref.mounted) {
      return true;
    }
    if (recoveryResult == null) return false;
    if (recoveryResult.hasToolCalls) {
      appLog(toolCallLogMessage);
      await _executeToolCalls(
        recoveryResult.toolCalls!,
        assistantContent: recoveryResult.content.isNotEmpty
            ? recoveryResult.content
            : streamedFinalAnswer,
        toolSearchEnabled: toolSearchEnabled,
        selectedToolNames: activeToolNames,
        stableToolDefinitions: stableToolDefinitions,
        completionVerificationFailureCounts: verificationFailureCounts,
        narratedTranscriptRepairSignatures: transcriptRepairSignatures,
        interactionGeneration: interactionGeneration,
      );
      return true;
    }
    final response = recoveryResult.content.trim();
    if (response.isNotEmpty) {
      _appendRecoveredAssistantResponse(
        response,
        interactionGeneration: interactionGeneration,
      );
    }
    return false;
  }

  void _appendUnexecutedToolRequestNoticeForContentIfNeeded({
    required ChatTurnOwner owner,
    required int interactionGeneration,
    required String content,
    required List<ToolResultInfo> toolResults,
  }) {
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != owner) {
      return;
    }
    final analysis = const UnexecutedFinalAnswerToolRequestPolicy().analyze(
      UnexecutedFinalAnswerToolRequestInput(
        content: content,
        existingToolResults: toolResults,
        hasTimedOutCommandResult: _hasTimedOutCommandResult(toolResults),
        hasFailedCommandValidation: _toolResultsContainFailedCommandValidation(
          toolResults,
        ),
        hasUnexecutedCommandActionResult: _claims
            .hasUnexecutedCommandActionResult(toolResults),
        hasUnexecutedFileSideEffectResult: _claims
            .hasUnexecutedFileSideEffectResult(toolResults),
        hasSuccessfulFileMutationEvidence: toolResults.any(
          (toolResult) =>
              _fileMutationEvidencePolicy.isMutationToolName(toolResult.name) &&
              _fileMutationEvidencePolicy.isSuccessfulResult(toolResult),
        ),
        hasSuccessfulCommandExecutionEvidence: _claims
            .hasSuccessfulCommandExecutionResult(toolResults),
      ),
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != owner) {
      return;
    }
    toolResults.addAll(analysis.newToolResults);
    final exitReason = analysis.exitReason;
    if (exitReason != null) {
      _turnEnd.setHint(owner, exitReason);
    }
    final transformId = analysis.transformId;
    if (transformId != null) {
      _turnEnd.addTransform(owner, transformId);
    }
    if (!analysis.appendNotice) return;

    final currentContent = _lastMessageContentForGeneration(
      interactionGeneration,
    );
    if (currentContent == null ||
        currentContent.contains(analysis.noticeText)) {
      return;
    }
    _replaceLastMessageContentForGeneration(
      interactionGeneration,
      '${currentContent.trimRight()}\n\n${analysis.noticeText}',
    );
  }

  /// Revives the tool loop when the answer describes a command run that no
  /// tool result backs, instead of only stamping the answer unverified.
  ///
  /// Measured before this existed: 25 of 130 turn exits in the corpus carried
  /// the unverified notice and none of them had a recovery attempt in the same
  /// turn, because the older recovery is gated on the user typing "continue"
  /// or 続けて. Real replies never say that.
  Future<ChatCompletionResult?> _requestUnexecutedCommandActionRetry({
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required Set<String>? allowedToolNames,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    void Function()? onBlockingFeedbackPrepared,
  }) async {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return null;
    final disposition = _unexecutedCommandRetries.evaluate(
      UnexecutedCommandActionRetryInput(
        owner: owner,
        ownerToolResults: executedToolResults,
        offersCommandExecution: _toolCallExecutionPolicy.offersCommandExecution(
          allowedToolNames,
        ),
        hasSuccessfulCommandExecution: _claims
            .hasSuccessfulCommandExecutionResult(executedToolResults),
        fencedToolArguments: const FencedToolArgumentsDetector().detect(
          candidateResponse,
        ),
        attemptedOwners: _unexecutedCommandRetryOwners,
        feedbackId:
            'unexecuted_command_action_retry_'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final plan = disposition.plan;
    if (plan == null) return null;
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != plan.owner) {
      return null;
    }
    if (!_unexecutedCommandRetryOwners.add(
      _unexecutedCommandRetries.ownerKey(plan.owner),
    )) {
      return null;
    }

    return _requestFinalAnswerRecoveryCompletion(
      owner: plan.owner,
      feedback: plan.feedback,
      transformId: 'unexecuted_command_action_retry',
      logLabel: 'unexecuted command action retry',
      logMessage:
          '[UnexecutedCommand] Answer described a command with no result; '
          'asking for the call or the blocker',
      candidateResponse: candidateResponse,
      executedToolResults: executedToolResults,
      batchToolResults: batchToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
      onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
    );
  }

  /// Applies the unexecuted-command retry to a streamed final answer. Returns
  /// true when the caller must stop.
  Future<bool> _applyUnexecutedCommandActionRetryToStreamedFinalAnswer({
    required String streamedFinalAnswer,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required Set<String>? allowedToolNames,
    required List<Map<String, dynamic>> tools,
    required bool toolSearchEnabled,
    required Set<String> activeToolNames,
    required List<Map<String, dynamic>>? stableToolDefinitions,
    required Map<String, int> verificationFailureCounts,
    required Set<String> transcriptRepairSignatures,
    required int interactionGeneration,
    required void Function() onBlockingFeedbackPrepared,
  }) async {
    return _applyFinalAnswerRecoveryResult(
      result: _requestUnexecutedCommandActionRetry(
        candidateResponse: streamedFinalAnswer,
        executedToolResults: executedToolResults,
        batchToolResults: batchToolResults,
        allowedToolNames: allowedToolNames,
        tools: tools,
        interactionGeneration: interactionGeneration,
        onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
      ),
      streamedFinalAnswer: streamedFinalAnswer,
      toolCallLogMessage: '[UnexecutedCommand] Retry requested tool calls',
      tools: tools,
      toolSearchEnabled: toolSearchEnabled,
      activeToolNames: activeToolNames,
      stableToolDefinitions: stableToolDefinitions,
      verificationFailureCounts: verificationFailureCounts,
      transcriptRepairSignatures: transcriptRepairSignatures,
      interactionGeneration: interactionGeneration,
    );
  }

  /// Revives the tool loop when this turn blocked a production release for
  /// missing approval, the user granted it, and the turn is ending without the
  /// command ever being re-issued.
  ///
  /// Unlike the transcript repair below, nothing here reads the answer text:
  /// the trigger is the guard's own structured block payload, the ledger of
  /// commands this owner executed, and the release-approval evidence. An
  /// assistant that says nothing and one that says "release started" are
  /// treated identically, because neither ran anything.
  Future<ChatCompletionResult?> _requestBlockedProductionReleaseRetry({
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    void Function()? onBlockingFeedbackPrepared,
  }) async {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return null;
    final disposition = _blockedReleaseRetries.evaluate(
      BlockedProductionReleaseRetryInput(
        owner: owner,
        ownerToolResults: executedToolResults,
        ownerExecutedCommands: _turnToolResults.commands(owner),
        approvalGranted: _productionReleaseApprovals
            .evidenceFor(interactionGeneration)
            .approved,
        pendingBlockedRelease:
            _productionReleaseApprovals.pendingRelease(owner.conversationId) ??
            _blockedReleaseRetries.blockedReleaseFromToolResults(
              executedToolResults,
            ),
        attemptedSignatures: _blockedReleaseRetrySignatures,
        feedbackId:
            'blocked_production_release_retry_'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final plan = disposition.plan;
    if (plan == null) {
      final reason = disposition.noPlanReason;
      if (reason == BlockedProductionReleaseRetryNoPlanReason.approvalMissing) {
        appLog(
          '[ReleaseRetry] Release stayed blocked: the turn holds no approval '
          'evidence, so the pause is the correct outcome',
        );
      }
      return null;
    }
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != plan.owner) {
      return null;
    }
    if (!_blockedReleaseRetrySignatures.add(plan.signature)) return null;
    // One prompt is all this block gets. Whether the model issues the call or
    // not, the conversation stops owing a retry for it.
    _productionReleaseApprovals.removePendingRelease(plan.owner.conversationId);

    return _requestFinalAnswerRecoveryCompletion(
      owner: plan.owner,
      feedback: plan.feedback,
      transformId: 'blocked_production_release_retry',
      logLabel: 'blocked production release retry',
      logMessage:
          '[ReleaseRetry] Approved release "${plan.command}" was never issued; '
          'asking the model to run it',
      candidateResponse: candidateResponse,
      executedToolResults: executedToolResults,
      batchToolResults: batchToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
      onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
    );
  }

  /// Applies the blocked-release retry to a streamed final answer. Returns true
  /// when the caller must stop: the retry re-entered the tool loop, or the
  /// generation was cancelled mid-retry.
  Future<bool> _applyBlockedProductionReleaseRetryToStreamedFinalAnswer({
    required String streamedFinalAnswer,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required List<Map<String, dynamic>> tools,
    required bool toolSearchEnabled,
    required Set<String> activeToolNames,
    required List<Map<String, dynamic>>? stableToolDefinitions,
    required Map<String, int> verificationFailureCounts,
    required Set<String> transcriptRepairSignatures,
    required int interactionGeneration,
    required void Function() onBlockingFeedbackPrepared,
  }) async {
    return _applyFinalAnswerRecoveryResult(
      result: _requestBlockedProductionReleaseRetry(
        candidateResponse: streamedFinalAnswer,
        executedToolResults: executedToolResults,
        batchToolResults: batchToolResults,
        tools: tools,
        interactionGeneration: interactionGeneration,
        onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
      ),
      streamedFinalAnswer: streamedFinalAnswer,
      toolCallLogMessage: '[ReleaseRetry] Retry requested tool calls',
      tools: tools,
      toolSearchEnabled: toolSearchEnabled,
      activeToolNames: activeToolNames,
      stableToolDefinitions: stableToolDefinitions,
      verificationFailureCounts: verificationFailureCounts,
      transcriptRepairSignatures: transcriptRepairSignatures,
      interactionGeneration: interactionGeneration,
    );
  }

  /// Revives the tool loop when a completion answer presents a terminal
  /// transcript whose commands were never executed this turn (fabricated
  /// verification evidence). The feedback asks the model to actually run the
  /// narrated commands — if the claim was true the run proves it, if not the
  /// failure surfaces — instead of merely stamping the answer as unverified.
  Future<ChatCompletionResult?>
  _requestNarratedTranscriptRepairForCompletionClaim({
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required Set<String> attemptedSignatures,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    void Function()? onBlockingFeedbackPrepared,
  }) async {
    final ownerSnapshot = _turnOwnerSnapshotForGeneration(
      interactionGeneration,
    );
    if (ownerSnapshot == null) return null;
    final disposition = _transcriptRepairs.evaluate(
      NarratedTranscriptRepairInput(
        owner: ownerSnapshot.owner,
        verificationEnabled: _codingVerificationEnabledFor(
          CodingVerificationTrigger.completionClaim,
        ),
        isCodingWorkspaceOrMode: ownerSnapshot.isCodingWorkspaceOrMode,
        isPlanning: ownerSnapshot.isPlanning,
        candidateResponse: candidateResponse,
        ownerToolResults: executedToolResults,
        ownerExecutedCommands: _turnToolResults.commands(ownerSnapshot.owner),
        attemptedSignatures: attemptedSignatures,
        maximumAttempts: ChatNotifier._maxNarratedTranscriptRepairAttempts,
        feedbackId:
            'narrated_transcript_check_'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (disposition.noPlanReason ==
        NarratedTranscriptRepairNoPlanReason.attemptLimitReached) {
      appLog(
        '[NarratedTranscript] Repair attempt limit reached; leaving the '
        'transcript claim to the finalization notice',
      );
    } else if (disposition.noPlanReason ==
        NarratedTranscriptRepairNoPlanReason.repeatedSignature) {
      appLog(
        '[NarratedTranscript] Skipping repeated repair for the same '
        'unexecuted transcript commands',
      );
    }
    final plan = disposition.plan;
    if (plan == null) return null;
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != plan.owner) {
      return null;
    }
    if (!attemptedSignatures.add(plan.signature)) {
      appLog(
        '[NarratedTranscript] Skipping repair because the owner signature '
        'was recorded after planning',
      );
      return null;
    }
    return _requestFinalAnswerRecoveryCompletion(
      owner: plan.owner,
      feedback: plan.feedback,
      transformId: 'narrated_transcript_repair',
      logLabel: 'narrated transcript feedback',
      logMessage:
          '[NarratedTranscript] Completion claim narrates '
          '${plan.assessment.unexecutedCommands.length} unexecuted command(s); '
          'requesting repair',
      candidateResponse: candidateResponse,
      executedToolResults: executedToolResults,
      batchToolResults: batchToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
      onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
    );
  }

  /// Applies the narrated-transcript repair to a streamed final answer.
  /// Returns true when the caller must stop: the repair re-entered the tool
  /// loop with follow-up calls, or the generation was cancelled mid-repair.
  Future<bool> _applyNarratedTranscriptRepairToStreamedFinalAnswer({
    required String streamedFinalAnswer,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required Set<String> attemptedSignatures,
    required List<Map<String, dynamic>> tools,
    required bool toolSearchEnabled,
    required Set<String> activeToolNames,
    required List<Map<String, dynamic>>? stableToolDefinitions,
    required Map<String, int> verificationFailureCounts,
    required int interactionGeneration,
    required void Function() onBlockingFeedbackPrepared,
  }) async {
    return _applyFinalAnswerRecoveryResult(
      result: _requestNarratedTranscriptRepairForCompletionClaim(
        candidateResponse: streamedFinalAnswer,
        executedToolResults: executedToolResults,
        batchToolResults: batchToolResults,
        attemptedSignatures: attemptedSignatures,
        tools: tools,
        interactionGeneration: interactionGeneration,
        onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
      ),
      streamedFinalAnswer: streamedFinalAnswer,
      toolCallLogMessage:
          '[NarratedTranscript] Streamed final answer repair requested calls',
      tools: tools,
      toolSearchEnabled: toolSearchEnabled,
      activeToolNames: activeToolNames,
      stableToolDefinitions: stableToolDefinitions,
      verificationFailureCounts: verificationFailureCounts,
      transcriptRepairSignatures: attemptedSignatures,
      interactionGeneration: interactionGeneration,
    );
  }
}
