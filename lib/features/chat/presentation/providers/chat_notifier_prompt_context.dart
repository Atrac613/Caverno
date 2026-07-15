// Same-library extension on [ChatNotifier]; Riverpod marks `ref` as
// `@protected`, which is not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

extension ChatNotifierPromptContext on ChatNotifier {
  Message _createSystemMessage({
    List<String>? toolNamesOverride,
    String? participantRolePrompt,
  }) {
    final now = DateTime.now();
    final activeCodingProject = _getEffectiveCodingProject();
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final toolNames = toolNamesOverride == null
        ? <String>[]
        : List<String>.from(toolNamesOverride);
    final toolObservation = _collectRequestToolObservation(
      toolNamesOverride: toolNamesOverride,
      toolNames: toolNames,
    );
    final resolvedLanguage = _settings.language == 'system'
        ? _languageCode
        : _settings.language;
    final resolvedAssistantMode = _resolveAssistantMode(
      currentConversation: currentConversation,
    );
    final projectedExecutionSnapshot = const ExecutionSnapshotProjector()
        .project(currentConversation);
    final commandDiagnosticRepairFocus = _commandDiagnosticRepairFocusFor(
      currentConversation,
    );
    final executionSnapshot = commandDiagnosticRepairFocus == null
        ? projectedExecutionSnapshot
        : projectedExecutionSnapshot.withCommandDiagnosticRepairFocus(
            diagnosticSummary: commandDiagnosticRepairFocus.diagnosticSummary,
            streak: commandDiagnosticRepairFocus.streak,
            hasPathBackedDiagnostic:
                commandDiagnosticRepairFocus.hasPathBackedDiagnostic,
          );
    _observeExecutionSnapshot(currentConversation, executionSnapshot);
    final content = SystemPromptBuilder.build(
      now: now,
      assistantMode: resolvedAssistantMode,
      languageCode: resolvedLanguage,
      toolNames: toolNames,
      sessionMemoryContext: _sessionMemoryContext,
      participantRolePrompt: participantRolePrompt,
      projectName: activeCodingProject?.name,
      projectRootPath: activeCodingProject?.rootPath,
      repoMapContext: _repoMap(resolvedAssistantMode, activeCodingProject),
      goal: currentConversation?.goal,
      workflowStage:
          currentConversation?.workflowStage ?? ConversationWorkflowStage.idle,
      workflowSpec: currentConversation?.workflowSpec,
      planArtifact: currentConversation?.planArtifact,
      executionSnapshot: executionSnapshot,
      isVoiceMode: _isVoiceMode,
      agentsMarkdown: _loadAgentsMd(resolvedAssistantMode, activeCodingProject),
      skillsContext: _buildSkillsPromptContext(toolNames),
      hasPythonInputAttachment:
          toolNames.contains('run_python_script') &&
          _latestPythonInputMessage() != null,
      modelCapabilityProfile: _settings.effectiveModelCapabilityProfile,
      modelHarnessConfig: _settings.effectiveModelHarnessConfig,
    );
    _updateContextSurgeryObservation(
      systemPrompt: content,
      toolDefinitions: toolObservation.definitions,
      mcpToolNames: toolObservation.mcpNames,
    );
    return Message(
      id: 'system',
      content: content,
      role: MessageRole.system,
      timestamp: now,
    );
  }

