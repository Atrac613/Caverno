// Same-library extension on [ChatNotifier]: delegates unexecuted-action and
// final-answer claim detection to the domain detector while keeping stateful
// application in the notifier.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierUnexecutedActionRecovery on ChatNotifier {
  void _appendUnexecutedToolRequestNoticeForContentIfNeeded({
    required int interactionGeneration,
    required String content,
    List<ToolResultInfo> toolResults = const [],
  }) {
    _recordUnexecutedFinalAnswerToolRequests(
      content: content,
      toolResults: toolResults,
    );
    const notice =
        'I could not execute the additional tool request above in this final-answer step. '
        'Treat it as unexecuted; ask me to continue with a narrower follow-up '
        'if the missing action still matters.';
    if (content.contains(notice) ||
        !_looksLikeUnexecutedToolRequest(content) ||
        _shouldSkipUnexecutedToolRequestNoticeForToolResults(
          content: content,
          toolResults: toolResults,
        )) {
      return;
    }
    final currentContent = _lastMessageContentForGeneration(
      interactionGeneration,
    );
    if (currentContent == null || currentContent.contains(notice)) {
      return;
    }
    _replaceLastMessageContentForGeneration(
      interactionGeneration,
      '${currentContent.trimRight()}\n\n$notice',
    );
  }

  void _recordUnexecutedFinalAnswerToolRequests({
    required String content,
    required List<ToolResultInfo> toolResults,
  }) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);
    if (toolCalls.isEmpty) {
      return;
    }

    var recordedAny = false;
    for (final toolCall in toolCalls) {
      final signature = jsonEncode({
        'name': toolCall.name,
        'arguments': toolCall.arguments,
      });
      final alreadyRecorded = toolResults.any((result) {
        final decoded = _tryDecodeMap(result.result);
        return decoded?['reason'] == 'final_answer_tool_request' &&
            decoded?['signature'] == signature;
      });
      if (alreadyRecorded) {
        continue;
      }
      toolResults.add(
        ToolResultInfo(
          id: 'unexecuted_final_answer_${toolCall.occurrenceId ?? toolCall.name}',
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: jsonEncode({
            'ok': false,
            'code': 'tool_call_not_executed',
            'reason': 'final_answer_tool_request',
            'tool_name': toolCall.name,
            'signature': signature,
            'error':
                'The final-answer response requested a tool, but final-answer streaming does not execute tools directly.',
            'required_action':
                'Retry this tool through the normal tool-aware continuation.',
          }),
        ),
      );
      recordedAny = true;
    }
    if (!recordedAny) {
      return;
    }
    _turnExitReasonHint = ToolLoopExitReason.unexecutedToolRequest;
    _appliedTurnTransforms.add('unexecuted_tool_request_notice');
  }

  String _messageContentWithVerificationClaimNotice(String content) {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation?.workspaceMode != WorkspaceMode.coding) {
      return content;
    }
    final assessment = _codingVerificationClaimGuard.assess(
      candidateResponse: content,
      toolResults: [
        ..._latestCompletedToolResults,
        ..._latestContentToolResults,
      ],
    );
    if (!assessment.hasMismatch) {
      return content;
    }
    final notice = assessment.buildNotice();
    if (content.contains(notice)) {
      return content;
    }
    _appliedTurnTransforms.add('verification_claim_notice');
    return '${content.trimRight()}\n\n$notice';
  }

  String _messageContentWithNarratedTranscriptClaimNotice(String content) {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation?.workspaceMode != WorkspaceMode.coding) {
      return content;
    }
    final assessment = _narratedTranscriptClaimGuard.assess(
      candidateResponse: content,
      toolResults: [
        ..._latestCompletedToolResults,
        ..._latestContentToolResults,
      ],
      additionalExecutedCommands: _turnCommandLedger,
    );
    if (!assessment.hasUnexecutedCommands) {
      return content;
    }
    final notice = assessment.buildNotice();
    if (content.contains(notice)) {
      return content;
    }
    _appliedTurnTransforms.add('narrated_transcript_claim_notice');
    return '${content.trimRight()}\n\n$notice';
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
    if (!_codingVerificationEnabledFor(
      CodingVerificationTrigger.completionClaim,
    )) {
      return null;
    }
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation?.workspaceMode != WorkspaceMode.coding ||
        (conversation?.isPlanningSession ?? false)) {
      return null;
    }
    final assessment = _narratedTranscriptClaimGuard.assess(
      candidateResponse: candidateResponse,
      toolResults: executedToolResults,
      additionalExecutedCommands: _turnCommandLedger,
    );
    if (!assessment.hasUnexecutedCommands) {
      return null;
    }
    if (attemptedSignatures.length >=
        ChatNotifier._maxNarratedTranscriptRepairAttempts) {
      appLog(
        '[NarratedTranscript] Repair attempt limit reached; leaving the '
        'transcript claim to the finalization notice',
      );
      return null;
    }
    final signature = jsonEncode(assessment.unexecutedCommands);
    if (!attemptedSignatures.add(signature)) {
      appLog(
        '[NarratedTranscript] Skipping repeated repair for the same '
        'unexecuted transcript commands',
      );
      return null;
    }

    final feedback = ToolResultInfo(
      id: 'narrated_transcript_check_${DateTime.now().microsecondsSinceEpoch}',
      name: 'narrated_transcript_check',
      arguments: {
        'trigger': 'narratedTranscript',
        'unexecuted_commands': assessment.unexecutedCommands,
      },
      result: jsonEncode({
        'schema': 'caverno_narrated_transcript_check',
        'ok': false,
        'code': 'narrated_transcript_commands_not_executed',
        'unexecuted_commands': assessment.unexecutedCommands,
        'error':
            'The answer presents a terminal transcript, but these commands '
            'have no execution record in this turn, so the output shown for '
            'them is not a real observation.',
        'required_action':
            'Execute the narrated commands now with local_execute_command '
            'and base the answer on their real output, or rewrite the answer '
            'to state plainly that these checks were not run.',
      }),
    );
    final promptFeedback = await _toolResultArtifactStore.persistIfLarge(
      feedback,
      conversationId:
          _activeResponseConversationIdForGeneration(interactionGeneration) ??
          conversationId,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    batchToolResults.add(promptFeedback);
    executedToolResults.add(promptFeedback);
    onBlockingFeedbackPrepared?.call();
    _appliedTurnTransforms.add('narrated_transcript_repair');

    appLog(
      '[NarratedTranscript] Completion claim narrates '
      '${assessment.unexecutedCommands.length} unexecuted command(s); '
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
      if (_isCurrentInteractionGeneration(interactionGeneration)) {
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

  String _messageContentWithUnwrittenFileClaimNotice(String content) {
    final conversationsState = ref.read(conversationsNotifierProvider);
    final conversation = conversationsState.currentConversation;
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding) {
      return content;
    }
    final projectRoot = _getEffectiveCodingProject()?.rootPath.trim();
    if (projectRoot == null || projectRoot.isEmpty) {
      return content;
    }
    final assessment = _unwrittenFileClaimGuard.assess(
      candidateResponse: content,
      toolResults: [
        ..._latestCompletedToolResults,
        ..._latestContentToolResults,
      ],
      projectRoot: projectRoot,
    );
    if (!assessment.hasClaims) {
      return content;
    }
    final notice = assessment.buildNotice();
    if (content.contains(notice)) {
      return content;
    }
    _appliedTurnTransforms.add('unwritten_file_claim_notice');
    return '${content.trimRight()}\n\n$notice';
  }

  ToolResultInfo? _buildUnexecutedSkippedBrowserActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required int interactionGeneration,
  }) {
    return _finalAnswerClaimDetector
        .buildUnexecutedSkippedBrowserActionToolResult(
          candidateResponse: candidateResponse,
          batchToolResults: batchToolResults,
          latestUserContent: _latestUserContentForGeneration(
            interactionGeneration,
          ),
        );
  }

  ToolResultInfo? _buildUnexecutedFileSideEffectToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    return _finalAnswerClaimDetector.buildUnexecutedFileSideEffectToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
      latestUserContent: _latestUserContentForGeneration(interactionGeneration),
    );
  }

  ToolResultInfo? _buildUnexecutedCommandActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    return _finalAnswerClaimDetector.buildUnexecutedCommandActionToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  ToolResultInfo? _buildUnverifiedReadOnlyInspectionClaimToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return _finalAnswerClaimDetector
        .buildUnverifiedReadOnlyInspectionClaimToolResult(
          candidateResponse: candidateResponse,
          toolResults: toolResults,
        );
  }

  @visibleForTesting
  ToolResultInfo? buildUnverifiedReadOnlyInspectionClaimToolResultForTest({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return _buildUnverifiedReadOnlyInspectionClaimToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  @visibleForTesting
  bool looksLikeCompletedReadOnlyInspectionClaimForTest(String content) {
    return _looksLikeCompletedReadOnlyInspectionClaim(content);
  }

  @visibleForTesting
  bool hasSuccessfulReadOnlyInspectionResultForTest(
    List<ToolResultInfo> toolResults,
  ) {
    return _hasSuccessfulReadOnlyInspectionResult(toolResults);
  }

  bool _hasSuccessfulFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasSuccessfulFileSideEffectResult(
      toolResults,
    );
  }

  bool _hasSuccessfulReadOnlyInspectionResult(
    List<ToolResultInfo> toolResults,
  ) {
    return _finalAnswerClaimDetector.hasSuccessfulReadOnlyInspectionResult(
      toolResults,
    );
  }

  String _clipForDiagnostic(String value, {int maxLength = 240}) {
    return _finalAnswerClaimDetector.clipForDiagnostic(
      value,
      maxLength: maxLength,
    );
  }

  bool _looksLikeCompletedReadOnlyInspectionClaim(String content) {
    return _finalAnswerClaimDetector.looksLikeCompletedReadOnlyInspectionClaim(
      content,
    );
  }

  Set<String> _browserToolNamesFromDefinitions(
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    return _finalAnswerClaimDetector.browserToolNamesFromDefinitions(
      toolDefinitions,
    );
  }

  bool _looksLikeBrowserActionRequest(String text) {
    return _finalAnswerClaimDetector.looksLikeBrowserActionRequest(text);
  }

  String _browserActionToolNameForText(String text) {
    return _finalAnswerClaimDetector.browserActionToolNameForText(text);
  }

  String _messageContentWithUnexecutedCommandActionNotice(
    String content,
    String notice,
  ) {
    return _finalAnswerClaimDetector
        .messageContentWithUnexecutedCommandActionNotice(
          content,
          notice: notice,
        );
  }

  String _messageContentWithPrependedClaimCorrectionNotice(
    String content,
    String notice,
  ) {
    return _finalAnswerClaimDetector
        .messageContentWithPrependedClaimCorrectionNotice(content, notice);
  }

  String _messageContentWithUnverifiedReadOnlyInspectionNotice(
    String content,
    String notice,
  ) {
    return _finalAnswerClaimDetector
        .messageContentWithUnverifiedReadOnlyInspectionNotice(
          content,
          notice: notice,
        );
  }

  bool _looksLikeUnsupportedFileSideEffectClaim(
    String content, {
    required List<ToolResultInfo> toolResults,
  }) {
    return _finalAnswerClaimDetector.looksLikeUnsupportedFileSideEffectClaim(
      content,
      toolResults: toolResults,
    );
  }

  bool _hasUnexecutedFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasUnexecutedFileSideEffectResult(
      toolResults,
    );
  }

  bool _hasUnexecutedCommandActionResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasUnexecutedCommandActionResult(
      toolResults,
    );
  }

  bool _hasUnverifiedReadOnlyInspectionClaimResult(
    List<ToolResultInfo> toolResults,
  ) {
    return _finalAnswerClaimDetector.hasUnverifiedReadOnlyInspectionClaimResult(
      toolResults,
    );
  }

  bool _hasSuccessfulCommandExecutionResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasSuccessfulCommandExecutionResult(
      toolResults,
    );
  }

  bool _looksLikeCommandSuccessClaim(String content) {
    return _finalAnswerClaimDetector.looksLikeCommandSuccessClaim(content);
  }

  bool _looksLikeUnsupportedCommandExecutionAction(String content) {
    return _finalAnswerClaimDetector.looksLikeUnsupportedCommandExecutionAction(
      content,
    );
  }

  bool _looksLikeFutureCommandExecutionAction(String content) {
    return _finalAnswerClaimDetector.looksLikeFutureCommandExecutionAction(
      content,
    );
  }

  bool _looksLikeCompletedCommandExecutionClaim(String content) {
    return _finalAnswerClaimDetector.looksLikeCompletedCommandExecutionClaim(
      content,
    );
  }

  bool _looksLikeFutureFileSideEffectAction(String content) {
    return _finalAnswerClaimDetector.looksLikeFutureFileSideEffectAction(
      content,
    );
  }

  bool _containsCjkFutureActionMarker(String value, {int startIndex = 0}) {
    return _finalAnswerClaimDetector.containsCjkFutureActionMarker(
      value,
      startIndex: startIndex,
    );
  }
}
