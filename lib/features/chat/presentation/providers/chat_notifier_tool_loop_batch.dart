// Same-library extension on [ChatNotifier]: tool-loop batch execution and
// prompt-result persistence are kept outside the main notifier body while the
// larger tool loop is decomposed.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

enum _ToolLoopBatchStatus { completed, textResponse, cancelled }

class _ToolLoopBatchExecutionResult {
  const _ToolLoopBatchExecutionResult({
    required this.status,
    required this.batchToolResults,
    required this.pendingBatchCalls,
    required this.commandRetryGeneration,
  });

  factory _ToolLoopBatchExecutionResult.completed({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolCallInfo> pendingBatchCalls,
    required int commandRetryGeneration,
  }) {
    return _ToolLoopBatchExecutionResult(
      status: _ToolLoopBatchStatus.completed,
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: commandRetryGeneration,
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

    final scheduledResults = await ToolExecutionScheduler.executeBatch(
      toolCalls: pendingBatchCalls,
      execute: (toolCall) async {
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
        final dispatchedAt = DateTime.now();
        final dispatchResult = await _dispatchToolCall(
          toolCall,
          interactionGeneration: interactionGeneration,
        );
        return _buildStaleProcessStartGuardResult(
              toolCall,
              dispatchResult,
              dispatchedAt: dispatchedAt,
            ) ??
            dispatchResult;
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

      if (result.isSuccess) {
        executedToolCallKeys.add(toolCallKey);
        toolFailureCounts.remove(toolCallKey);
        if (_advancesCommandRetryGeneration(toolCall)) {
          nextCommandRetryGeneration += 1;
        }
      } else {
        await _recordMalformedToolCallRuntimeFeedback(
          '${result.errorMessage ?? ''}\n${result.result}',
        );
        final failureCount = (toolFailureCounts[toolCallKey] ?? 0) + 1;
        toolFailureCounts[toolCallKey] = failureCount;
        if (failureCount >= 2) {
          appLog(
            '[Tool] Same tool (${toolCall.name}) failed $failureCount times consecutively, ending loop',
          );
          _appendToLastMessageForGeneration(
            interactionGeneration,
            '\nFailed to execute tool (${toolCall.name}). Please check your server configuration.\nError: ${result.errorMessage}\n',
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
    }
    if (recordBackgroundProcessStart) {
      _recordBackgroundProcessStartResult(promptToolResult);
    }
    if (recordModelEditApplyTelemetry) {
      await _recordModelEditApplyTelemetry(promptToolResult);
    }
    return promptToolResult;
  }
}
