// Same-library tool-loop batch execution extension.
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
    required bool verifierOnlyContinuation,
  }) async {
    final batchToolResults = <ToolResultInfo>[];
    final pendingBatchCalls = <ToolCallInfo>[];
    var nextCommandRetryGeneration = commandRetryGeneration;
    final terminalSuccessState = ToolTerminalSuccessBatchState();
    final projectRoot = _projectRootForGeneration(interactionGeneration);
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return _ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
      );
    }
    final ownerConversation = _conversationForId(owner.conversationId);
    if (ownerConversation == null) {
      return _ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
      );
    }
    final ownerWorkspaceMode = ownerConversation.workspaceMode;
    final ownerBlockingAssumptions =
        List<ConversationContractItemProvenance>.unmodifiable(
          ownerConversation.effectiveWorkflowSpec.blockingAssumptions,
        );
    int ownerMutationGeneration() {
      return _conversationForId(owner.conversationId)?.mutationGeneration ?? 0;
    }

    String resolveProjectPath(String path) =>
        ToolDedupeKeys.resolvePath(path, projectRoot: projectRoot);
    for (final toolCall in currentToolCalls) {
      final mutationGeneration = ownerMutationGeneration();
      final shouldSuppressAdditionalReadReplay =
          _successfulReadResultReplayCache.shouldSuppressAdditionalReplay(
            toolCall: toolCall,
            interactionGeneration: interactionGeneration,
            mutationGeneration: mutationGeneration,
            resolveProjectPath: resolveProjectPath,
          );
      final toolCallKey = _toolExecutionKey(
        toolCall,
        projectRoot: projectRoot,
        commandRetryGeneration: nextCommandRetryGeneration,
      );
      final shouldBlockTimedOutCommandRetry =
          const TimedOutCommandRetryGuard().evaluate(
            TimedOutCommandRetryInput(
              toolCall: toolCall,
              executedToolResults: executedToolResults,
            ),
          ) !=
          null;
      if ((executedToolCallKeys.contains(toolCallKey) &&
              !_shouldAllowRepeatedToolExecution(toolCall) &&
              !shouldBlockTimedOutCommandRetry) ||
          shouldSuppressAdditionalReadReplay) {
        appLog(
          shouldSuppressAdditionalReadReplay
              ? '[InspectionReplay] Additional unchanged read_file replay '
                    'suppressed: ${toolCall.arguments}'
              : '[Tool] Duplicate tool call detected, skipping: '
                    '${toolCall.name} ${toolCall.arguments}',
        );
        _logToolLifecycleEvent(
          generation: interactionGeneration,
          toolCall: toolCall,
          lifecycleState: 'skipped',
          loopIndex: iteration,
          schedulerMode: ToolExecutionScheduler.executionModeFor(toolCall),
          resultStatus: 'skipped',
          skipReason: shouldSuppressAdditionalReadReplay
              ? 'repeated_read_replay_exhausted'
              : 'duplicate_tool_call',
        );
        await _modelEditTelemetry!.runtimeSamplerFeedback.recordEvent(
          RuntimeSamplerToolLoopRepetitionEvent(
            owner: owner,
            baselineProfile: _modelEditApplyTelemetryBaseline(),
          ),
        );
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
      const MaterialContractAssumptionGuard().isContractMutation,
    );

    final scheduledResults = await ToolExecutionScheduler.executeBatch(
      toolCalls: pendingBatchCalls,
      execute: (toolCall) async {
        final validationProbeGuardResult = const GoalValidationProbeGuard()
            .evaluate(
              toolCall,
              verifierOnlyContinuation: verifierOnlyContinuation,
            );
        if (validationProbeGuardResult != null) {
          return validationProbeGuardResult;
        }
        final materialAssumptionGuardResult =
            const MaterialContractAssumptionGuard().evaluate(
              toolCall,
              workspaceMode: ownerWorkspaceMode,
              blockingAssumptions: ownerBlockingAssumptions,
            );
        if (materialAssumptionGuardResult != null) {
          return materialAssumptionGuardResult;
        }
        final truncatedArgumentsGuardResult =
            _buildTruncatedToolCallArgumentsGuardResult(toolCall, owner: owner);
        if (truncatedArgumentsGuardResult != null) {
          return truncatedArgumentsGuardResult;
        }
        final analysisOptionsLintEditGuardResult =
            const AnalysisOptionsLintEditGuard().buildResult(
              toolCall: toolCall,
              executedToolResults: executedToolResults,
            );
        if (analysisOptionsLintEditGuardResult != null) {
          return analysisOptionsLintEditGuardResult;
        }
        final guardResult = const GitTagFormatInspectionGuard().evaluate(
          GitTagFormatInspectionInput(
            toolCall: toolCall,
            resolvedArguments: _resolveProjectScopedArguments(
              toolCall.name,
              toolCall.arguments,
            ),
            executedToolResults: executedToolResults,
          ),
        );
        if (guardResult != null) {
          return guardResult;
        }
        final timeoutRetryGuardResult = const TimedOutCommandRetryGuard()
            .evaluate(
              TimedOutCommandRetryInput(
                toolCall: toolCall,
                executedToolResults: executedToolResults,
              ),
            );
        if (timeoutRetryGuardResult != null) {
          return timeoutRetryGuardResult;
        }
        final productionReleaseGuardResult =
            _buildProductionReleaseApprovalGuardResult(
              toolCall,
              currentAssistantContent: currentAssistantContent,
              approvalEvidence: _releaseEvidenceFor(interactionGeneration),
            );
        if (productionReleaseGuardResult != null) {
          return productionReleaseGuardResult;
        }
        McpToolResult? codingCommandPreflightGuardResult;
        final preflightToolName = toolCall.name.trim().toLowerCase();
        if (preflightToolName == 'local_execute_command' ||
            preflightToolName == 'process_start') {
          final preflightArguments = _resolveProjectScopedArguments(
            toolCall.name,
            toolCall.arguments,
          );
          codingCommandPreflightGuardResult =
              CodingCommandOutputGuardrailService.buildPreflightResult(
                toolName: toolCall.name,
                command: LocalShellTools.normalizeCommand(
                  (preflightArguments['command'] as String?)?.trim() ?? '',
                ),
                workingDirectory:
                    (preflightArguments['working_directory'] as String?)
                        ?.trim() ??
                    '',
              );
        }
        if (codingCommandPreflightGuardResult != null) {
          return codingCommandPreflightGuardResult;
        }
        final savedValidationGuard = const SavedValidationCommandGuard()
            .evaluate(
              SavedValidationCommandInput(
                owner: owner,
                toolCall: toolCall,
                savedCommand: _savedValidationCommandForGeneration(
                  interactionGeneration,
                ),
                ownerProjectRoot: projectRoot,
              ),
            );
        if (savedValidationGuard != null) return savedValidationGuard;
        final savedTargetGuard = const SavedTaskTargetScopeGuard().evaluate(
          SavedTaskTargetScopeInput(
            owner: owner,
            toolCall: toolCall,
            ownerTask: _savedTaskForGeneration(interactionGeneration),
            ownerProjectRoot: projectRoot,
          ),
        );
        if (savedTargetGuard != null) return savedTargetGuard;
        final verifierReplayDecision =
            const CommandDiagnosticVerifierReplayGuard().evaluate(
              CommandDiagnosticVerifierReplayInput(
                currentToolCall: toolCall,
                focus: _commandDiagnosticRepairFocusFor(ownerConversation),
                attemptedCommandKey: _toolFailureKey(
                  toolCall,
                  projectRoot: projectRoot,
                  commandRetryGeneration: nextCommandRetryGeneration,
                ),
                commandEffect: const ToolCapabilityClassifier()
                    .classify(toolCall.name, arguments: toolCall.arguments)
                    .commandEffect,
                pendingToolCalls: pendingBatchCalls,
              ),
            );
        if (verifierReplayDecision.isBlocked) {
          appLog(
            '[CommandDiagnosticRepairFocus] blocked unchanged verifier replay; '
            'signatureStreak='
            '${verifierReplayDecision.logFields!.signatureStreak}',
          );
          return verifierReplayDecision.result!;
        }
        final unexecutedFileMutationGuardResult =
            const UnexecutedFileMutationBeforeCommandGuard().evaluate(
              UnexecutedFileMutationGuardInput(
                owner: owner,
                toolCall: toolCall,
                currentAssistantContent: currentAssistantContent,
                pendingToolCalls: pendingBatchCalls,
                executedToolResults: executedToolResults,
              ),
            );
        if (unexecutedFileMutationGuardResult != null) {
          return unexecutedFileMutationGuardResult;
        }
        final mutationGeneration = ownerMutationGeneration();
        if (allowSuccessfulReadResultReplay) {
          final replayedResult = _successfulReadResultReplayCache.lookup(
            toolCall: toolCall,
            interactionGeneration: interactionGeneration,
            mutationGeneration: mutationGeneration,
            resolveProjectPath: resolveProjectPath,
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
            const ProcessStartResultPolicy().buildStaleGuardResult(
              toolCall,
              dispatchResult,
              dispatchedAt: dispatchedAt,
            ) ??
            dispatchResult;
        if (!_toolFailureClassifier.isApprovalDenial(effectiveResult)) {
          _recordExecutedVerifierReplayCandidate(owner, toolCall);
        }
        if (allowSuccessfulReadResultReplay) {
          _successfulReadResultReplayCache.record(
            toolCall: toolCall,
            result: effectiveResult.result,
            isSuccess: effectiveResult.isSuccess,
            interactionGeneration: interactionGeneration,
            mutationGeneration: mutationGeneration,
            resolveProjectPath: resolveProjectPath,
          );
        }
        return effectiveResult;
      },
      onLifecycle: (event) => _logScheduledToolLifecycleEvent(
        event,
        generation: interactionGeneration,
        loopIndex: iteration,
      ),
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
        projectRoot: projectRoot,
        commandRetryGeneration: nextCommandRetryGeneration,
      );
      // Failure identity ignores narration; mutations also strip it so a
      // reworded reason cannot repeat the same side effect.
      final toolFailureKey = _toolFailureKey(
        toolCall,
        projectRoot: projectRoot,
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
        taintSourceResult: result,
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
      if (const CommandDiagnosticVerifierReplayGuard().matches(result)) {
        toolFailureCounts.remove(toolFailureKey);
      } else if (disposition == ToolResultDisposition.success) {
        if (_toolCallExecutionPolicy.isCommandExecutionTool(toolCall.name)) {
          _resetCommandDiagnosticStreak(owner, toolFailureKey);
        }
        final isMutationTool =
            !const GoalValidationProbeGuard().matches(result) &&
            const MaterialContractAssumptionGuard().isContractMutation(
              toolCall,
            );
        if (isMutationTool) {
          _clearCommandDiagnosticRepairFocus(owner);
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
                .recordMutationGeneration(conversationId: owner.conversationId);
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
          owner: owner,
          commandKey: toolFailureKey,
          toolResult: promptToolResult,
        );
        appLog(
          '[Tool] Command completed with an actionable non-zero outcome; '
          'returning diagnostics without counting an execution failure',
        );
      } else {
        await _modelEditTelemetry!.runtimeSamplerFeedback.recordEvent(
          RuntimeSamplerMalformedToolCallEvent(
            owner: owner,
            baselineProfile: _modelEditApplyTelemetryBaseline(),
            message: '${result.errorMessage ?? ''}\n${result.result}',
          ),
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
          _turnEnd.setHint(owner, ToolLoopExitReason.toolFailureAbort);
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
    ToolCallInfo toolCall, {
    required ChatTurnOwner owner,
  }) {
    if (!_lengthTruncatedToolCallIds.contains(toolCall.id) ||
        toolCall.arguments.isNotEmpty) {
      return null;
    }
    _turnEnd.addTransform(owner, 'truncated_tool_call_arguments_feedback');
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
    McpToolResult? taintSourceResult,
    bool recordBackgroundProcessStart = false,
    bool recordModelEditApplyTelemetry = false,
  }) async {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return null;
    }
    final promptToolResult = await _toolResultArtifactStore.persistIfLarge(
      toolResult,
      conversationId: owner.conversationId,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) {
      return null;
    }
    if (taintSourceResult != null) {
      ToolResultTaintRecorder.record(
        state: _conversationTaintState,
        owner: owner,
        result: taintSourceResult,
      );
      _recordTurnCommandLedgerEntry(
        promptToolResult,
        interactionGeneration: interactionGeneration,
      );
    }
    if (recordBackgroundProcessStart) {
      _recordBackgroundProcessStartResult(owner, promptToolResult);
    }
    if (recordModelEditApplyTelemetry) {
      await _recordModelEditApplyTelemetry(
        owner,
        promptToolResult,
        baselineProfile: _modelEditApplyTelemetryBaseline(),
      );
    }
    return promptToolResult;
  }

  // Tool execution-policy delegates and process-start bookkeeping.




  void _recordBackgroundProcessStartResult(
    ChatTurnOwner owner,
    ToolResultInfo result,
  ) {
    final name = result.name.trim().toLowerCase();
    if (name != 'process_start' &&
        (name != 'local_execute_command' ||
            !_asBool(result.arguments['background']))) {
      return;
    }
    final snapshot = _backgroundProcessMonitorService
        .registerProcessStartResult(
          owner: owner,
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


  /// Accumulates executed commands for the exact turn owner.
  void _recordTurnCommandLedgerEntry(
    ToolResultInfo toolResult, {
    required int interactionGeneration,
  }) {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return;
    if (!_toolCallExecutionPolicy.isCommandExecutionTool(toolResult.name)) {
      return;
    }
    final command = _toolCallExecutionPolicy.toolCommandArgument(toolResult.arguments);
    if (command != null) {
      _turnToolResults.recordCommand(owner, command);
    }
  }
}
