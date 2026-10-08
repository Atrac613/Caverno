// Same-library tool-loop batch execution extension.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

const _toolFailureClassifier = ToolFailureClassifier();

extension ChatNotifierToolLoopBatch on ChatNotifier {
  // Tool-loop identity and generation helpers. They live with their only
  // caller so the notifier library's aggregate stays within its ratchet.
  String _toolFailureKey(
    ToolCallInfo toolCall, {
    required String? projectRoot,
    int commandRetryGeneration = 0,
  }) => ToolDedupeKeys.toolFailure(
    toolCall,
    projectRoot: projectRoot,
    commandRetryGeneration: commandRetryGeneration,
  );

  bool _shouldAllowRepeatedToolExecution(ToolCallInfo toolCall) =>
      _toolCallExecutionPolicy.shouldAllowRepeatedToolExecution(toolCall);

  bool _advancesCommandRetryGeneration(ToolCallInfo toolCall) =>
      _toolCallExecutionPolicy.advancesCommandRetryGeneration(toolCall);

  bool _advancesStateChangeGeneration(ToolCallInfo toolCall) =>
      _toolCallExecutionPolicy.advancesStateChangeGeneration(toolCall);

  Future<ToolLoopBatchExecutionResult> _executeToolLoopBatch({
    required List<ToolCallInfo> currentToolCalls,
    required String? currentAssistantContent,
    required List<ToolResultInfo> executedToolResults,
    required Set<String> executedToolCallKeys,
    required Map<String, int> toolFailureCounts,
    required int commandRetryGeneration,
    required int stateChangeGeneration,
    required int iteration,
    required int interactionGeneration,
    required bool verifierOnlyContinuation,
  }) async {
    final batchToolResults = <ToolResultInfo>[];
    final pendingBatchCalls = <ToolCallInfo>[];
    var nextCommandRetryGeneration = commandRetryGeneration;
    var nextStateChangeGeneration = stateChangeGeneration;
    final terminalSuccessState = ToolTerminalSuccessBatchState();
    final projectRoot = _projectRootForGeneration(interactionGeneration);
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }
    final ownerConversation = _conversationForId(owner.conversationId);
    if (ownerConversation == null) {
      return ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }
    final ownerWorkspaceMode = ownerConversation.workspaceMode;
    final toolPolicies = TurnToolPolicyChain(
      // Read from the turn, not from the zone. The request zone that carries
      // the role for accounting is opened per request and does not wrap the
      // tool loop, so `ModelUsageRole.current` is `unknown` here — which
      // silently unarmed the parent guard. The generation is the turn's own
      // identity and is in scope either way.
      executingRole: _anabasisRoles.mainLoopRoleFor(interactionGeneration),
      // The tool list already omits editors on a review; this also catches a
      // mutating shell command and a call the model makes from memory.
      turnScope: _isCodeReview(interactionGeneration)
          ? const ReadOnlyReviewScope().evaluate
          : null,
      assumptionGate: MaterialAssumptionConfirmationGate(
        // The turn's memory, not this batch's: the loop builds a gate per
        // iteration, so a field here would re-ask a dismissal every time.
        asked: _materialAssumptionAsks.scopeFor(owner),
        currentSpec: () =>
            _conversationForId(owner.conversationId)?.effectiveWorkflowSpec ??
            const ConversationWorkflowSpec(),
        requestConfirmation:
            ({required item, required itemText, required toolName}) =>
                requestAssumptionConfirmation(
                  owner: owner,
                  item: item,
                  itemText: itemText,
                  toolName: toolName,
                ),
        persist: (spec) => ref
            .read(conversationsNotifierProvider.notifier)
            .updateCurrentWorkflow(
              workflowSpec: spec,
              preserveWorkflowProjection: true,
              conversationId: owner.conversationId,
            ),
      ),
    );
    int ownerMutationGeneration() {
      return _conversationForId(owner.conversationId)?.mutationGeneration ?? 0;
    }

