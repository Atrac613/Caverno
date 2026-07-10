// Same-library extension on [ChatNotifier]: coding completion-verification
// feedback — building the verification tool result, progress/validation/counts
// summaries, mutation/failure signatures, and convergence-blocker logging.
// Pure relocation from chat_notifier.dart (F5), no behavior change.
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
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation?.workspaceMode != WorkspaceMode.coding ||
        (currentConversation?.isPlanningSession ?? false)) {
      return null;
    }
    final projectRoot = _getActiveProjectRootPath();
    if (projectRoot == null || projectRoot.isEmpty) {
      return null;
    }

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
      await _recordCodingVerificationValidationProgress(verification.snapshot);
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
    if (!_shouldVerifyCodingCompletionClaim(candidateResponse)) {
      return null;
    }
    final mutationSignature = _codingVerificationMutationSignature(
      executedToolResults,
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
    final failureSignature = _codingVerificationFailureSignature(feedback);
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
          content: _codingVerificationConvergenceBlocker(feedback),
          finishReason: 'stop',
        );
      }
    }

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
    CodingVerificationSnapshot? snapshot,
  ) async {
    if (snapshot == null) {
      return;
    }
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null || conversation.projectedExecutionTasks.isEmpty) {
      return;
    }
    final task =
        ConversationPlanExecutionCoordinator.validationTask(conversation) ??
        ConversationPlanExecutionCoordinator.executionFocusTask(conversation);
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
    final validationSummary = _codingVerificationValidationSummary(snapshot);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: status,
      allowStatusRegression: true,
      validationStatus: snapshot.validationStatus,
      lastValidationAt: DateTime.now(),
      lastValidationCommand: _codingVerificationCommandSummary(snapshot),
      lastValidationSummary: validationSummary,
      summary: _codingVerificationProgressSummary(snapshot),
      blockedReason:
          snapshot.validationStatus ==
              ConversationExecutionValidationStatus.failed
          ? validationSummary
          : '',
      eventType: ConversationExecutionTaskEventType.validated,
      eventSummary: validationSummary,
    );

    if (!conversation.shouldPreferPlanDocument) {
      return;
    }
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowStage.review
          : ConversationWorkflowStage.implement,
      preserveWorkflowProjection: true,
    );
  }

  String _codingVerificationCommandSummary(
    CodingVerificationSnapshot snapshot,
  ) {
    final command = snapshot.selectedAttempt?.command;
    if (command != null) {
      return [command.executable, ...command.arguments].join(' ');
    }
    final targets = snapshot.targetBatches
        .expand((batch) => batch.targets)
        .toList(growable: false);
    if (targets.isEmpty) {
      return 'coding verification';
    }
    return 'coding verification ${targets.join(' ')}';
  }

  String _codingVerificationProgressSummary(
    CodingVerificationSnapshot snapshot,
  ) {
    final counts = _codingVerificationCountsSummary(snapshot);
    final suffix = counts.isEmpty ? '' : ' ($counts)';
    return switch (snapshot.validationStatus) {
      ConversationExecutionValidationStatus.passed =>
        'Coding verification passed$suffix.',
      ConversationExecutionValidationStatus.failed =>
        'Coding verification failed$suffix.',
      ConversationExecutionValidationStatus.unknown =>
        'Coding verification was inconclusive${snapshot.reason == null ? '' : ': ${snapshot.reason}'}$suffix.',
    };
  }

  String _codingVerificationValidationSummary(
    CodingVerificationSnapshot snapshot,
  ) {
    if (snapshot.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        snapshot.failures.isNotEmpty) {
      final failure = snapshot.failures.first;
      final locationParts = [
        failure.absolutePath == null
            ? null
            : DartProjectPath.relativePath(
                failure.absolutePath!,
                snapshot.projectRoot,
              ),
        if (failure.line != null) 'line ${failure.line}',
      ].whereType<String>().where((part) => part.trim().isNotEmpty);
      final location = locationParts.join(':');
      final label = [
        if (location.isNotEmpty) location,
        if (failure.testName.trim().isNotEmpty) failure.testName.trim(),
      ].join(' ');
      final message = failure.message.trim().isEmpty
          ? 'Test failed.'
          : failure.message.trim();
      return label.isEmpty ? message : '$label: $message';
    }
    return _codingVerificationProgressSummary(snapshot);
  }

  String _codingVerificationCountsSummary(CodingVerificationSnapshot snapshot) {
    final parts = <String>[
      if (snapshot.passedCount > 0) '${snapshot.passedCount} passed',
      if (snapshot.failedCount > 0) '${snapshot.failedCount} failed',
      if (snapshot.skippedCount > 0) '${snapshot.skippedCount} skipped',
    ];
    return parts.join(', ');
  }

  bool _shouldVerifyCodingCompletionClaim(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    final normalized = candidate.toLowerCase();
    if (normalized.contains('not complete') ||
        normalized.contains('not completed') ||
        normalized.contains('incomplete')) {
      return false;
    }
    return _hiddenAssistantEvidenceScore(candidate) >= 2 ||
        normalized.contains('done');
  }

  String? _codingVerificationMutationSignature(
    List<ToolResultInfo> toolResults,
  ) {
    final entries = <Map<String, String>>[];
    for (final toolResult in toolResults) {
      if (!_isFileMutationToolName(toolResult.name)) {
        continue;
      }
      if (!_isSuccessfulFileMutationToolResult(toolResult)) {
        continue;
      }
      final path =
          _toolResultPayloadPath(toolResult.result) ??
          _toolPathFromArguments(toolResult.arguments);
      if (path == null || !path.toLowerCase().endsWith('.dart')) {
        continue;
      }
      final resolved = FilesystemTools.resolvePath(
        path,
        defaultRoot: _getActiveProjectRootPath(),
      );
      entries.add({
        'id': toolResult.id,
        'name': toolResult.name,
        'path': resolved ?? path,
      });
    }
    if (entries.isEmpty) {
      return null;
    }
    return jsonEncode(entries);
  }

  String? _codingVerificationFailureSignature(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    if (decoded == null) {
      return null;
    }
    final failingTests = decoded['failing_tests'];
    if (failingTests is! List || failingTests.isEmpty) {
      return null;
    }
    final entries = <Map<String, Object?>>[];
    for (final test in failingTests) {
      if (test is! Map) {
        continue;
      }
      entries.add({
        'relative_path': test['relative_path'] ?? test['path'],
        'test_name': test['test_name'],
        'line': test['line'],
        'column': test['column'],
        'message': test['message'],
      });
    }
    if (entries.isEmpty) {
      return null;
    }
    return jsonEncode({
      'provider': decoded['provider'],
      'validation_status': decoded['validation_status'],
      'failures': entries,
    });
  }

  String _codingVerificationConvergenceBlocker(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    final failingTests = decoded?['failing_tests'];
    final buffer = StringBuffer(
      'The coding task is not complete. The same failing tests persisted after '
      '${ChatNotifier._maxRepeatedCodingVerificationRepairAttempts} repair attempts, so I am '
      'stopping the automatic repair loop.',
    );
    if (failingTests is List && failingTests.isNotEmpty) {
      buffer.writeln();
      buffer.writeln();
      buffer.writeln('Remaining failing tests:');
      for (final test in failingTests.take(5)) {
        if (test is! Map) {
          continue;
        }
        final path = test['relative_path'] ?? test['path'];
        final name = test['test_name'];
        final line = test['line'];
        final message = test['message'];
        final location = [
          if (path is String && path.isNotEmpty) path,
          if (line != null) 'line $line',
        ].join(':');
        final label = [
          if (location.isNotEmpty) location,
          if (name is String && name.isNotEmpty) name,
        ].join(' ');
        buffer.write('- ');
        if (label.isNotEmpty) {
          buffer.write(label);
          buffer.write(': ');
        }
        buffer.write(
          message is String && message.isNotEmpty ? message : 'Test failed.',
        );
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  void _logCodingVerificationFeedbackSummary(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    if (decoded == null) {
      return;
    }
    final telemetry = decoded['telemetry'];
    final telemetryMap = telemetry is Map<String, dynamic> ? telemetry : null;
    final counts = decoded['counts'];
    final countsMap = counts is Map<String, dynamic> ? counts : null;
    final summary = <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'trigger': decoded['trigger'],
      'validationStatus': decoded['validation_status'],
      'files': decoded['changed_paths'],
      if (countsMap != null) ...{
        'passedCount': countsMap['passed'],
        'failedCount': countsMap['failed'],
        'skippedCount': countsMap['skipped'],
      },
      if (telemetryMap != null) ...{
        'durationMs': telemetryMap['duration_ms'],
        'commandAttemptCount': telemetryMap['command_attempt_count'],
        'fallbackCommandCount': telemetryMap['fallback_command_count'],
        'timedOutCommandCount': telemetryMap['timed_out_command_count'],
        'startErrorCommandCount': telemetryMap['start_error_command_count'],
      },
    };
    appLog(
      '[CodingVerification] Test feedback summary: ${jsonEncode(summary)}',
    );
  }
}
