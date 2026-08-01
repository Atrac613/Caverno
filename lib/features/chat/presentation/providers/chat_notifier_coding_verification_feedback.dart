// Same-library extension on [ChatNotifier]: coding completion-verification
// feedback — running verification, persisting progress, mutation signatures,
// and adapting presentation telemetry to app logging.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierCodingVerificationFeedback on ChatNotifier {
  Future<CodingVerificationFeedbackRun?> _buildCodingVerificationFeedbackRun(
    List<ToolResultInfo> toolResults, {
    required int interactionGeneration,
    required CodingVerificationTrigger trigger,
  }) async {
    if (!_codingVerificationEnabledFor(trigger)) {
      return null;
    }
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    final turn = _codingTurnContext(interactionGeneration);
    if (turn == null) {
      return null;
    }
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return null;
    }
    final projectRoot = turn.projectRoot;

    final changedPaths = _changedFileMutationPaths(toolResults);
    if (changedPaths.isEmpty) {
      return null;
    }

    try {
      final verification = await _codingVerificationFeedbackService
          .buildFeedbackRun(
            projectRoot: projectRoot,
            changedPaths: changedPaths,
            trigger: trigger,
          );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return null;
      }
      await _recordCodingVerificationValidationProgress(
        verification.snapshot,
        owner: owner,
        ownerConversation: turn.conversation,
      );
      final feedback = verification.toolResult;
      if (feedback != null) {
        appLog(
          '[CodingVerification] Added test feedback for '
          '${changedPaths.length} changed file(s)',
        );
        _logCodingVerificationFeedbackSummary(feedback);
      }
      return verification;
    } catch (error, stackTrace) {
      appLog('[CodingVerification] Failed to collect test feedback: $error');
      appLog('[CodingVerification] stackTrace: $stackTrace');
      return null;
    }
  }

  Future<ChatCompletionResult?>
  _requestCodingVerificationRepairForCompletionClaim({
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required Set<String> attemptedMutationSignatures,
    required Map<String, int> verificationFailureCounts,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    List<ToolResultInfo>? retainedEvidenceToolResults,
    void Function()? onBlockingFeedbackPrepared,
  }) async {
    if (!_codingVerificationEnabledFor(
      CodingVerificationTrigger.completionClaim,
    )) {
      return null;
    }
    if (!CodingVerificationFeedbackPresentation.shouldVerifyCompletionClaim(
      candidateResponse,
    )) {
      return null;
    }
    final mutationSignature = _codingVerificationMutationSignature(
      executedToolResults,
      projectRoot: _projectRootForGeneration(interactionGeneration),
    );
    if (mutationSignature == null) {
      return null;
    }
    if (!attemptedMutationSignatures.add(mutationSignature)) {
      appLog(
        '[CodingVerification] Skipping duplicate completion verification '
        'for unchanged file mutations',
      );
      return null;
    }
    final verification = await _buildCodingVerificationFeedbackRun(
      executedToolResults,
      interactionGeneration: interactionGeneration,
      trigger: CodingVerificationTrigger.completionClaim,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    final evidence = verification?.evidenceToolResult;
    if (evidence != null) {
      executedToolResults.add(evidence);
      if (retainedEvidenceToolResults != null &&
          !identical(retainedEvidenceToolResults, executedToolResults)) {
        retainedEvidenceToolResults.add(evidence);
      }
      appLog(
        '[CodingVerification] Retained test evidence for final claim checks',
      );
    }
    final feedback = verification?.toolResult;
    if (feedback == null) {
      return null;
    }
    final failureSignature =
        CodingVerificationFeedbackPresentation.failureSignature(feedback);
    if (failureSignature != null) {
      final failureCount =
          (verificationFailureCounts[failureSignature] ?? 0) + 1;
      verificationFailureCounts[failureSignature] = failureCount;
      if (failureCount >
          ChatNotifier._maxRepeatedCodingVerificationRepairAttempts) {
        appLog(
          '[CodingVerification] Repeated failing test signature reached the '
          'repair limit; surfacing blocker',
        );
        return ChatCompletionResult(
          content: CodingVerificationFeedbackPresentation.convergenceBlocker(
            feedback,
            maxRepairAttempts:
                ChatNotifier._maxRepeatedCodingVerificationRepairAttempts,
          ),
          finishReason: 'stop',
        );
      }
    }

    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return null;
    }
    final promptFeedback = await _toolResultArtifactStore.persistIfLarge(
      feedback,
      conversationId: owner.conversationId,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) {
      return null;
    }
    batchToolResults.add(promptFeedback);
    executedToolResults.add(promptFeedback);
    onBlockingFeedbackPrepared?.call();

    appLog(
      '[CodingVerification] Completion claim blocked by failing tests; '
      'requesting repair',
    );
    _appendToLastMessageForGeneration(interactionGeneration, '<think>');
    try {
      return await _createToolResultCompletionWithContextRetry(
        logLabel: 'coding verification feedback',
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

  bool _codingVerificationEnabledFor(CodingVerificationTrigger trigger) {
    if (!_settings.enableCodingVerificationFeedback) {
      return false;
    }
    return switch (trigger) {
      CodingVerificationTrigger.completionClaim =>
        _settings.runsCodingVerificationOnCompletionClaim,
      CodingVerificationTrigger.explicitRequest =>
        _settings.codingVerificationTriggerPolicy !=
            CodingVerificationTriggerPolicy.off,
      CodingVerificationTrigger.quietPeriod =>
        _settings.codingVerificationTriggerPolicy ==
            CodingVerificationTriggerPolicy.onCompletionClaim,
    };
  }

  Future<void> _recordCodingVerificationValidationProgress(
    CodingVerificationSnapshot? snapshot, {
    required ChatTurnOwner owner,
    required Conversation ownerConversation,
  }) async {
    if (snapshot == null ||
        ownerConversation.id != owner.conversationId ||
        !_activeResponseRegistry.containsOwner(owner)) {
      return;
    }
    if (ownerConversation.projectedExecutionTasks.isEmpty) {
      return;
    }
    final task =
        ConversationPlanExecutionCoordinator.validationTask(
          ownerConversation,
        ) ??
        ConversationPlanExecutionCoordinator.executionFocusTask(
          ownerConversation,
        );
    if (task == null) {
      return;
    }

    final status = switch (snapshot.validationStatus) {
      ConversationExecutionValidationStatus.passed =>
        ConversationWorkflowTaskStatus.completed,
      ConversationExecutionValidationStatus.failed =>
        ConversationWorkflowTaskStatus.blocked,
      ConversationExecutionValidationStatus.unknown =>
        task.status == ConversationWorkflowTaskStatus.pending
            ? ConversationWorkflowTaskStatus.inProgress
            : task.status,
    };
    final validationSummary =
        CodingVerificationFeedbackPresentation.validationSummary(snapshot);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: status,
      allowStatusRegression: true,
      validationStatus: snapshot.validationStatus,
      lastValidationAt: DateTime.now(),
      lastValidationCommand:
          CodingVerificationFeedbackPresentation.commandSummary(snapshot),
      lastValidationSummary: validationSummary,
      summary: CodingVerificationFeedbackPresentation.progressSummary(snapshot),
      blockedReason:
          snapshot.validationStatus ==
              ConversationExecutionValidationStatus.failed
          ? validationSummary
          : '',
      eventType: ConversationExecutionTaskEventType.validated,
      eventSummary: validationSummary,
      conversationId: owner.conversationId,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) return;
    if (snapshot.validationStatus ==
        ConversationExecutionValidationStatus.passed) {
      try {
        await conversationsNotifier.recordVerificationGeneration(
          conversationId: owner.conversationId,
        );
      } catch (error) {
        appLog(
          '[ExecutionEvidence] Failed to persist successful verification '
          'generation: $error',
        );
      }
    }
    if (!_activeResponseRegistry.containsOwner(owner)) return;

    if (!ownerConversation.shouldPreferPlanDocument) {
      return;
    }
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowStage.review
          : ConversationWorkflowStage.implement,
      preserveWorkflowProjection: true,
      conversationId: owner.conversationId,
    );
  }

  String? _codingVerificationMutationSignature(
    List<ToolResultInfo> toolResults, {
    required String? projectRoot,
  }) {
    return const CodingVerificationMutationSignature().compute(
      CodingVerificationMutationSignatureInput(
        toolResults: toolResults,
        projectRoot: projectRoot,
      ),
    );
  }

  void _logCodingVerificationFeedbackSummary(ToolResultInfo feedback) {
    final summary = CodingVerificationFeedbackPresentation.telemetrySummary(
      feedback,
    );
    if (summary == null) {
      return;
    }
    appLog(
      '[CodingVerification] Test feedback summary: ${jsonEncode(summary)}',
    );
  }
}
