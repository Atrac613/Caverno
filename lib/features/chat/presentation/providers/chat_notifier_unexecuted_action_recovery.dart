// Same-library ChatNotifier extension for final-answer claim recovery.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierUnexecutedActionRecovery on ChatNotifier {
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
    final promptFeedback = await _toolResultArtifactStore.persistIfLarge(
      plan.feedback,
      conversationId: plan.owner.conversationId,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        _turnOwnerForGeneration(interactionGeneration) != plan.owner) {
      return null;
    }
    batchToolResults.add(promptFeedback);
    executedToolResults.add(promptFeedback);
    onBlockingFeedbackPrepared?.call();
    _turnEnd.addTransform(plan.owner, 'narrated_transcript_repair');

    appLog(
      '[NarratedTranscript] Completion claim narrates '
      '${plan.assessment.unexecutedCommands.length} unexecuted command(s); '
      'requesting repair',
    );
    _appendToLastMessageForGeneration(interactionGeneration, '<think>');
    try {
      return await _createToolResultCompletionWithContextRetry(
        logLabel: 'narrated transcript feedback',
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
          _turnOwnerForGeneration(interactionGeneration) == plan.owner) {
        _removeTrailingThinkTagForGeneration(interactionGeneration);
      }
    }
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
    final repairResult =
        await _requestNarratedTranscriptRepairForCompletionClaim(
          candidateResponse: streamedFinalAnswer,
          executedToolResults: executedToolResults,
          batchToolResults: batchToolResults,
          attemptedSignatures: attemptedSignatures,
          tools: tools,
          interactionGeneration: interactionGeneration,
          onBlockingFeedbackPrepared: onBlockingFeedbackPrepared,
        );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return true;
    if (!ref.mounted) return true;
    if (repairResult == null) {
      return false;
    }
    if (repairResult.hasToolCalls) {
      appLog(
        '[NarratedTranscript] Streamed final answer repair requested '
        'tool calls',
      );
      await _executeToolCalls(
        repairResult.toolCalls!,
        assistantContent: repairResult.content.isNotEmpty
            ? repairResult.content
            : streamedFinalAnswer,
        toolSearchEnabled: toolSearchEnabled,
        selectedToolNames: activeToolNames,
        stableToolDefinitions: stableToolDefinitions,
        completionVerificationFailureCounts: verificationFailureCounts,
        narratedTranscriptRepairSignatures: attemptedSignatures,
        interactionGeneration: interactionGeneration,
      );
      return true;
    }
    final transcriptResponse = repairResult.content.trim();
    if (transcriptResponse.isNotEmpty) {
      _appendRecoveredAssistantResponse(
        transcriptResponse,
        interactionGeneration: interactionGeneration,
      );
    }
    return false;
  }
}
