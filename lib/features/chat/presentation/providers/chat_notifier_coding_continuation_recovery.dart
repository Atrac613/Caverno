// Same-library extension on [ChatNotifier]: coding-mode continuation recovery —
// detecting prose-only / bracketed-tool continuations and building the recovery
// re-prompt. Pure relocation from chat_notifier.dart (F5), no behavior change.
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

    appLog('[Tool] Requesting coding continuation recovery: $recoveryCode');
    final recoveryToolResult = _buildCodingContinuationRecoveryToolResult(
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
              _buildCodingContinuationRecoveryPrompt(
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
      logLabel: _codingContinuationRecoveryLogLabel(recoveryCode),
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
    final candidate = candidateResponse.trim();
    if (candidate.isEmpty) {
      return null;
    }
    if (!_isCodingWorkspaceOrMode()) {
      return null;
    }
    if (!_hasCodingContinuationRecoveryTools(tools)) {
      return null;
    }
    // A save_skill call already completed the task this turn, so the model's
    // "skill created" summary is a legitimate terminal response, not an
    // unexecuted coding continuation. Skip recovery to avoid forcing a
    // redundant second save (and a second non-cacheable approval).
    if (_lastSaveSkillGeneration == interactionGeneration) {
      return null;
    }
    final hasStructuredExecutionDeferral =
        const StructuredCodingExecutionDeferralDetector().matches(candidate);
    final hasPendingStructuredExecutionDeferral =
        hasStructuredExecutionDeferral &&
        _hasPendingAutoContinueExecutionWorkflow();
    if (hasStructuredExecutionDeferral &&
        !hasPendingStructuredExecutionDeferral) {
      return null;
    }
    if (requireContinuationRequest &&
        !_looksLikeContinuationOnlyUserRequest(
          _latestUserContentForGeneration(interactionGeneration),
        ) &&
        !hasPendingStructuredExecutionDeferral) {
      return null;
    }
    if (_shouldAcceptTerminalToolRoleBlockerResponse(candidate)) {
      return null;
    }
    final bracketedToolName = _bracketedToolRequestName(candidate);
    if (bracketedToolName != null &&
        _isCodingContinuationRecoveryToolName(bracketedToolName)) {
      return 'bracketed_coding_tool_request';
    }
    if (_looksLikeProseOnlyCodingContinuation(candidate) ||
        hasPendingStructuredExecutionDeferral) {
      return 'prose_only_coding_continuation';
    }
    return null;
  }

  bool _hasPendingAutoContinueExecutionWorkflow() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final goal = conversation?.goal;
    if (conversation == null ||
        goal == null ||
        !goal.isActive ||
        !goal.autoContinue ||
        conversation.workflowStage != ConversationWorkflowStage.implement) {
      return false;
    }
    final snapshot = const ExecutionSnapshotProjector().project(conversation);
    return snapshot.action == ExecutionSnapshotAction.execute &&
        snapshot.remainingTaskCount > 0 &&
        snapshot.unresolvedQuestionCount == 0;
  }

  bool _isCodingWorkspaceOrMode() {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    return currentConversation?.workspaceMode == WorkspaceMode.coding ||
        _assistantModeOverride == AssistantMode.coding ||
        _settings.assistantMode == AssistantMode.coding;
  }

  bool _hasCodingContinuationRecoveryTools(
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    final toolNames = ToolDefinitionSearchService.toolNamesFromDefinitions(
      toolDefinitions,
    ).map((toolName) => toolName.trim().toLowerCase()).toSet();
    return toolNames.any(_isCodingContinuationRecoveryToolName);
  }

  bool _isCodingContinuationRecoveryToolName(String toolName) {
    return const {
      'read_file',
      'list_directory',
      'search_files',
      'resolve_installed_dependency',
      'write_file',
      'edit_file',
      'delete_file',
      'local_execute_command',
      'git_execute_command',
      'run_tests',
      'run_python_script',
    }.contains(toolName.trim().toLowerCase());
  }

  bool _looksLikeContinuationOnlyUserRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final cleaned = normalized
        .replaceAll(RegExp(r'^[\s.!?]+'), '')
        .replaceAll(RegExp(r'[\s.!?]+$'), '');
    if (const {
      'continue',
      'go on',
      'keep going',
      'proceed',
      'resume',
      'next',
      'next step',
    }.contains(cleaned)) {
      return true;
    }
    if (cleaned.startsWith('automatic goal continuation ')) {
      return true;
    }
    return _containsAnyCodeUnitSequence(text, const [
      [0x7d9a, 0x3051, 0x3066],
      [0x7d9a, 0x304d],
      [0x9032, 0x3081, 0x3066],
    ]);
  }

  @visibleForTesting
  bool looksLikeContinuationOnlyUserRequestForTest(String text) {
    return _looksLikeContinuationOnlyUserRequest(text);
  }

  bool _looksLikeProseOnlyCodingContinuation(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final hasFencedCode = trimmed.contains('```');
    if (trimmed.length > 1600 && (!hasFencedCode || trimmed.length > 12000)) {
      return false;
    }
    final normalized = trimmed.toLowerCase();
    if (_containsAny(normalized, const [
      'cannot',
      'can not',
      "can't",
      'unable',
      'blocked',
      'need your',
      'please provide',
      'not enough information',
    ])) {
      return false;
    }

    final hasEnglishTarget = _containsAny(normalized, const [
      'code',
      'source',
      'file',
      'project',
      'dart',
      'python',
      'script',
      'logic',
      'entrypoint',
      'implementation',
      'pubspec',
      'error',
      'diagnostic',
      'analyzer',
      'test failure',
    ]);
    final hasEnglishAction = _containsAny(normalized, const [
      'i will inspect',
      'i will check',
      'i will read',
      'i will port',
      'i will implement',
      'i will update',
      'i will edit',
      'i will modify',
      'i will write',
      'i will create',
      'i will fix',
      'i will resolve',
      "i'll inspect",
      "i'll check",
      "i'll read",
      "i'll port",
      "i'll implement",
      "i'll update",
      "i'll edit",
      "i'll modify",
      "i'll write",
      "i'll create",
      "i'll fix",
      "i'll resolve",
      'i am going to inspect',
      'i am going to check',
      'i am going to read',
      'i am going to port',
      'i am going to implement',
      'i am going to update',
      'i am going to edit',
      'i am going to modify',
      'i am going to write',
      'i am going to create',
      'i am going to fix',
      'i am going to resolve',
      'next i will',
      'now i will',
    ]);
    final hasCjkTarget = _containsAnyCodeUnitSequence(text, const [
      [0x30b3, 0x30fc, 0x30c9],
      [0x30bd, 0x30fc, 0x30b9],
      [0x30d5, 0x30a1, 0x30a4, 0x30eb],
      [0x30d7, 0x30ed, 0x30b8, 0x30a7, 0x30af, 0x30c8],
      [0x30b9, 0x30af, 0x30ea, 0x30d7, 0x30c8],
      [0x30ed, 0x30b8, 0x30c3, 0x30af],
      [0x65e2, 0x5b58],
      [0x30a8, 0x30e9, 0x30fc],
      [0x8a3a, 0x65ad],
    ]);
    final hasCjkAction = _containsAnyCodeUnitSequence(text, const [
      [0x78ba, 0x8a8d, 0x3057],
      [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
      [0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059],
      [0x8aad, 0x307f, 0x307e, 0x3059],
      [0x30dd, 0x30fc, 0x30c6, 0x30a3, 0x30f3, 0x30b0, 0x3057, 0x307e, 0x3059],
      [0x79fb, 0x690d, 0x3057, 0x307e, 0x3059],
      [0x5b9f, 0x88c5, 0x3057, 0x307e, 0x3059],
      [0x66f4, 0x65b0, 0x3057, 0x307e, 0x3059],
      [0x7de8, 0x96c6, 0x3057, 0x307e, 0x3059],
      [0x4f5c, 0x6210, 0x3057, 0x307e, 0x3059],
      [0x66f8, 0x304d, 0x307e, 0x3059],
      [0x4fee, 0x6b63, 0x3057, 0x307e, 0x3059],
    ]);
    return (hasEnglishTarget || hasCjkTarget) &&
        (hasEnglishAction || hasCjkAction);
  }

  @visibleForTesting
  bool looksLikeProseOnlyCodingContinuationForTest(String text) {
    return _looksLikeProseOnlyCodingContinuation(text);
  }

  ToolResultInfo _buildCodingContinuationRecoveryToolResult({
    required String candidateResponse,
    required String recoveryCode,
  }) {
    return ToolResultInfo(
      id: '${recoveryCode}_${DateTime.now().microsecondsSinceEpoch}',
      name: 'coding_continuation_recovery',
      arguments: {'reason': _codingContinuationRecoveryReason(recoveryCode)},
      result: jsonEncode({
        'ok': false,
        'code': recoveryCode,
        'error': _codingContinuationRecoveryError(recoveryCode),
        'claimedResponse': _clipForDiagnostic(candidateResponse),
        'requiredAction': _codingContinuationRecoveryRequiredAction(
          recoveryCode,
        ),
      }),
    );
  }

  String _buildCodingContinuationRecoveryPrompt(
    String candidateResponse, {
    required String recoveryCode,
    List<ToolResultInfo> executedToolResults = const [],
  }) {
    // When this turn already executed commands that did not cleanly succeed
    // (a timeout or a non-zero exit), a blanket "treat that response as
    // unexecuted" re-prompt makes the model restart the whole task and re-run
    // steps that already completed. Branch to a non-destructive prompt that
    // preserves prior progress and points the model at the specific failure.
    final partialProgressNotice =
        _codingContinuationRecoveryPartialProgressNotice(executedToolResults);
    if (partialProgressNotice != null) {
      return [
        _codingContinuationRecoveryPromptLead(recoveryCode),
        partialProgressNotice,
        'Do not restart the task or re-run commands that already completed successfully.',
        'Use the available tools now to investigate and resolve only the unresolved failure above, then report the final status.',
        'Do not restate the plan and do not answer with future-tense prose.',
        'Previous response: ${_clipForDiagnostic(candidateResponse)}',
      ].join('\n');
    }
    return [
      _codingContinuationRecoveryPromptLead(recoveryCode),
      'Treat that response as unexecuted.',
      'Use the available tools now to perform the next concrete coding step.',
      'Prefer read_file, list_directory, or search_files before editing when the target file has not been inspected.',
      'Do not restate the plan and do not answer with future-tense prose.',
      'Previous response: ${_clipForDiagnostic(candidateResponse)}',
    ].join('\n');
  }

  /// Builds a notice describing partial command progress for the recovery
  /// re-prompt, or returns null when the default "treat as unexecuted" framing
  /// is appropriate.
  ///
  /// Returns non-null only when this turn already executed a command tool that
  /// ended in a timeout or a non-zero exit. Pure read-only inspection turns
  /// (read_file / list_directory only) and turns where every command succeeded
  /// fall through to null, so the default prompt is preserved for the
  /// "planned but executed nothing" case.
  String? _codingContinuationRecoveryPartialProgressNotice(
    List<ToolResultInfo> executedToolResults,
  ) {
    if (executedToolResults.isEmpty) {
      return null;
    }
    final hasTimeout = _hasTimedOutCommandResult(executedToolResults);
    final hasFailedExit = _toolResultsContainFailedCommandValidation(
      executedToolResults,
    );
    if (!hasTimeout && !hasFailedExit) {
      return null;
    }
    final problems = <String>[
      if (hasTimeout) 'a command timed out before completing',
      if (hasFailedExit) 'a command exited with a non-zero status',
    ];
    final progressClause =
        _hasSuccessfulCommandExecutionResult(executedToolResults)
        ? 'Some commands in this turn already completed successfully, but '
        : 'In this turn, ';
    return '$progressClause${problems.join(' and ')}.';
  }

  String _codingContinuationRecoveryLogLabel(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'length-truncated pending action recovery';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'bracketed coding tool request recovery';
    }
    return 'prose-only coding continuation recovery';
  }

  String _codingContinuationRecoveryReason(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'The assistant reached the output-token limit while trusted tool evidence still showed incomplete executable coding work.';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'The assistant returned a bracketed coding tool request in final-answer text instead of issuing an executable tool call.';
    }
    return 'The assistant returned coding continuation prose instead of using an available coding tool.';
  }

  String _codingContinuationRecoveryError(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'The assistant reached the output-token limit before issuing the next executable coding action.';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'The assistant response contained a bracketed coding tool request, but no executable tool call was issued.';
    }
    return 'The assistant response described a future coding action, but no tool call was issued.';
  }

  String _codingContinuationRecoveryRequiredAction(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'Issue exactly one available tool call that advances the incomplete work.';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'Issue the requested coding tool call now. Do not describe bracketed tool blocks as already executed.';
    }
    return 'Use an available file, command, or test tool now. Do not restate the plan.';
  }

  String _codingContinuationRecoveryPromptLead(String recoveryCode) {
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'The previous assistant response contained a bracketed coding tool request in final-answer text, but no tool call was issued.';
    }
    return 'The previous assistant response was a coding continuation, but no tool call was issued.';
  }
}
