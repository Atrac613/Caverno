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
    return CodingContinuationRecoveryRequest.run(
      candidateResponse: candidateResponse,
      recoveryCode: recoveryCode,
      forcedPrompt: forcedRecoveryPrompt,
      generation: interactionGeneration,
      tools: tools,
      executedResults: executedToolResults,
      buildBaseMessages: (forceCompaction) => _prepareMessagesForLLM(
        forceCompaction: forceCompaction,
        toolDefinitionsOverride: tools,
        interactionGeneration: interactionGeneration,
      ),
      carryResults: (feedback) =>
          _readResultCarryFor(interactionGeneration).resolve(
            batchToolResults: [feedback],
            executedToolResults: executedToolResults,
          ),
      create: _createToolResultCompletionWithContextRetry,
      isCurrent: () => _isCurrentInteractionGeneration(interactionGeneration),
    );
  }

  String? _codingContinuationRecoveryCode({
    required String candidateResponse,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    required bool requireContinuationRequest,
  }) {
    final visible = ContentParser.stripModelHistoryArtifacts(candidateResponse);
    final owner = _turnOwnerForGeneration(interactionGeneration);
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
            _shouldAcceptTerminalToolRoleBlockerResponse(visible),
        bracketedToolRequestName: const UnexecutedFinalAnswerToolRequestPolicy()
            .bracketedToolRequestName(visible),
        isProjectTaskTurn: _primaryRoutes.isProjectTaskTurn(
          interactionGeneration,
        ),
        reasoningOnlyRecoveryUsed:
            owner == null ||
            _turnEnd
                .transforms(owner)
                .contains('coding_continuation_recovery_reasoning_only_stop'),
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
