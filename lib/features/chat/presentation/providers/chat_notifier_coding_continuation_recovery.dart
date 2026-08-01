// Same-library ChatNotifier extension for coding continuation recovery.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierCodingContinuationRecovery on ChatNotifier {
  Future<ChatCompletionResult?> _requestCodingContinuationRecovery({
    required String candidateResponse,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    required bool requireContinuationRequest,
    List<ToolResultInfo> executedToolResults = const [],
    String? forcedRecoveryCode,
    String? forcedRecoveryPrompt,
  }) async {
    final recoveryCode =
        forcedRecoveryCode ??
        _codingContinuationRecoveryCode(
          candidateResponse: candidateResponse,
          tools: tools,
          interactionGeneration: interactionGeneration,
          requireContinuationRequest: requireContinuationRequest,
        );
    if (recoveryCode == null) {
      return null;
    }
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return null;
    }

    _turnEnd.addTransform(owner, 'coding_continuation_recovery_$recoveryCode');
    appLog('[Tool] Requesting coding continuation recovery: $recoveryCode');
    final recoveryToolResult = const CodingContinuationRecoveryPolicy()
        .buildCodingContinuationRecoveryToolResult(
          id: '${recoveryCode}_${DateTime.now().microsecondsSinceEpoch}',
          candidateResponse: candidateResponse,
          recoveryCode: recoveryCode,
        );
    List<Message> buildRecoveryMessages(bool forceCompaction) {
      final messages = _prepareMessagesForLLM(
        forceCompaction: forceCompaction,
        toolDefinitionsOverride: tools,
        interactionGeneration: interactionGeneration,
      );
      messages.add(
        Message(
          id: '${recoveryCode}_recovery_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.user,
          content:
              forcedRecoveryPrompt ??
              const CodingContinuationRecoveryPolicy()
                  .buildCodingContinuationRecoveryPrompt(
                    candidateResponse,
                    recoveryCode: recoveryCode,
                    executedToolResults: executedToolResults,
                  ),
          timestamp: DateTime.now(),
        ),
      );
      return messages;
    }

    return _createToolResultCompletionWithContextRetry(
      logLabel: const CodingContinuationRecoveryPolicy().recoveryLogLabel(
        recoveryCode,
      ),
      interactionGeneration: interactionGeneration,
      buildMessages: buildRecoveryMessages,
      toolResults: [recoveryToolResult],
      assistantContent: candidateResponse.isNotEmpty ? candidateResponse : null,
      tools: tools,
    );
  }

  String? _codingContinuationRecoveryCode({
    required String candidateResponse,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    required bool requireContinuationRequest,
  }) {
    final ownerSnapshot = _turnOwnerSnapshotForGeneration(
      interactionGeneration,
    );
    return const CodingContinuationRecoveryPolicy().recoveryCode(
      CodingContinuationRecoveryInput(
        candidateResponse: candidateResponse,
        toolDefinitions: tools,
        owningTurnLatestUserText: _latestUserContentForGeneration(
          interactionGeneration,
        ),
        requireContinuationRequest: requireContinuationRequest,
        isCodingWorkspaceOrMode:
            ownerSnapshot?.isCodingWorkspaceOrMode ?? false,
        hasPendingAutoContinueWorkflow:
            ownerSnapshot?.hasPendingAutoContinueExecutionWorkflow ?? false,
        saveSkillCompletedInGeneration:
            _lastSaveSkillGeneration == interactionGeneration,
        acceptsTerminalToolRoleBlockerResponse:
            _shouldAcceptTerminalToolRoleBlockerResponse(candidateResponse),
        bracketedToolRequestName: const UnexecutedFinalAnswerToolRequestPolicy()
            .bracketedToolRequestName(candidateResponse),
      ),
    );
  }

  bool _isCodingWorkspaceOrMode(int interactionGeneration) =>
      _turnOwnerSnapshotForGeneration(
        interactionGeneration,
      )?.isCodingWorkspaceOrMode ??
      false;

  bool _hasCodingContinuationRecoveryTools(
    List<Map<String, dynamic>> toolDefinitions,
  ) => const CodingContinuationRecoveryPolicy()
      .hasCodingContinuationRecoveryTools(toolDefinitions);

  @visibleForTesting
  bool looksLikeContinuationOnlyUserRequestForTest(String text) =>
      const CodingContinuationRecoveryPolicy()
          .looksLikeContinuationOnlyUserRequest(text);

  @visibleForTesting
  bool looksLikeProseOnlyCodingContinuationForTest(String text) =>
      const CodingContinuationRecoveryPolicy()
          .looksLikeProseOnlyCodingContinuation(text);
}
