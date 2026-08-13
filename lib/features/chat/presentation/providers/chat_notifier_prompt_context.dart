// Same-library extension on [ChatNotifier]; Riverpod marks `ref` as
// `@protected`, which is not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

final Expando<ExecutionSnapshotObserver<LlmSessionLogContext>>
_executionSnapshotObservers =
    Expando<ExecutionSnapshotObserver<LlmSessionLogContext>>();

extension ChatNotifierPromptContext on ChatNotifier {
  ExecutionSnapshotObserver<LlmSessionLogContext>
  get _executionSnapshotObserver => _executionSnapshotObservers[this] ??=
      ExecutionSnapshotObserver<LlmSessionLogContext>(
        logPort: LlmSessionExecutionShadowLogPort(
          ref.read(llmSessionLogStoreProvider),
        ),
        diagnosticLog: appLog,
      );

  Message _createSystemMessage({
    List<String>? toolNamesOverride,
    String? participantRolePrompt,
    required Conversation? conversation,
    TurnOwnerSnapshot? ownerSnapshot,
  }) {
    final now = DateTime.now();
    final currentConversation = conversation;
    final activeCodingProject = currentConversation == null
        ? null
        : _codingProjectForTurn(currentConversation);
    final projectRoot = ownerSnapshot == null
        ? activeCodingProject?.rootPath
        : ownerSnapshot.projectRoot;
    final toolNames = toolNamesOverride == null
        ? <String>[]
        : List<String>.from(toolNamesOverride);
    final mcpToolService = _mcpToolService;
    final toolObservation = const RequestToolObservationCollector().collect(
      RequestToolObservationInput(
        catalog: mcpToolService == null
            ? null
            : RequestToolCatalogSnapshot(
                connectionStatus: mcpToolService.status,
                toolDefinitions: mcpToolService.getOpenAiToolDefinitions(),
                externalToolDescriptors: mcpToolService.tools
                    .map((tool) => tool.toOpenAiTool())
                    .toList(growable: false),
              ),
        hasToolNamesOverride: toolNamesOverride != null,
        effectiveToolNames: toolNames,
        mcpEnabled: _settings.mcpEnabled,
        hasTemporalReferenceContext: _temporalReferenceContext != null,
      ),
    );
    final resolvedLanguage = _settings.language == 'system'
        ? _languageCode
        : _settings.language;
    final resolvedAssistantMode = ownerSnapshot == null
        ? _resolveAssistantMode(currentConversation: currentConversation)
        : ownerSnapshot.isPlanning
        ? AssistantMode.plan
        : ownerSnapshot.isCodingWorkspaceOrMode
        ? AssistantMode.coding
        : AssistantMode.general;
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
    _observeExecutionSnapshot(
      currentConversation,
      executionSnapshot,
      ownerSnapshot,
    );
    final content = SystemPromptBuilder.build(
      now: now,
      assistantMode: resolvedAssistantMode,
      languageCode: resolvedLanguage,
      toolNames: toolNames,
      sessionMemoryContext: _sessionMemoryContext,
      participantRolePrompt: participantRolePrompt,
      projectName: activeCodingProject?.name,
      projectRootPath: projectRoot,
      repoMapContext: _repoMap(
        resolvedAssistantMode,
        projectRoot,
        ownerSnapshot?.owner.interactionGeneration,
      ),
      goal: currentConversation?.goal,
      workflowStage:
          currentConversation?.workflowStage ?? ConversationWorkflowStage.idle,
      workflowSpec: currentConversation?.workflowSpec,
      planArtifact: currentConversation?.planArtifact,
      executionSnapshot: executionSnapshot,
      isVoiceMode: _isVoiceMode,
      agentsMarkdown: _loadAgentsMd(resolvedAssistantMode, projectRoot),
      skillsContext: _buildSkillsPromptContext(toolNames),
      hasPythonInputAttachment:
          toolNames.contains('run_python_script') &&
          (ownerSnapshot?.hasAttachments ?? false),
      modelCapabilityProfile: _primaryCapabilityProfileForGeneration(
        ownerSnapshot?.owner.interactionGeneration,
      ),
      modelHarnessConfig: _primaryHarnessConfigForGeneration(
        ownerSnapshot?.owner.interactionGeneration,
      ),
    );
    // Only a registered turn has an owner. Fabricating one from the visible
    // conversation used generation 0, which ChatTurnOwner rejects outright, so
    // every prompt built outside a registered turn — plan drafting above all —
    // threw instead of skipping an observation it has nothing to attribute.
    final observationOwner = ownerSnapshot?.owner;
    if (observationOwner != null) {
      _updateContextSurgeryObservation(
        owner: observationOwner,
        systemPrompt: content,
        toolDefinitions: toolObservation.definitions,
        mcpToolNames: toolObservation.mcpNames,
      );
    }
    return Message(
      id: 'system',
      content: content,
      role: MessageRole.system,
      timestamp: now,
    );
  }

