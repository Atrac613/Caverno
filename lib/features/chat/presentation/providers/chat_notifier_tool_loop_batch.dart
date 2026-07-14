// Same-library extension on [ChatNotifier]: tool-loop batch execution and
// prompt-result persistence are kept outside the main notifier body while the
// larger tool loop is decomposed.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

enum _ToolLoopBatchStatus { completed, textResponse, cancelled }

const _toolFailureClassifier = ToolFailureClassifier();

class _ToolLoopBatchExecutionResult {
  const _ToolLoopBatchExecutionResult({
    required this.status,
    required this.batchToolResults,
    required this.pendingBatchCalls,
    required this.commandRetryGeneration,
    this.terminalSuccessMessage,
  });

  factory _ToolLoopBatchExecutionResult.completed({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolCallInfo> pendingBatchCalls,
    required int commandRetryGeneration,
    String? terminalSuccessMessage,
  }) {
    return _ToolLoopBatchExecutionResult(
      status: _ToolLoopBatchStatus.completed,
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: commandRetryGeneration,
      terminalSuccessMessage: terminalSuccessMessage,
    );
  }

  factory _ToolLoopBatchExecutionResult.textResponse({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolCallInfo> pendingBatchCalls,
    required int commandRetryGeneration,
  }) {
    return _ToolLoopBatchExecutionResult(
      status: _ToolLoopBatchStatus.textResponse,
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: commandRetryGeneration,
    );
  }

  factory _ToolLoopBatchExecutionResult.cancelled({
    required int commandRetryGeneration,
  }) {
    return _ToolLoopBatchExecutionResult(
      status: _ToolLoopBatchStatus.cancelled,
      batchToolResults: const [],
      pendingBatchCalls: const [],
      commandRetryGeneration: commandRetryGeneration,
    );
  }

  final _ToolLoopBatchStatus status;
  final List<ToolResultInfo> batchToolResults;
  final List<ToolCallInfo> pendingBatchCalls;
  final int commandRetryGeneration;
  final String? terminalSuccessMessage;

  bool get didCancel => status == _ToolLoopBatchStatus.cancelled;

  bool get hasTextResponse => status == _ToolLoopBatchStatus.textResponse;
}

extension ChatNotifierToolLoopBatch on ChatNotifier {
  Future<_ToolLoopBatchExecutionResult> _executeToolLoopBatch({
    required List<ToolCallInfo> currentToolCalls,
    required String? currentAssistantContent,
    required List<ToolResultInfo> executedToolResults,
    required Set<String> executedToolCallKeys,
    required Map<String, int> toolFailureCounts,
    required int commandRetryGeneration,
    required int iteration,
    required int interactionGeneration,
  }) async {
    final batchToolResults = <ToolResultInfo>[];
    final pendingBatchCalls = <ToolCallInfo>[];
    var nextCommandRetryGeneration = commandRetryGeneration;
    final terminalSuccessState = ToolTerminalSuccessBatchState();

    for (final toolCall in currentToolCalls) {
      final toolCallKey = _toolExecutionKey(
        toolCall,
        commandRetryGeneration: nextCommandRetryGeneration,
      );
      final shouldBlockTimedOutCommandRetry =
          _buildTimedOutCommandRetryGuardResult(
            toolCall,
            executedToolResults: executedToolResults,
          ) !=
          null;
      if (executedToolCallKeys.contains(toolCallKey) &&
          !_shouldAllowRepeatedToolExecution(toolCall) &&
          !shouldBlockTimedOutCommandRetry) {
        appLog(
          '[Tool] Duplicate tool call detected, skipping: ${toolCall.name} ${toolCall.arguments}',
        );
        _logToolLifecycleEvent(
          toolCall: toolCall,
          lifecycleState: 'skipped',
          loopIndex: iteration,
          schedulerMode: ToolExecutionScheduler.executionModeFor(toolCall),
          resultStatus: 'skipped',
          skipReason: 'duplicate_tool_call',
        );
        await _recordToolLoopRepetitionRuntimeFeedback();
        continue;
      }

      appLog('[Tool] Executing tool: ${toolCall.name}');
      appLog('[Tool] Arguments: ${toolCall.arguments}');

      _appendToolUseToLastMessage(
        toolCall,
        interactionGeneration: interactionGeneration,
      );
      pendingBatchCalls.add(toolCall);
    }

    final diagnosticBaseline = await _captureCodingDiagnosticFeedbackBaseline(
      pendingBatchCalls,
      interactionGeneration: interactionGeneration,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return _ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
      );
    }