    String resolveProjectPath(String path) =>
        ToolDedupeKeys.resolvePath(path, projectRoot: projectRoot);
    final repeatBudget = _readOnlyCommandRepeatBudget.forBatch(
      interactionGeneration: interactionGeneration,
      commandRetryGeneration: nextCommandRetryGeneration,
      stateChangeGeneration: nextStateChangeGeneration,
    );
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
        stateChangeGeneration: nextStateChangeGeneration,
      );
      final shouldBlockTimedOutCommandRetry =
          const TimedOutCommandRetryGuard().evaluate(
            TimedOutCommandRetryInput(
              toolCall: toolCall,
              executedToolResults: executedToolResults,
            ),
          ) !=
          null;
      final exhaustedRepeat = repeatBudget.isExhausted(toolCall);
      final skipReason = shouldSuppressAdditionalReadReplay
          ? 'repeated_read_replay_exhausted'
          : exhaustedRepeat
          ? 'read_only_command_repeat_exhausted'
          : 'duplicate_tool_call';
      if ((executedToolCallKeys.contains(toolCallKey) &&
              !_shouldAllowRepeatedToolExecution(toolCall) &&
              !shouldBlockTimedOutCommandRetry) ||
          shouldSuppressAdditionalReadReplay ||
          exhaustedRepeat) {
        appLog(
          '[Tool] Skip ($skipReason): ${toolCall.name} ${toolCall.arguments}',
        );
        _logToolLifecycleEvent(
          generation: interactionGeneration,
          toolCall: toolCall,
          lifecycleState: 'skipped',
          loopIndex: iteration,
          schedulerMode: ToolExecutionScheduler.executionModeFor(toolCall),
          resultStatus: 'skipped',
          skipReason: skipReason,
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
      repeatBudget.recordExecution(toolCall);
      pendingBatchCalls.add(toolCall);
    }

    final diagnosticBaseline = await _captureCodingDiagnosticFeedbackBaseline(
      pendingBatchCalls,
      interactionGeneration: interactionGeneration,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }

    final allowSuccessfulReadResultReplay = !pendingBatchCalls.any(
      const MaterialContractAssumptionGuard().isContractMutation,
    );

    _turnToolResults.track(owner, executedToolResults);
    final scheduledResults = await ToolExecutionScheduler.executeBatch(
      toolCalls: pendingBatchCalls,
      execute: (call) async {
        final blockerRefusal = _refuseToolAfterGoalBlocker(
          call,
          interactionGeneration: interactionGeneration,
        );
        if (blockerRefusal != null) return blockerRefusal;
        // The guards below cast arguments, so a mistyped one must be caught
        // here: session e3a9f3f0's write_file content object threw in one.
        final argumentCheck = _mcpToolService?.checkToolArguments(call);
        if (argumentCheck?.failure case final failure?) return failure;
        final toolCall = argumentCheck?.toolCall ?? call;
        final validationProbeGuardResult = const GoalValidationProbeGuard()
            .evaluate(
              toolCall,
              verifierOnlyContinuation: verifierOnlyContinuation,
            );
        if (validationProbeGuardResult != null) {
          return validationProbeGuardResult;
        }
        final policyRefusal = await toolPolicies.evaluate(
          toolCall,
          workspaceMode: ownerWorkspaceMode,
        );
        if (policyRefusal != null) return policyRefusal;
        if (!_isCurrentInteractionGeneration(interactionGeneration)) {
          // The chain may have waited on the user. Anything decided for a turn
          // the conversation has moved past must not still be executed.
          return approvalTurnExpiredResult(toolCall.name);
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
        final uninspectedCommitGuardResult = const UninspectedCommitGuard()
            .evaluate(
              UninspectedCommitInput(
                toolCall: toolCall,
                executedToolResults: executedToolResults,
              ),
            );
        if (uninspectedCommitGuardResult != null) {
          return uninspectedCommitGuardResult;
        }
        final productionReleaseGuardResult = _productionReleaseApprovals
            .buildGuardResult(
              toolCall,
              currentAssistantContent: currentAssistantContent,
              evidence: _productionReleaseApprovals.evidenceFor(
                interactionGeneration,
              ),
              executedToolResults: executedToolResults,
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
            ownerTask: _turnOwnerSnapshotForGeneration(
              interactionGeneration,
            )?.savedTask,
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
              result: replayedResult.result,
              isSuccess: true,
              outcome: replayedResult.outcome,
            );
          }
        }
        final verifiedReplay = VerifiedPytestReplayPolicy.reuse(
          call: toolCall,
          results: executedToolResults,
          pendingCalls: pendingBatchCalls,
          projectRoot: projectRoot,
        );
        if (verifiedReplay != null) return verifiedReplay;
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
          final verifier = ExecutedVerifierReplayPolicy.prepare(
            toolCall,
            effectiveResult,
          );
          if (verifier != null) {
            _recordExecutedVerifierReplayCandidate(owner, verifier);
          }
        }
        if (allowSuccessfulReadResultReplay) {
          _successfulReadResultReplayCache.record(
            toolCall: toolCall,
            result: effectiveResult.result,
            isSuccess: effectiveResult.isSuccess,
            interactionGeneration: interactionGeneration,
            mutationGeneration: mutationGeneration,
            outcome: effectiveResult.outcome,
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
      return ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }

    for (final scheduledResult in scheduledResults) {
      final toolCall = scheduledResult.toolCall;
      final toolCallKey = _toolExecutionKey(
        toolCall,
        projectRoot: projectRoot,
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
      // Failure identity ignores narration; mutations also strip it so a
      // reworded reason cannot repeat the same side effect.
      final toolFailureKey = _toolFailureKey(
        toolCall,
        projectRoot: projectRoot,
        commandRetryGeneration: nextCommandRetryGeneration,
      );
      // The diagnostic streak needs a key that survives an edit. The failure
      // key above deliberately does not: commandRetryGeneration advances on
      // every write_file or edit_file so a retry is not mistaken for a
      // duplicate. Reusing it for the streak made a plateau unobservable by
      // construction, because the edit between two attempts is exactly what
      // the streak is trying to look across.
      final commandStreakKey = _toolFailureKey(
        toolCall,
        projectRoot: projectRoot,
      );
      if (scheduledResult.error != null) {
        final error = scheduledResult.error!;
        appLog('[Tool] Error: $error');
        // The turn ends and the call stays unexecuted on purpose, so handlers
        // must return failures rather than throw and take the turn with them.
        _appendToLastMessageForGeneration(
          interactionGeneration,
          '[Tool dispatch error: $error]\n',
        );
        return ToolLoopBatchExecutionResult.textResponse(
          batchToolResults: batchToolResults,
          pendingBatchCalls: pendingBatchCalls,
          commandRetryGeneration: nextCommandRetryGeneration,
          stateChangeGeneration: nextStateChangeGeneration,
        );
      }

      final result = scheduledResult.result!;
      final toolResult = result.isSuccess
          ? result.result
          : (result.result.trim().isNotEmpty
                ? result.result
                : 'Error: ${result.errorMessage}');

      await observeToolOutcomeShadow(
        store: ref.read(llmSessionLogStoreProvider),
        settingsEnabled: _settings.enableLlmSessionLogs,
        context: _llmSessionLogContextForGeneration(interactionGeneration),
        toolName: toolCall.name,
        outcome: result.outcome,
        renderedPayload: toolResult,
        toolCallId: toolCall.id,
        loopIndex: iteration,
      );
      unawaited(
        observeShellWrites(
          store: ref.read(llmSessionLogStoreProvider),
          settingsEnabled: _settings.enableLlmSessionLogs,
          context: _llmSessionLogContextForGeneration(interactionGeneration),
          toolName: toolCall.name,
          renderedPayload: toolResult,
          toolCallId: toolCall.id,
        ),
      );

      if (result.isSuccess && toolCall.name == 'load_skill') {
        loadedSkills.record(
          conversationId: owner.conversationId,
          skillRef:
              (toolCall.arguments['id'] ?? toolCall.arguments['name'] ?? '')
                  .toString(),
        );
      }

      final promptToolResult = await _persistToolResultForPrompt(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: toolResult,
          // Carried, not re-derived: the exit status is read a few lines below
          // from `result.outcome`, and every downstream consumer had to parse
          // it back out of the payload string because it stopped here.
          outcome: result.outcome,
        ),
        interactionGeneration: interactionGeneration,
        taintSourceResult: result,
        recordBackgroundProcessStart: true,
        recordModelEditApplyTelemetry: true,
      );
      if (promptToolResult == null) {
        return ToolLoopBatchExecutionResult.cancelled(
          commandRetryGeneration: nextCommandRetryGeneration,
          stateChangeGeneration: nextStateChangeGeneration,
        );
      }
      batchToolResults.add(promptToolResult);
      executedToolResults.add(promptToolResult);

      final disposition = _toolFailureClassifier.classify(toolCall, result);
      if (const CommandDiagnosticVerifierReplayGuard().matches(result)) {
        toolFailureCounts.remove(toolFailureKey);
      } else if (disposition == ToolResultDisposition.success) {
        if (_toolCallExecutionPolicy.isCommandExecutionTool(toolCall.name)) {
          // A shell command that exits non-zero is normalized to a successful
          // tool result on purpose — the call worked, the command reported a
          // problem. That is right for everything else here, but it used to
          // reset the diagnostic streak on exactly the runs the streak exists
          // to count, so a verifier could report the same error forever and
          // never register as a plateau. Read the command's own exit status
          // rather than the tool call's.
          if (result.outcome?.hasFailingExitCode ?? false) {
            _recordCommandDiagnosticStreak(
              owner: owner,
              commandKey: commandStreakKey,
              toolResult: promptToolResult,
            );
          } else {
            _resetCommandDiagnosticStreak(owner, commandStreakKey);
          }
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
        if (_advancesStateChangeGeneration(toolCall)) {
          nextStateChangeGeneration += 1;
        }
      } else if (disposition ==
          ToolResultDisposition.actionableCommandFailure) {
        toolFailureCounts.remove(toolFailureKey);
        _recordCommandDiagnosticStreak(
          owner: owner,
          commandKey: commandStreakKey,
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
          // Final like a denied approval to the loop; not one to the reader.
          final policyRefusal = _toolFailureClassifier.policyRefusal(result);
          if (policyRefusal != null &&
              policyRefusal.requiredAction.isNotEmpty) {
            // A policy refusal names a *different* call to make, so ending the
            // turn takes away the one move that was left. Measured: an Anabasis
            // parent lost a whole turn to a compound shell expression it was
            // asked to split, and another to a tool its own prompt told it to
            // use. The refusal still stands -- the call does not run, and the
            // loop's own iteration cap bounds a model that ignores the
            // instruction. An approval denial keeps aborting: there the answer
            // came from the user, and continuing only asks them again.
            appLog(
              '[Tool] ${toolCall.name} refused by policy '
              '(${policyRefusal.code}) $failureCount times; the refusal names '
              'a next action, so the turn continues',
            );
            continue;
          }
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
            const ToolLoopAbortNotice().build(
              toolName: toolCall.name,
              errorMessage: result.errorMessage,
              isApprovalDenial: isDenial,
              isExternalMcpResult: result.isExternalMcpResult,
              executedToolResults: executedToolResults,
              policyRefusalCode: policyRefusal?.code,
              policyRefusalAction: policyRefusal?.requiredAction,
            ),
          );
          _turnEnd.setHint(owner, ToolLoopExitReason.toolFailureAbort);
          return ToolLoopBatchExecutionResult.textResponse(
            batchToolResults: batchToolResults,
            pendingBatchCalls: pendingBatchCalls,
            commandRetryGeneration: nextCommandRetryGeneration,
            stateChangeGeneration: nextStateChangeGeneration,
          );
        }
      }
    }

    final blockedResponse = _recordedGoalBlockerResponse(owner);
    if (blockedResponse != null) {
      _appendRecoveredAssistantResponse(
        blockedResponse,
        interactionGeneration: interactionGeneration,
      );
      return ToolLoopBatchExecutionResult.textResponse(
        batchToolResults: batchToolResults,
        pendingBatchCalls: pendingBatchCalls,
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }

    final diagnosticFeedback = await _buildCodingDiagnosticFeedbackToolResult(
      batchToolResults,
      interactionGeneration: interactionGeneration,
      baseline: diagnosticBaseline,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }
    if (diagnosticFeedback != null) {
      final promptDiagnosticFeedback = await _persistToolResultForPrompt(
        diagnosticFeedback,
        interactionGeneration: interactionGeneration,
      );
      if (promptDiagnosticFeedback == null) {
        return ToolLoopBatchExecutionResult.cancelled(
          commandRetryGeneration: nextCommandRetryGeneration,
          stateChangeGeneration: nextStateChangeGeneration,
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
      return ToolLoopBatchExecutionResult.cancelled(
        commandRetryGeneration: nextCommandRetryGeneration,
        stateChangeGeneration: nextStateChangeGeneration,
      );
    }
    if (commandOutputFeedback != null) {
      final promptCommandOutputFeedback = await _persistToolResultForPrompt(
        commandOutputFeedback,
        interactionGeneration: interactionGeneration,
      );
      if (promptCommandOutputFeedback == null) {
        return ToolLoopBatchExecutionResult.cancelled(
          commandRetryGeneration: nextCommandRetryGeneration,
          stateChangeGeneration: nextStateChangeGeneration,
        );
      }
      batchToolResults.add(promptCommandOutputFeedback);
      executedToolResults.add(promptCommandOutputFeedback);
    }

    return ToolLoopBatchExecutionResult.completed(
      batchToolResults: batchToolResults,
      pendingBatchCalls: pendingBatchCalls,
      commandRetryGeneration: nextCommandRetryGeneration,
      stateChangeGeneration: nextStateChangeGeneration,
      terminalSuccessMessage: terminalSuccessState.message,
    );
  }

  /// Supplies the guard with this notifier's notion of a truncated completion.
  Set<String> _truncationCasualties(ChatCompletionResult result) =>
      truncatedToolCallArgumentsGuard.casualtyToolCallIds(
        result,
        truncated: ProposalParsingTextUtils.isCompletionTruncated(
          result.finishReason,
        ),
      );

  /// Answers a tool call whose arguments were lost to an output-token-limit
  /// truncation. Recording the transform and the log line stays here: the
  /// guard itself is stateless so it can be tested without a notifier.
  McpToolResult? _buildTruncatedToolCallArgumentsGuardResult(
    ToolCallInfo toolCall, {
    required ChatTurnOwner owner,
  }) {
    if (!truncatedToolCallArgumentsGuard.isCasualty(
      toolCall,
      _lengthTruncatedToolCallIds,
    )) {
      return null;
    }
    _turnEnd.addTransform(owner, 'truncated_tool_call_arguments_feedback');
    appLog(
      '[Tool] ${toolCall.name} arguments were truncated by the output token '
      'limit; returning truncation diagnostic instead of executing',
    );
    return truncatedToolCallArgumentsGuard.diagnosticFor(toolCall);
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
      const TurnCommandExecutionRecorder().record(
        ledger: _turnToolResults,
        owner: owner,
        toolResult: promptToolResult,
        sourceResult: taintSourceResult,
        resolveArguments: (toolCall) =>
            _resolveProjectScopedArguments(toolCall.name, toolCall.arguments),
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
            !argumentIsTruthy(result.arguments['background']))) {
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

  /// Finishes a tool loop once it stops issuing calls: runs a batch declared
  /// at the iteration limit, gathers the final evidence, streams the answer,
  /// tries the post-answer recoveries, then replays a verifier or closes the
  /// turn. Moved out of `_executeToolCalls` unchanged; the parameters are the
  /// loop state it reads, and the four it reassigns are only read here.
  Future<void> _finalizeToolLoop({
    required ChatTurnOwner turnOwner,
    required TurnOwnerSnapshot? turnSnapshot,
    required int interactionGeneration,
    required List<ToolCallInfo> currentToolCalls,
    required String? currentAssistantContent,
    required bool hasTextResponse,
    required bool truncatedBeforeAnswer,
    required int iteration,
    required ToolLoopExecutionBudget budget,
    required List<ToolResultInfo> executedToolResults,
    required Set<String> executedToolCallKeys,
    required Map<String, int> toolFailureCounts,
    required int commandRetryGeneration,
    required int stateChangeGeneration,
    required bool savedValidationSucceededInLoop,
    required Set<String> attemptedCompletionVerificationMutationSignatures,
    required Map<String, int> verificationFailureCounts,
    required Set<String> transcriptRepairSignatures,
    required Set<String> activeToolNames,
    required bool toolSearchEnabled,
    required List<Map<String, dynamic>>? stableToolDefinitions,
    required bool replayVerifierImmediatelyAfterMutation,
    required bool verifierOnlyContinuation,
    required List<Map<String, dynamic>> Function(McpToolService) selectedDefinitionsFor,
  }) async {
    void acceptAnswer(String answer) {
      _appendRecoveredAssistantResponse(
        answer,
        interactionGeneration: interactionGeneration,
      );
      currentAssistantContent = answer;
      hasTextResponse = true;
    }

    if (!hasTextResponse &&
        currentToolCalls.isNotEmpty &&
        iteration >= budget.limit) {
      appLog(
        '[Tool] Tool loop reached limit with a declared pending batch; '
        'executing it before finalization',
      );
      final finalBatchResult = await _executeToolLoopBatch(
        currentToolCalls: currentToolCalls,
        currentAssistantContent: currentAssistantContent,
        executedToolResults: executedToolResults,
        executedToolCallKeys: executedToolCallKeys,
        toolFailureCounts: toolFailureCounts,
        commandRetryGeneration: commandRetryGeneration,
        stateChangeGeneration: stateChangeGeneration,
        iteration: iteration + 1,
        interactionGeneration: interactionGeneration,
        verifierOnlyContinuation: verifierOnlyContinuation,
      );
      if (finalBatchResult.didCancel) return;
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;
      commandRetryGeneration = finalBatchResult.commandRetryGeneration;
      final completedToolCallIds = finalBatchResult.batchToolResults
          .map((result) => result.id)
          .toSet();
      currentToolCalls = finalBatchResult.pendingBatchCalls
          .where((toolCall) => !completedToolCallIds.contains(toolCall.id))
          .toList(growable: false);
      if (finalBatchResult.batchToolResults.isNotEmpty &&
          currentToolCalls.isEmpty) {
        _turnEnd.setHintIfAbsent(
          turnOwner,
          ToolLoopExitReason.pendingBatchExecuted,
        );
      }
    }

    final unexecutedPendingToolResults = _buildUnexecutedPendingToolResults(
      toolCalls: currentToolCalls,
      executedToolCallKeys: executedToolCallKeys,
      commandRetryGeneration: commandRetryGeneration,
      projectRoot: _projectRootForGeneration(interactionGeneration),
    );
    final unexecutedFileSideEffect = _claims
        .buildUnexecutedFileSideEffectToolResult(
          candidateResponse: currentAssistantContent ?? '',
          toolResults: [
            ...executedToolResults,
            ...unexecutedPendingToolResults,
          ],
          latestUserContent: const SavedTaskAuthoredRequestText().resolve(
            latestUserContent: turnSnapshot!.latestUserContent,
            savedTask: turnSnapshot.savedTask,
          ),
          fileChangesAlreadyCaptured: projectTaskHasCapturedChanges(
            _conversationForGeneration(interactionGeneration),
          ),
        );
    // Re-run analysis so final diagnostics reflect the post-edit state.
    final finalDiagnosticFeedback = hasTextResponse
        ? null
        : await _buildFinalCodingDiagnosticFeedbackToolResult(
            executedToolResults,
            interactionGeneration: interactionGeneration,
          );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    if (finalDiagnosticFeedback != null) {
      CodingFeedbackTelemetry.logDiagnostics(finalDiagnosticFeedback);
    }
    final finalToolResults = <ToolResultInfo>[
      ...executedToolResults,
      ...unexecutedPendingToolResults,
      ?unexecutedFileSideEffect,
      ?finalDiagnosticFeedback,
    ];
    var finalCompletionEvidence = ToolResultPromptBuilder.completionEvidence(
      finalToolResults,
    );
    finalCompletionEvidence = _goalCompletionEvidence
        .settleSuccessfulSavedValidation(
          finalCompletionEvidence,
          conversation: _conversationForGeneration(interactionGeneration),
          succeeded: savedValidationSucceededInLoop,
        );
    var finalCompletionEvidenceIsCurrent = true;
    if (!hasTextResponse && finalToolResults.isNotEmpty) {
      appLog('[Tool] Resending tool results as user message');
      if (!ref.mounted) return;
      final preFinalAnswerContent =
          _lastMessageContentForGeneration(interactionGeneration) ?? '';
      final toolResultCountBeforeFinalAnswer = finalToolResults.length;
      final mcpToolService = _mcpToolService;
      final recoveryTools = mcpToolService == null
          ? const <Map<String, dynamic>>[]
          : selectedDefinitionsFor(mcpToolService);
      final canPreparePendingActionRecovery = _pendingActions
          .canPrepareActionOnlyRecovery(
            cutOffBeforeAnswer: truncatedBeforeAnswer,
            isCodingWorkspace: _isCodingWorkspaceOrMode(interactionGeneration),
            hasAvailableActionTools: _hasCodingContinuationRecoveryTools(
              recoveryTools,
            ),
            retryAlreadyUsed: _pendingActionLengthRecoveryGenerations.contains(
              interactionGeneration,
            ),
            completionEvidence: finalCompletionEvidence,
          );
      var streamedFinalAnswer = await _streamToolResultAnswerWithContextRetry(
        toolResults: finalToolResults,
        interactionGeneration: interactionGeneration,
        completionEvidence: finalCompletionEvidence,
        deferIncompleteLengthRecovery: canPreparePendingActionRecovery,
      );
      if (finalToolResults.length != toolResultCountBeforeFinalAnswer) {
        finalCompletionEvidenceIsCurrent = false;
      }
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      final shouldRequestPendingActionRecovery = _pendingActions
          .shouldRequestActionOnlyRecovery(
            cutOffBeforeAnswer: truncatedBeforeAnswer,
            finishReason: _responseMetadata.finishReasonFor(turnOwner),
            isCodingWorkspace: _isCodingWorkspaceOrMode(interactionGeneration),
            hasAvailableActionTools: _hasCodingContinuationRecoveryTools(
              recoveryTools,
            ),
            retryAlreadyUsed: _pendingActionLengthRecoveryGenerations.contains(
              interactionGeneration,
            ),
            completionEvidence: finalCompletionEvidence,
          );
      if (shouldRequestPendingActionRecovery) {
        _pendingActionLengthRecoveryGenerations.add(interactionGeneration);
        _turnEnd.addTransform(turnOwner, 'pending_action_length_recovery');
        appLog(
          '[PendingActionLengthRecovery] Requesting one bounded tool-aware '
          'retry; evidence=${finalCompletionEvidence.summary}',
        );
        final recoveryResult = await _requestCodingContinuationRecovery(
          candidateResponse: streamedFinalAnswer,
          tools: recoveryTools,
          interactionGeneration: interactionGeneration,
          requireContinuationRequest: false,
          executedToolResults: finalToolResults,
          forcedRecoveryCode: 'length_truncated_pending_action',
          forcedRecoveryPrompt: _pendingActions.buildRetryPrompt(
            finalCompletionEvidence,
          ),
        );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (recoveryResult?.hasToolCalls == true) {
          appLog(
            '[PendingActionLengthRecovery] Tool-aware retry requested one or '
            'more tool calls',
          );
          _recordHiddenEvidence(turnOwner, streamedFinalAnswer);
          _removeStreamedAnswerSuffixForGeneration(
            interactionGeneration,
            preAnswerContent: preFinalAnswerContent,
          );
          final recoveredToolCalls = recoveryResult!.toolCalls!;
          await _executeToolCalls(
            recoveredToolCalls,
            assistantContent: recoveryResult.content.isNotEmpty
                ? recoveryResult.content
                : streamedFinalAnswer,
            toolSearchEnabled: toolSearchEnabled,
            selectedToolNames: {
              ...activeToolNames,
              ...recoveredToolCalls.map((toolCall) => toolCall.name),
            },
            stableToolDefinitions: stableToolDefinitions,
            completionVerificationFailureCounts: verificationFailureCounts,
            narratedTranscriptRepairSignatures: transcriptRepairSignatures,
            replayVerifierImmediatelyAfterMutation:
                replayVerifierImmediatelyAfterMutation,
            verifierOnlyContinuation: verifierOnlyContinuation,
            interactionGeneration: interactionGeneration,
          );
          return;
        }
        final recoveryContent = recoveryResult?.content.trim() ?? '';
        if (recoveryContent.isNotEmpty) {
          _recordHiddenEvidence(turnOwner, streamedFinalAnswer);
          _removeStreamedAnswerSuffixForGeneration(
            interactionGeneration,
            preAnswerContent: preFinalAnswerContent,
          );
          _appendRecoveredAssistantResponse(
            recoveryContent,
            interactionGeneration: interactionGeneration,
          );
          streamedFinalAnswer = recoveryContent;
        }
      }

      if (mcpToolService != null) {
        final streamVerificationBatchToolResults = <ToolResultInfo>[];
        final tools = recoveryTools;
        final backgroundProcessRepairResult =
            await _requestBackgroundProcessMonitorRepairForCompletionClaim(
              candidateResponse: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              tools: tools,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (backgroundProcessRepairResult != null) {
          if (backgroundProcessRepairResult.hasToolCalls) {
            appLog(
              '[BackgroundProcess] Streamed final answer monitor follow-up '
              'requested tool calls',
            );
            await _executeToolCalls(
              backgroundProcessRepairResult.toolCalls!,
              assistantContent: backgroundProcessRepairResult.content.isNotEmpty
                  ? backgroundProcessRepairResult.content
                  : streamedFinalAnswer,
              toolSearchEnabled: toolSearchEnabled,
              selectedToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              completionVerificationFailureCounts: verificationFailureCounts,
              narratedTranscriptRepairSignatures: transcriptRepairSignatures,
              verifierOnlyContinuation: verifierOnlyContinuation,
              interactionGeneration: interactionGeneration,
            );
            return;
          }

          final monitorResponse = backgroundProcessRepairResult.content.trim();
          _recordHiddenEvidence(turnOwner, monitorResponse);
          final monitorFollowUp =
              BackgroundProcessFollowUpPolicy.followUpToolCall(
                executedToolResults,
                waitMs: BackgroundProcessFollowUpPolicy.waitMsForIteration(
                  budget.limit,
                ),
              );
          if (monitorFollowUp != null) {
            appLog(
              '[BackgroundProcess] Streamed final answer monitor prose '
              'response forced follow-up process check',
            );
            await _executeToolCalls(
              [monitorFollowUp],
              assistantContent: monitorResponse.isNotEmpty
                  ? monitorResponse
                  : streamedFinalAnswer,
              toolSearchEnabled: toolSearchEnabled,
              selectedToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              completionVerificationFailureCounts: verificationFailureCounts,
              narratedTranscriptRepairSignatures: transcriptRepairSignatures,
              verifierOnlyContinuation: verifierOnlyContinuation,
              interactionGeneration: interactionGeneration,
            );
            return;
          }

          if (monitorResponse.isNotEmpty) {
            acceptAnswer(monitorResponse);
          }
        }
        final verificationRepairResult =
            await _requestCodingVerificationRepairForCompletionClaim(
              candidateResponse: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              retainedEvidenceToolResults: finalToolResults,
              attemptedMutationSignatures:
                  attemptedCompletionVerificationMutationSignatures,
              verificationFailureCounts: verificationFailureCounts,
              tools: tools,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (verificationRepairResult != null) {
          if (verificationRepairResult.hasToolCalls) {
            appLog(
              '[CodingVerification] Streamed final answer repair requested '
              'tool calls',
            );
            await _executeToolCalls(
              verificationRepairResult.toolCalls!,
              assistantContent: verificationRepairResult.content.isNotEmpty
                  ? verificationRepairResult.content
                  : streamedFinalAnswer,
              toolSearchEnabled: toolSearchEnabled,
              selectedToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              completionVerificationFailureCounts: verificationFailureCounts,
              narratedTranscriptRepairSignatures: transcriptRepairSignatures,
              verifierOnlyContinuation: verifierOnlyContinuation,
              interactionGeneration: interactionGeneration,
            );
            return;
          }

          final verificationResponse = verificationRepairResult.content.trim();
          if (verificationResponse.isNotEmpty) {
            _appendRecoveredAssistantResponse(
              verificationResponse,
              interactionGeneration: interactionGeneration,
            );
          }
        }
        final handledByReleaseRetry =
            await _applyBlockedProductionReleaseRetryToStreamedFinalAnswer(
              streamedFinalAnswer: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              tools: tools,
              toolSearchEnabled: toolSearchEnabled,
              activeToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              verificationFailureCounts: verificationFailureCounts,
              transcriptRepairSignatures: transcriptRepairSignatures,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (handledByReleaseRetry) return;
        final handledByTranscriptRepair =
            await _applyNarratedTranscriptRepairToStreamedFinalAnswer(
              streamedFinalAnswer: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              attemptedSignatures: transcriptRepairSignatures,
              tools: tools,
              toolSearchEnabled: toolSearchEnabled,
              activeToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              verificationFailureCounts: verificationFailureCounts,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (handledByTranscriptRepair) return;
        if (const FencedToolArgumentsDetector().detect(streamedFinalAnswer) !=
            null) {
          final handledByFencedRetry =
              await _applyUnexecutedCommandActionRetryToStreamedFinalAnswer(
                streamedFinalAnswer: streamedFinalAnswer,
                executedToolResults: finalToolResults,
                batchToolResults: streamVerificationBatchToolResults,
                allowedToolNames: turnSnapshot.allowedToolNames,
                tools: tools,
                toolSearchEnabled: toolSearchEnabled,
                activeToolNames: activeToolNames,
                stableToolDefinitions: stableToolDefinitions,
                verificationFailureCounts: verificationFailureCounts,
                transcriptRepairSignatures: transcriptRepairSignatures,
                interactionGeneration: interactionGeneration,
                onBlockingFeedbackPrepared: () =>
                    _removeStreamedAnswerSuffixForGeneration(
                      interactionGeneration,
                      preAnswerContent: preFinalAnswerContent,
                    ),
              );
          if (handledByFencedRetry) return;
        }
        final unexecutedCommandAction =
            _toolCallExecutionPolicy.offersCommandExecution(
              turnSnapshot.allowedToolNames,
            )
            ? _claims.buildUnexecutedCommandActionToolResult(
                candidateResponse: streamedFinalAnswer,
                toolResults: finalToolResults,
                isProjectSubtask: _primaryRoutes.isProjectTaskStep(
                  interactionGeneration,
                ),
              )
            : null;
        if (unexecutedCommandAction != null) {
          finalToolResults.add(unexecutedCommandAction);
          finalCompletionEvidenceIsCurrent = false;
          final handledByCommandRetry =
              await _applyUnexecutedCommandActionRetryToStreamedFinalAnswer(
                streamedFinalAnswer: streamedFinalAnswer,
                executedToolResults: finalToolResults,
                batchToolResults: streamVerificationBatchToolResults,
                allowedToolNames: turnSnapshot.allowedToolNames,
                tools: tools,
                toolSearchEnabled: toolSearchEnabled,
                activeToolNames: activeToolNames,
                stableToolDefinitions: stableToolDefinitions,
                verificationFailureCounts: verificationFailureCounts,
                transcriptRepairSignatures: transcriptRepairSignatures,
                interactionGeneration: interactionGeneration,
                onBlockingFeedbackPrepared: () =>
                    _removeStreamedAnswerSuffixForGeneration(
                      interactionGeneration,
                      preAnswerContent: preFinalAnswerContent,
                    ),
              );
          if (handledByCommandRetry) return;
          _appendUnexecutedCommandActionNoticeIfNeeded(
            toolResults: finalToolResults,
            owner: turnOwner,
          );
        } else {
          final unverifiedInspectionClaim = _guardReviewInspection(
            candidateResponse: streamedFinalAnswer,
            toolResults: finalToolResults,
            generation: interactionGeneration,
          );
          if (unverifiedInspectionClaim != null) {
            finalToolResults.add(unverifiedInspectionClaim);
            finalCompletionEvidenceIsCurrent = false;
            _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded(
              toolResults: finalToolResults,
              owner: turnOwner,
            );
          }
        }
        // A review ending at the loop limit answers here (session ca60617b).
        _captureProjectTaskReviewResponse(
          owner: turnOwner,
          response: streamedFinalAnswer,
          finishReason: _responseMetadata.finishReasonFor(turnOwner) ?? '',
          results: finalToolResults,
        );
      }
    } else if (!hasTextResponse) {
      appLog('[Tool] Tool loop reached maximum iterations (no text response)');
      // The helper already skips a turn with no message of its own; the
      // removed `state.messages` guard read whichever thread was on screen.
      _appendToLastMessageForGeneration(
        interactionGeneration,
        '\nSorry, there was a problem executing the tools. Please try again later.',
      );
    }

    if (!finalCompletionEvidenceIsCurrent) {
      finalCompletionEvidence = ToolResultPromptBuilder.completionEvidence(
        finalToolResults,
      );
      finalCompletionEvidence = _goalCompletionEvidence
          .settleSuccessfulSavedValidation(
            finalCompletionEvidence,
            conversation: _conversationForGeneration(interactionGeneration),
            succeeded: savedValidationSucceededInLoop,
          );
    }
    finalCompletionEvidence = _goalCompletionEvidence
        .replaceWithCombinedEvidence(turnOwner, finalCompletionEvidence);
    final postMutationVerifierReplay = _takePostMutationVerifierReplay(
      evidence: finalCompletionEvidence,
      interactionGeneration: interactionGeneration,
    );
    if (postMutationVerifierReplay != null) {
      appLog(
        '[CodingVerification] Replaying the last executed verifier after '
        'a later mutation',
      );
      await _executeToolCalls(
        [postMutationVerifierReplay],
        assistantContent:
            'The implementation changed after its last verification. '
            'Re-running the same verifier now.',
        toolSearchEnabled: toolSearchEnabled,
        selectedToolNames: activeToolNames,
        stableToolDefinitions: stableToolDefinitions,
        completionVerificationFailureCounts: verificationFailureCounts,
        narratedTranscriptRepairSignatures: transcriptRepairSignatures,
        verifierOnlyContinuation: verifierOnlyContinuation,
        interactionGeneration: interactionGeneration,
      );
      return;
    }
    await _recordSuccessfulVerificationGenerationIfNeeded(
      finalCompletionEvidence,
      owner: turnOwner,
    );
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    _turnToolResults.setCompleted(turnOwner, finalToolResults);
    await _finishStreaming(interactionGeneration: interactionGeneration);
  }
}