  Future<void> _ensureShortPromptExecutionContract({
    required String? projectRoot,
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
      specification: _loadReferencedSpecification(
        userMessage.content,
        projectRoot,
      ),
    );
    if (workflowSpec == null) return;
    try {
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: currentConversation.isPlanningSession
            ? ConversationWorkflowStage.plan
            : ConversationWorkflowStage.implement,
        workflowSpec: workflowSpec,
        conversationId: currentConversation.id,
      );
    } catch (error) {
      appLog(
        '[ExecutionContract] Failed to persist short-prompt contract: $error',
      );
    }
  }

  Future<void> _markPendingExecutionTaskStarted({
    required Conversation? conversation,
    required ConversationsNotifier conversationsNotifier,
    required bool bypassPlanMode,
    required int interactionGeneration,
  }) async {
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
        conversationId: conversation.id,
      );
      _runtimeEvents.emitRuntimeWorkflowTransition(
        generation: interactionGeneration,
        stage: 'implement',
        taskId: task.id,
        taskStatus: ConversationWorkflowTaskStatus.inProgress.name,
      );
    } catch (error) {
      appLog('[ExecutionProgress] Failed to persist task start: $error');
    }
  }

  SpecificationContractInput? _loadReferencedSpecification(
    String request,
    String? projectRoot,
  ) => const ReferencedSpecificationLoader().load(
    projectRoot: projectRoot ?? '',
    request: request,
  );

  void _observeExecutionSnapshot(
    Conversation? conversation,
    ExecutionSnapshot snapshot,
    TurnOwnerSnapshot? ownerSnapshot,
  ) {
    if (conversation == null) return;
    final context = ownerSnapshot?.owner.conversationId == conversation.id
        ? ownerSnapshot!.sessionLogContext
        : _buildLlmSessionLogContext(targetConversationId: conversation.id);
    unawaited(
      _executionSnapshotObserver.observe(
        ExecutionSnapshotObservation(
          conversationId: conversation.id,
          workspaceMode: conversation.workspaceMode,
          snapshot: snapshot,
          loggingEnabled: LlmSessionLogStore.isEnabled(
            settingsEnabled: _settings.enableLlmSessionLogs,
          ),
          logContext: context,
          timestamp: DateTime.now(),
        ),
      ),
    );
  }

  CodingProject? _codingProjectForTurn(Conversation? conversation) =>
      _codingProjects.forConversation(conversation);

  /// An empty registered root blocks the visible-project fallback.
  TurnProjectRoot? _turnProjectRootFor(int? generation) {
    if (generation == null) return null;
    return TurnProjectRoot(_projectRootForGeneration(generation) ?? '');
  }

  String? _projectRootForGeneration(int generation) =>
      _turnOwnerSnapshotForGeneration(generation)?.projectRoot;

  String? _loadAgentsMd(AssistantMode assistantMode, String? projectRoot) {
    if (!_settings.enableAgentsMd || assistantMode == AssistantMode.general) {
      return null;
    }
    return ref.read(agentsMdLoaderProvider).loadForProject(projectRoot);
  }

  String? _repoMap(
    AssistantMode assistantMode,
    String? projectRoot,
    int? interactionGeneration,
  ) {
    if (assistantMode == AssistantMode.general) return null;
    final lspSymbolEntries = ref
        .read(repoMapLspSymbolCacheProvider)
        .entriesForRoot(projectRoot);
    // LL22: serve from the precompute cache when the project signature is
    // unchanged; otherwise this rebuilds and stores it (a cold first turn).
    return ref
        .read(repoMapPrecomputeCacheProvider)
        .getOrBuild(
          rootPath: projectRoot,
          usableContextTokens: _primaryCapabilityProfileForGeneration(
            interactionGeneration,
          )?.usableContextTokens,
          lspSymbolEntries: lspSymbolEntries,
        );
  }
}
