// Same-library extension on [ChatNotifier]; Riverpod marks `ref` as
// `@protected`, which is not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

final Expando<ExecutionSnapshotObserver<LlmSessionLogContext>>
_executionSnapshotObservers =
    Expando<ExecutionSnapshotObserver<LlmSessionLogContext>>();

extension ChatNotifierPromptContext on ChatNotifier {
  List<Message> _prepareMessagesForLLM({
    bool forceCompaction = false,
    List<Map<String, dynamic>>? toolDefinitionsOverride,
    required int interactionGeneration,
    String? participantRolePrompt,
  }) {
    // Before the snapshot is read, because committing is what puts an
    // interruption where that read finds it.
    _commitPendingTurnSteering(interactionGeneration);
    final ownerSnapshot = _turnOwnerSnapshotForGeneration(
      interactionGeneration,
    );
    if (ownerSnapshot == null) {
      throw StateError(
        'Turn owner snapshot unavailable: $interactionGeneration',
      );
    }
    final currentConversation = _conversationForId(
      ownerSnapshot.owner.conversationId,
    );
    final hiddenPrompt = ownerSnapshot.hiddenPrompt;
    final temporalReferenceContext = ownerSnapshot.temporalReferenceContext;
    final sourceMessages = _commitPhaseHistory(ownerSnapshot);
    final messages =
        ConversationPlanExecutionCoordinator.filterSupersededTaskExecutionTurns(
              messages: sourceMessages.where((message) => !message.isStreaming),
              currentExecutionPrompt: hiddenPrompt?.content,
            )
            .map(_messagePersistence.sanitizeMessageForModelHistory)
            .where(_messagePersistence.shouldKeepMessageForModelHistory)
            .toList();
    final modelSwitchHandoffBrief = _modelSwitchHandoffs.take(
      ownerSnapshot.owner,
    );
    final shouldForceCompaction = _modelSwitchHandoffs.consumePromptCompaction(
      owner: ownerSnapshot.owner,
      forceCompaction: forceCompaction,
      hasModelSwitchHandoff: modelSwitchHandoffBrief != null,
    );
    final promptMessages = <Message>[
      _createSystemMessage(
        conversation: currentConversation,
        ownerSnapshot: ownerSnapshot,
        participantRolePrompt: participantRolePrompt,
        toolNamesOverride: toolDefinitionsOverride == null
            ? null
            : ToolDefinitionSearchService.toolNamesFromDefinitions(
                toolDefinitionsOverride,
              ).toList(),
      ),
    ];
    if (temporalReferenceContext != null) {
      promptMessages.add(
        Message(
          id: 'system_temporal',
          content: temporalReferenceContext,
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ),
      );
    }
    final modelSwitchHandoffMessage = _hasCommitScope(interactionGeneration)
        ? null
        : _modelSwitchHandoffs.createPromptMessage(modelSwitchHandoffBrief);
    if (modelSwitchHandoffMessage != null) {
      promptMessages.add(modelSwitchHandoffMessage);
    }
    final promptBudget = _promptTokenBudget.budgetFor(
      _settings,
      ownerSnapshot.owner.conversationId,
    );
    final compactionArtifact = promptBudget.resolveArtifact(
      conversation: _hasCommitScope(interactionGeneration)
          ? null
          : currentConversation,
      messages: messages,
      forceCompaction: shouldForceCompaction,
    );
    if (compactionArtifact?.hasContent ?? false) {
      promptMessages.add(
        Message(
          id: 'system_compaction',
          content:
              'Earlier conversation summary for omitted turns:\n'
              '${compactionArtifact!.normalizedSummary!}\n\n'
              'Treat this summary as context for the trimmed transcript that follows.',
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ),
      );
    }
    final retainedMessages = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: compactionArtifact,
    );
    final result = [...promptMessages, ...retainedMessages];
    if (hiddenPrompt != null) {
      result.add(hiddenPrompt);
    }
    // Last, so an interruption is not read as one more remark filed behind the
    // work already in flight.
    final steeringDirective = _turnSteeringDirectiveMessage(
      ownerSnapshot.owner,
    );
    if (steeringDirective != null) {
      result.add(steeringDirective);
    }
    // Recorded before the pressure update overwrites it, so the pair handed to
    // the next turn describes this exact request.
    _promptTokenBudget.recordEstimate(ownerSnapshot.owner, result);
    _updateContextTokenPressureState(
      pressure: promptBudget.assess(result),
      compactionActive: compactionArtifact?.hasContent ?? false,
    );
    return result;
  }

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
    final currentConversation = conversation;
    // Native phase handoffs supersede older goal, workflow and memory instructions.
    final commitPhase =
        ownerSnapshot != null &&
        _hasCommitScope(ownerSnapshot.owner.interactionGeneration);
    // LL22: pinned per turn, because a per-request minute reading mutated one
    // line inside an otherwise byte-stable ~20k-token prefix and cost a full
    // reprefill. See [TurnPromptClock].
    final now = _turnPromptClock.pinFor(ownerSnapshot?.owner, DateTime.now());
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
    final capability = _primaryCapabilityProfileForGeneration(
      ownerSnapshot?.owner.interactionGeneration,
    );
    final projectContext = ref.read(projectPromptContextSourceProvider);
    final content = SystemPromptBuilder.build(
      now: now,
      assistantMode: resolvedAssistantMode,
      languageCode: resolvedLanguage,
      toolNames: toolNames,
      sessionMemoryContext: commitPhase ? null : _sessionMemoryContext,
      participantRolePrompt: participantRolePrompt,
      projectName: activeCodingProject?.name,
      projectRootPath: projectRoot,
      repoMapContext: projectContext.repoMap(
        resolvedAssistantMode,
        projectRoot,
        capability?.usableContextTokens,
      ),
      // KC2's environment block is withdrawn: its paired re-run regressed
      // class 4 to 100% stale (docs/knowledge_currency_track_design.md).
      goal: commitPhase ? null : currentConversation?.goal,
      workflowStage: commitPhase
          ? ConversationWorkflowStage.idle
          : currentConversation?.workflowStage ??
                ConversationWorkflowStage.idle,
      workflowSpec: commitPhase
          ? null
          : currentConversation?.projectedWorkflowSpec,
      planArtifact: commitPhase ? null : currentConversation?.planArtifact,
      executionSnapshot: commitPhase ? null : executionSnapshot,
      delegatedResults: commitPhase || currentConversation == null
          ? const <String>[]
          : const DelegatedResultDigest().summaries(
              children: ref
                  .read(subagentTaskNotifierProvider)
                  .tasksForConversation(currentConversation.id),
              worktreeChildren: _worktreeChildrenOrNone(),
              acceptedTaskIds: currentConversation.taskAcceptances
                  .map((acceptance) => acceptance.taskId)
                  .toSet(),
            ),
      isVoiceMode: _isVoiceMode,
      agentsMarkdown: _loadAgentsMd(resolvedAssistantMode, projectRoot),
      skillsContext: _buildSkillsPromptContext(toolNames),
      hasPythonInputAttachment:
          toolNames.contains('run_python_script') &&
          (ownerSnapshot?.hasAttachments ?? false),
      modelCapabilityProfile: capability,
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
    // A parent turn claims nothing: this mark is an ordinary coding turn saying
    // "I am working on this", and the parent is forbidden from working on it.
    // Claiming it anyway took the task out of `pending` -- the status
    // TaskDelegationBriefBuilder requires -- so the parent read an empty queue
    // in the turn that asked it to delegate, and the claimed task could never
    // return to `pending` with nothing executing it.
    if (_anabasisRoles.isParentTurn(interactionGeneration)) {
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
}