    final allowSuccessfulReadResultReplay = !pendingBatchCalls.any(
      _isContractMutationToolCall,
    );

    final scheduledResults = await ToolExecutionScheduler.executeBatch(
      toolCalls: pendingBatchCalls,
      execute: (toolCall) async {
        final materialAssumptionGuardResult =
            _buildMaterialContractAssumptionGuardResult(toolCall);
        if (materialAssumptionGuardResult != null) {
          return materialAssumptionGuardResult;
        }
        final truncatedArgumentsGuardResult =
            _buildTruncatedToolCallArgumentsGuardResult(toolCall);
        if (truncatedArgumentsGuardResult != null) {
          return truncatedArgumentsGuardResult;
        }
        final analysisOptionsLintEditGuardResult =
            _buildAnalysisOptionsLintEditGuardResult(
              toolCall,
              executedToolResults: executedToolResults,
            );
        if (analysisOptionsLintEditGuardResult != null) {
          return analysisOptionsLintEditGuardResult;
        }
        final guardResult = _buildGitTagFormatInspectionGuardResult(
          toolCall,
          executedToolResults: executedToolResults,
        );
        if (guardResult != null) {
          return guardResult;
        }
        final timeoutRetryGuardResult = _buildTimedOutCommandRetryGuardResult(
          toolCall,
          executedToolResults: executedToolResults,
        );
        if (timeoutRetryGuardResult != null) {
          return timeoutRetryGuardResult;
        }
        final productionReleaseGuardResult =
            _buildProductionReleaseApprovalGuardResult(
              toolCall,
              currentAssistantContent: currentAssistantContent,
              interactionGeneration: interactionGeneration,
            );
        if (productionReleaseGuardResult != null) {
          return productionReleaseGuardResult;
        }
        final codingCommandPreflightGuardResult =
            _buildCodingCommandPreflightGuardResult(toolCall);
        if (codingCommandPreflightGuardResult != null) {
          return codingCommandPreflightGuardResult;
        }
        final modifiedSavedValidationCommandGuardResult =
            _buildModifiedSavedValidationCommandGuardResult(toolCall);
        if (modifiedSavedValidationCommandGuardResult != null) {
          return modifiedSavedValidationCommandGuardResult;
        }
        final savedTaskTargetScopeGuardResult =
            _buildSavedTaskTargetScopeGuardResult(toolCall);
        if (savedTaskTargetScopeGuardResult != null) {
          return savedTaskTargetScopeGuardResult;
        }
        final verifierReplayGuardResult =
            _buildUnchangedVerifierReplayBeforeRepairGuardResult(
              toolCall,
              commandRetryGeneration: nextCommandRetryGeneration,
              pendingToolCalls: pendingBatchCalls,
            );
        if (verifierReplayGuardResult != null) {
          return verifierReplayGuardResult;
        }
        final unexecutedFileMutationGuardResult =
            _buildUnexecutedFileMutationBeforeCommandGuardResult(
              toolCall,
              currentAssistantContent: currentAssistantContent,
              pendingToolCalls: pendingBatchCalls,
              executedToolResults: executedToolResults,
            );
        if (unexecutedFileMutationGuardResult != null) {
          return unexecutedFileMutationGuardResult;
        }
        final mutationGeneration =
            ref
                .read(conversationsNotifierProvider)
                .currentConversation
                ?.mutationGeneration ??
            0;
        if (allowSuccessfulReadResultReplay) {
          final replayedResult = _successfulReadResultReplayCache.lookup(
            toolCall: toolCall,
            interactionGeneration: interactionGeneration,
            mutationGeneration: mutationGeneration,
            resolveProjectPath: _normalizeToolPathForDedup,
          );
          if (replayedResult != null) {
            appLog(
              '[InspectionReplay] Replayed successful read_file result for '
              'mutation generation $mutationGeneration',
            );
            return McpToolResult(
              toolName: toolCall.name,
              result: replayedResult,
              isSuccess: true,
            );
          }
        }
        final dispatchedAt = DateTime.now();
        final dispatchResult = await _dispatchToolCall(
          toolCall,
          interactionGeneration: interactionGeneration,
        );
        final effectiveResult =
            _buildStaleProcessStartGuardResult(
              toolCall,
              dispatchResult,
              dispatchedAt: dispatchedAt,
            ) ??
            dispatchResult;
        if (!_toolFailureClassifier.isApprovalDenial(effectiveResult)) {
          _recordExecutedVerifierReplayCandidate(toolCall);
        }
        if (allowSuccessfulReadResultReplay) {
          _successfulReadResultReplayCache.record(
            toolCall: toolCall,
            result: effectiveResult.result,
            isSuccess: effectiveResult.isSuccess,
            interactionGeneration: interactionGeneration,
            mutationGeneration: mutationGeneration,
            resolveProjectPath: _normalizeToolPathForDedup,
          );
        }
        return effectiveResult;
      },
      onLifecycle: (event) =>
          _logScheduledToolLifecycleEvent(event, loopIndex: iteration),
      onBatch: (telemetry) {
        appLog(ChatToolExecutionLogFormatter.schedulerBatchLine(telemetry));
      },
    );

    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return _ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
      );
    }

    for (final scheduledResult in scheduledResults) {
      final toolCall = scheduledResult.toolCall;
      final toolCallKey = _toolExecutionKey(
        toolCall,
        commandRetryGeneration: nextCommandRetryGeneration,
      );
      // Failure tracking ignores model narration (`reason`) so a retried denied
      // command counts as one repeating action. Success dedup keeps narration
      // for inspections but strips it for file mutations, preventing reworded
      // reasons from repeating a side effect.
      final toolFailureKey = _toolFailureKey(
        toolCall,
        commandRetryGeneration: nextCommandRetryGeneration,
      );
      if (scheduledResult.error != null) {
        final error = scheduledResult.error!;
        appLog('[Tool] Error: $error');
        _appendToLastMessageForGeneration(
          interactionGeneration,
          '[Search error: $error]\n',
        );
        return _ToolLoopBatchExecutionResult.textResponse(
          batchToolResults: batchToolResults,
          pendingBatchCalls: pendingBatchCalls,
          commandRetryGeneration: nextCommandRetryGeneration,
        );
      }

      final result = scheduledResult.result!;
      final toolResult = result.isSuccess
          ? result.result
          : (result.result.trim().isNotEmpty
                ? result.result
                : 'Error: ${result.errorMessage}');

      final promptToolResult = await _persistToolResultForPrompt(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: toolResult,
        ),
        interactionGeneration: interactionGeneration,
        recordConversationTaint: true,
        recordBackgroundProcessStart: true,
        recordModelEditApplyTelemetry: true,
      );
      if (promptToolResult == null) {
        return _ToolLoopBatchExecutionResult.cancelled(
          commandRetryGeneration: nextCommandRetryGeneration,
        );
      }
      batchToolResults.add(promptToolResult);
      executedToolResults.add(promptToolResult);

      final disposition = _toolFailureClassifier.classify(toolCall, result);
      if (_isUnchangedVerifierReplayBeforeRepairGuardResult(result)) {
        toolFailureCounts.remove(toolFailureKey);
      } else if (disposition == ToolResultDisposition.success) {
        if (_isCommandExecutionTool(toolCall.name)) {
          _resetCommandDiagnosticStreak(toolFailureKey);
        }
        final isMutationTool = _isContractMutationToolCall(toolCall);
        if (isMutationTool) {
          _clearCommandDiagnosticRepairFocus();
        }
        final hasExplicitTerminalSuccess = terminalSuccessState
            .observeSuccessfulResult(
              rawResult: result.result,
              isMutationTool: isMutationTool,
            );
        if (isMutationTool && !hasExplicitTerminalSuccess) {
          try {
            await ref
                .read(conversationsNotifierProvider.notifier)
                .recordCurrentMutationGeneration();
          } catch (error) {
            appLog(
              '[ExecutionEvidence] Failed to persist mutation generation: '
              '$error',
            );
          }
        }
        executedToolCallKeys.add(toolCallKey);
        toolFailureCounts.remove(toolFailureKey);
        if (_advancesCommandRetryGeneration(toolCall)) {
          nextCommandRetryGeneration += 1;
        }
      } else if (disposition ==
          ToolResultDisposition.actionableCommandFailure) {
        toolFailureCounts.remove(toolFailureKey);
        _recordCommandDiagnosticStreak(
          commandKey: toolFailureKey,
          toolResult: promptToolResult,
        );
        appLog(
          '[Tool] Command completed with an actionable non-zero outcome; '
          'returning diagnostics without counting an execution failure',
        );
      } else {
        await _recordMalformedToolCallRuntimeFeedback(
          '${result.errorMessage ?? ''}\n${result.result}',
        );
        final failureCount = (toolFailureCounts[toolFailureKey] ?? 0) + 1;
        toolFailureCounts[toolFailureKey] = failureCount;
        if (failureCount >= 2) {
          final isDenial = disposition == ToolResultDisposition.approvalDenied;
          appLog(
            '[Tool] Same tool (${toolCall.name}) '
            '${isDenial ? 'was denied' : 'failed'} '
            '$failureCount times consecutively, ending loop',
          );
          // A repeated approval denial is a policy decision, not a broken
          // endpoint: re-issuing the identical command will always be denied,
          // so guide toward approval / a different approach instead of telling
          // the user to check their server configuration.
          _appendToLastMessageForGeneration(
            interactionGeneration,
            isDenial
                ? '\nThe command (${toolCall.name}) was blocked by approval and '
                      'will keep being blocked if re-issued unchanged. Approve it '
                      'manually or take a different approach.\n'
                      'Reason: ${result.errorMessage}\n'
                : '\nFailed to execute tool (${toolCall.name}). Please check your server configuration.\nError: ${result.errorMessage}\n',
          );
          _turnExitReasonHint = ToolLoopExitReason.toolFailureAbort;
          return _ToolLoopBatchExecutionResult.textResponse(
            batchToolResults: batchToolResults,
            pendingBatchCalls: pendingBatchCalls,
            commandRetryGeneration: nextCommandRetryGeneration,
          );
        }
      }
    }

    final diagnosticFeedback = await _buildCodingDiagnosticFeedbackToolResult(
      batchToolResults,
      interactionGeneration: interactionGeneration,
      baseline: diagnosticBaseline,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return _ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
      );
    }
    if (diagnosticFeedback != null) {
      final promptDiagnosticFeedback = await _persistToolResultForPrompt(
        diagnosticFeedback,
        interactionGeneration: interactionGeneration,
      );
      if (promptDiagnosticFeedback == null) {
        return _ToolLoopBatchExecutionResult.cancelled(
          commandRetryGeneration: nextCommandRetryGeneration,
        );
      }
      batchToolResults.add(promptDiagnosticFeedback);
      executedToolResults.add(promptDiagnosticFeedback);
    }

    final commandOutputFeedback =
        await _buildCodingCommandOutputGuardrailToolResult(
          batchToolResults,
          interactionGeneration: interactionGeneration,
        );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return _ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
      );
    }
    if (commandOutputFeedback != null) {
      final promptCommandOutputFeedback = await _persistToolResultForPrompt(
        commandOutputFeedback,
        interactionGeneration: interactionGeneration,
      );
      if (promptCommandOutputFeedback == null) {
        return _ToolLoopBatchExecutionResult.cancelled(
          commandRetryGeneration: nextCommandRetryGeneration,
        );
      }
      batchToolResults.add(promptCommandOutputFeedback);
      executedToolResults.add(promptCommandOutputFeedback);
    }

    return _ToolLoopBatchExecutionResult.completed(
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: nextCommandRetryGeneration,
      terminalSuccessMessage: terminalSuccessState.message,
    );
  }

  /// Tool calls carried by a length-truncated completion whose arguments
  /// parsed empty — the truncation ate them mid-generation. Recorded so the
  /// batch executor can answer them with a truncation diagnostic.
  Set<String> _truncationCasualtyToolCallIds(ChatCompletionResult result) {
    if (!result.hasToolCalls || !_isCompletionTruncated(result.finishReason)) {
      return const <String>{};
    }
    return result.toolCalls!
        .where((toolCall) => toolCall.arguments.isEmpty)
        .map((toolCall) => toolCall.id)
        .toSet();
  }

  /// Answers a tool call whose arguments were lost to an output-token-limit
  /// truncation with a diagnostic that names the real cause. Without this the
  /// call falls through to a generic missing-argument error and the model
  /// cannot know its own generation was cut off, so the originally intended
  /// action (often a long verification chain) is silently abandoned.
  McpToolResult? _buildTruncatedToolCallArgumentsGuardResult(
    ToolCallInfo toolCall,
  ) {
    if (!_lengthTruncatedToolCallIds.contains(toolCall.id) ||
        toolCall.arguments.isNotEmpty) {
      return null;
    }
    _appliedTurnTransforms.add('truncated_tool_call_arguments_feedback');
    appLog(
      '[Tool] ${toolCall.name} arguments were truncated by the output token '
      'limit; returning truncation diagnostic instead of executing',
    );
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': 'tool_call_arguments_truncated',
        'error':
            'The ${toolCall.name} arguments were lost because the response '
            'hit the output token limit (finish_reason=length) while '
            'generating them.',
        'required_action':
            'Re-issue the ${toolCall.name} call you intended. If the '
            'arguments were long, split the work into several smaller tool '
            'calls instead of one large call, and keep each command short.',
      }),
      isSuccess: false,
      errorMessage:
          'Tool call arguments were truncated by the output token limit; '
          're-issue the intended call as smaller separate calls.',
    );
  }

  Future<ToolResultInfo?> _persistToolResultForPrompt(
    ToolResultInfo toolResult, {
    required int interactionGeneration,
    bool recordConversationTaint = false,
    bool recordBackgroundProcessStart = false,
    bool recordModelEditApplyTelemetry = false,
  }) async {
    final promptToolResult = await _toolResultArtifactStore.persistIfLarge(
      toolResult,
      conversationId:
          _activeResponseConversationIdForGeneration(interactionGeneration) ??
          conversationId,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    if (recordConversationTaint) {
      _conversationTaintState.recordToolResult(promptToolResult.name);
      _recordTurnCommandLedgerEntry(
        promptToolResult,
        interactionGeneration: interactionGeneration,
      );
    }
    if (recordBackgroundProcessStart) {
      _recordBackgroundProcessStartResult(promptToolResult);
    }
    if (recordModelEditApplyTelemetry) {
      await _recordModelEditApplyTelemetry(promptToolResult);
    }
    return promptToolResult;
  }

  // Tool-call execution-policy delegates and process-start bookkeeping,
  // relocated from chat_notifier.dart (F1 ratchet), no behavior change.
  bool _isCommandExecutionTool(String toolName) {
    return _toolCallExecutionPolicy.isCommandExecutionTool(toolName);
  }

  String? _toolCommandArgument(Map<String, dynamic> arguments) {
    return _toolCallExecutionPolicy.toolCommandArgument(arguments);
  }

  bool _toolResultHasSuccessfulExit(ToolResultInfo result) {
    return _toolCallExecutionPolicy.toolResultHasSuccessfulExit(result);
  }

  int? _exitCodeValue(Object? value) {
    return _toolCallExecutionPolicy.exitCodeValue(value);
  }

  void _recordBackgroundProcessStartResult(ToolResultInfo result) {
    final name = result.name.trim().toLowerCase();
    if (name != 'process_start' &&
        (name != 'local_execute_command' ||
            !_asBool(result.arguments['background']))) {
      return;
    }
    final snapshot = _backgroundProcessMonitorService
        .registerProcessStartResult(
          result: result.result,
          arguments: result.arguments,
        );
    if (snapshot == null) {
      return;
    }
    appLog(
      '[BackgroundProcess] Monitoring ${snapshot.jobId} '
      '(${snapshot.status})',
    );
  }

  McpToolResult? _buildStaleProcessStartGuardResult(
    ToolCallInfo toolCall,
    McpToolResult result, {
    required DateTime dispatchedAt,
  }) {
    if (toolCall.name.trim().toLowerCase() != 'process_start' ||
        !result.isSuccess) {
      return null;
    }
    final decoded = _tryDecodeMap(result.result);
    if (decoded == null ||
        decoded['ok'] != true ||
        decoded['duplicate_existing'] == true) {
      return null;
    }
    final startedAtText = decoded['started_at']?.toString().trim();
    if (startedAtText == null || startedAtText.isEmpty) {
      return null;
    }
    final startedAt = DateTime.tryParse(startedAtText);
    if (startedAt == null) {
      return null;
    }
    final staleBefore = dispatchedAt.subtract(const Duration(seconds: 5));
    if (!startedAt.isBefore(staleBefore)) {
      return null;
    }

    final payload = jsonEncode({
      'ok': false,
      'code': 'background_process_start_stale_result',
      'error':
          'process_start returned a non-duplicate job result whose started_at '
          'predates this tool call. Treat the start result as stale until the '
          'process state is verified.',
      'job_id': decoded['job_id'],
      'command': decoded['command'],
      'working_directory': decoded['working_directory'],
      'started_at': startedAtText,
      'tool_dispatched_at': dispatchedAt.toIso8601String(),
      'required_action':
          'Use process_status, process_tail, or process_wait for the job_id '
          'if it should still be monitored. Do not report the command as newly '
          'started from this result.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'process_start returned a stale job result.',
    );
  }

  bool _asBool(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  bool _toolResultTimedOut(ToolResultInfo result) {
    return _toolCallExecutionPolicy.toolResultTimedOut(result);
  }

  String? _toolResultErrorText(ToolResultInfo result) {
    return _toolCallExecutionPolicy.toolResultErrorText(result);
  }

  /// Accumulates executed commands for the transcript claim guard. The ledger
  /// is scoped to the interaction generation, which stays constant across
  /// repair revivals within a turn while resetting on the next user message.
  void _recordTurnCommandLedgerEntry(
    ToolResultInfo toolResult, {
    required int interactionGeneration,
  }) {
    if (_turnCommandLedgerGeneration != interactionGeneration) {
      _turnCommandLedgerGeneration = interactionGeneration;
      _turnCommandLedger.clear();
    }
    if (!_isCommandExecutionTool(toolResult.name)) {
      return;
    }
    final command = _toolCommandArgument(toolResult.arguments);
    if (command != null) {
      _turnCommandLedger.add(command);
    }
  }
}