  Future<void> _ensureShortPromptExecutionContract({
    required Conversation? currentConversation,
    required Message userMessage,
    required ConversationsNotifier conversationsNotifier,
  }) async {
    final isActiveAutoGoal =
        (currentConversation?.goal?.isActive ?? false) &&
        (currentConversation?.goal?.autoContinue ?? false);
    if (currentConversation?.workspaceMode != WorkspaceMode.coding ||
        (!(currentConversation?.isPlanningSession ?? false) &&
            !isActiveAutoGoal) ||
        currentConversation!.effectiveWorkflowSpec.hasContent) {
      return;
    }
    final workflowSpec = const ShortPromptContractBuilder().build(
      userMessageId: userMessage.id,
      userRequest: userMessage.content,
      specification: _loadReferencedSpecification(userMessage.content),
    );
    if (workflowSpec == null) return;
    try {
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: currentConversation.isPlanningSession
            ? ConversationWorkflowStage.plan
            : ConversationWorkflowStage.implement,
        workflowSpec: workflowSpec,
      );
    } catch (error) {
      appLog(
        '[ExecutionContract] Failed to persist short-prompt contract: $error',
      );
    }
  }

  Future<void> _markPendingExecutionTaskStarted({
    required ConversationsNotifier conversationsNotifier,
    required bool bypassPlanMode,
  }) async {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding ||
        (conversation.isPlanningSession && !bypassPlanMode)) {
      return;
    }
    final task = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    if (task == null || task.status != ConversationWorkflowTaskStatus.pending) {
      return;
    }

    final startedAt = DateTime.now();
    try {
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.inProgress,
        lastRunAt: startedAt,
        eventType: ConversationExecutionTaskEventType.started,
        eventTimestamp: startedAt,
      );
      _emitRuntimeWorkflowTransition(
        stage: 'implement',
        taskId: task.id,
        taskStatus: ConversationWorkflowTaskStatus.inProgress.name,
      );
    } catch (error) {
      appLog('[ExecutionProgress] Failed to persist task start: $error');
    }
  }

  SpecificationContractInput? _loadReferencedSpecification(String request) {
    final projectRoot = _getEffectiveCodingProject()?.rootPath.trim() ?? '';
    if (projectRoot.isEmpty) return null;
    final match = RegExp(
      r'''(?:^|[\s"'`(])([^\s"'`()]+\.md)\b''',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(request);
    final reference = match?.group(1)?.trim() ?? '';
    if (reference.isEmpty) return null;
    final normalizedRoot = Uri.file(
      Directory(projectRoot).absolute.path,
    ).normalizePath().toFilePath();
    final candidate = Uri.file(
      File('$normalizedRoot${Platform.pathSeparator}$reference').absolute.path,
    ).normalizePath().toFilePath();
    if (!candidate.startsWith('$normalizedRoot${Platform.pathSeparator}')) {
      return null;
    }
    final file = File(candidate);
    if (!file.existsSync() || file.lengthSync() > 256 * 1024) return null;
    try {
      return SpecificationContractInput(
        path: reference,
        content: file.readAsStringSync(),
      );
    } on FileSystemException {
      return null;
    }
  }

  void _observeExecutionSnapshot(
    Conversation? conversation,
    ExecutionSnapshot snapshot,
  ) {
    if (conversation?.workspaceMode != WorkspaceMode.coding) {
      return;
    }
    final observationKey = '${conversation?.id}|${snapshot.observationKey}';
    if (_latestExecutionSnapshotObservationKey == observationKey) {
      return;
    }
    _latestExecutionSnapshotObservationKey = observationKey;
    appLog('[ExecutionShadow] ${snapshot.toRedactedLogSummary()}');
    if (!LlmSessionLogStore.isEnabled(
      settingsEnabled: _settings.enableLlmSessionLogs,
    )) {
      return;
    }
    unawaited(
      ref
          .read(llmSessionLogStoreProvider)
          .recordExecutionShadow(
            context: _currentLlmSessionLogContext(),
            at: DateTime.now(),
            contractHash: snapshot.contractHash,
            workflowStage: snapshot.workflowStage.name,
            action: snapshot.action.name,
            activeTaskRef: snapshot.activeTaskRef,
            taskStatus: snapshot.activeTaskStatus?.name,
            validationStatus: snapshot.validationStatus.name,
            completedTaskCount: snapshot.completedTaskCount,
            totalTaskCount:
                snapshot.completedTaskCount + snapshot.remainingTaskCount,
            unresolvedQuestionCount: snapshot.unresolvedQuestionCount,
            requiresValidation: snapshot.requiresValidation,
            hasDiagnostic: snapshot.latestDiagnostic != null,
          ),
    );
  }

  CodingProject? _getEffectiveCodingProject() {
    final project = _getActiveCodingProject();
    if (project == null) {
      return null;
    }
    final worktreePath = ref
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.normalizedWorktreePath;
    if (worktreePath == null || worktreePath.isEmpty) {
      return project;
    }
    return project.copyWith(rootPath: worktreePath);
  }

  String? _loadAgentsMd(AssistantMode assistantMode, CodingProject? project) {
    if (!_settings.enableAgentsMd || assistantMode == AssistantMode.general) {
      return null;
    }
    return ref.read(agentsMdLoaderProvider).loadForProject(project?.rootPath);
  }

  String? _repoMap(AssistantMode assistantMode, CodingProject? project) {
    if (assistantMode == AssistantMode.general) return null;
    final lspSymbolEntries = ref
        .read(repoMapLspSymbolCacheProvider)
        .entriesForRoot(project?.rootPath);
    // LL22: serve from the precompute cache when the project signature is
    // unchanged; otherwise this rebuilds and stores it (a cold first turn).
    return ref
        .read(repoMapPrecomputeCacheProvider)
        .getOrBuild(
          rootPath: project?.rootPath,
          usableContextTokens:
              _settings.effectiveModelCapabilityProfile?.usableContextTokens,
          lspSymbolEntries: lspSymbolEntries,
        );
  }
}
