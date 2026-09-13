// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierSubagentHandlers on ChatNotifier {
  Future<McpToolResult> _handleSpawnSubagent(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final owner = interactionGeneration == null
        ? null
        : _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final description = trimStringArgument(toolCall.arguments, 'description');
    var prompt = trimStringArgument(toolCall.arguments, 'prompt');
    if (prompt.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'prompt is required',
      );
    }
    final admission = AnabasisDelegationAdmission.prepare(
      toolCall,
      isParent: _anabasisRoles.isParentTurn(interactionGeneration!),
      conversation: _conversationForId(owner.conversationId),
      prompt: prompt,
    );
    if (admission.refusal != null) return admission.refusal!;
    prompt = admission.prompt;
    final workflowTaskId = admission.workflowTaskId;
    final label = description.isEmpty ? 'Subagent task' : description;
    final background = toolCall.arguments['background'] == true;

    final toolService = _mcpToolService;
    final inheritedTools = toolService == null
        ? const <Map<String, dynamic>>[]
        : SubagentToolPolicy.filterInheritedToolDefinitions(
            toolService.getOpenAiToolDefinitions(),
          );

    if (trimStringArgument(toolCall.arguments, 'runner') == 'worktree') {
      return _delegateToWorktree(
        toolCall: toolCall,
        owner: owner,
        prompt: prompt,
        label: label,
        workflowTaskId: workflowTaskId,
        interactionGeneration: interactionGeneration,
      );
    }

    final taskId = _uuid.v4();

    if (background) {
      return _startBackgroundSubagent(
        owner: owner,
        taskId: taskId,
        label: label,
        prompt: prompt,
        workflowTaskId: workflowTaskId,
        parentToolUseId: toolCall.id,
        toolName: toolCall.name,
        inheritedTools: inheritedTools,
        interactionGeneration: interactionGeneration,
      );
    }

    appLog('[Subagent] Spawning "$label" (task=$taskId)');
    final observation = SubagentCommandObservation();
    final task = await _runSubagent(
      owner: owner,
      taskId: taskId,
      label: label,
      prompt: prompt,
      workflowTaskId: workflowTaskId,
      parentToolUseId: toolCall.id,
      inheritedTools: inheritedTools,
      interactionGeneration: interactionGeneration,
      isBackground: false,
      onChildResult: observation.observe,
    );

    // The acceptance audit reads this notifier to find the child it must judge,
    // and only the background path was registering. So a foreground delegation
    // -- the parent's ordinary route -- could only ever be refused as
    // acceptance_no_delegated_result.
    ref.read(subagentTaskNotifierProvider.notifier).register(owner, task);

    if (task.status == SubagentTaskStatus.completed) {
      appLog('[Subagent] Completed "$label" (task=$taskId)');
      return observation.completed(toolCall.name, task);
    }

    appLog('[Subagent] Failed "$label" (task=$taskId): ${task.error}');
    return SubagentCommandObservation.failed(toolCall.name, task);
  }

  /// Hands planned work to a worktree child: its own branch, its own checkout.
  ///
  /// The evidenced kind of delegation, and the reason ANA3's acceptance can
  /// stand on more than the parent's word: a worktree child reports changed
  /// files and the result of the saved validation command, where a subagent
  /// child has neither and leaves both audit levels inapplicable.
  ///
  /// Requires the plan binding. Without a saved task there is no validation
  /// command to run and nothing to audit the branch against, so the route is
  /// refused rather than quietly downgraded -- a silent fall back to a subagent
  /// would return a summary the parent would read as evidence.
  Future<McpToolResult> _delegateToWorktree({
    required ToolCallInfo toolCall,
    required ChatTurnOwner owner,
    required String prompt,
    required String label,
    required String workflowTaskId,
    required int interactionGeneration,
  }) async {
    const payloads = SubagentResultPayloads();
    final conversation = _conversationForId(owner.conversationId);
    final task = conversation?.effectiveWorkflowSpec.tasks
        .where((candidate) => candidate.id == workflowTaskId)
        .firstOrNull;
    final projectRoot = _projectRootForGeneration(interactionGeneration) ?? '';
    if (task == null || projectRoot.isEmpty) {
      return payloads.worktreeUnavailable(
        toolName: toolCall.name,
        reason: task == null
            ? 'A worktree child runs against a saved task; none was bound.'
            : 'A worktree child needs a coding project root; this turn has none.',
        requiredAction: task == null
            ? 'Pass a ready workflow_task_id, or delegate to a subagent.'
            : 'Open the project in coding mode, or delegate to a subagent.',
      );
    }
    final inFlight = _worktreeChildrenOrNone()
        .where(
          (candidate) =>
              candidate.workflowTaskId == workflowTaskId && !candidate.isTerminal,
        )
        .lastOrNull;
    if (inFlight != null) {
      return payloads.worktreeAlreadyRunning(
        toolName: toolCall.name,
        taskId: inFlight.id,
        workflowTaskId: workflowTaskId,
        branchName: inFlight.branchName,
      );
    }
    try {
      final launched = await ref
          .read(worktreeAgentTaskLauncherProvider)
          .enqueue(
            WorktreeAgentTaskLaunchRequest(
              title: label,
              prompt: prompt,
              projectRootPath: projectRoot,
              verificationCommand: task.validationCommand,
              expectedTargetFiles: task.targetFiles,
              objectiveAcceptanceCriteria:
                  conversation!.effectiveWorkflowSpec.acceptanceCriteria,
              workflowTaskId: workflowTaskId,
            ),
          );
      appLog(
        '[Subagent] Enqueued worktree child for $workflowTaskId '
        '(task=${launched.task.id} branch=${launched.task.branchName})',
      );
      // Started here, because nothing else would. Only a slash command with
      // --run drives the scheduler, so a parent that merely enqueued would hand
      // itself an id to poll on a child that never starts -- delegation with no
      // effect, which is the one thing the parent's only route to effect cannot
      // be. Fire-and-forget, like the slash command: the run outlives this tool
      // call by design, and the parent polls it.
      unawaited(
        ref
            .read(worktreeAgentTaskOrchestratorProvider)
            .startAndExecuteReady(
              WorktreeAgentTaskRunRequest(fallbackProjectRootPath: projectRoot),
            ),
      );
      return payloads.worktreeEnqueued(
        toolName: toolCall.name,
        taskId: launched.task.id,
        workflowTaskId: workflowTaskId,
        branchName: launched.task.branchName,
        worktreePath: launched.task.normalizedWorktreePath,
        verificationCommand: launched.task.verificationCommand,
      );
    } catch (error) {
      // The launcher throws for a reason the parent can act on -- no project
      // root, unreadable git reservations -- so it is reported rather than
      // swallowed into a generic failure.
      return payloads.worktreeUnavailable(
        toolName: toolCall.name,
        reason: '$error',
        requiredAction:
            'Fix the project or branch state, or delegate to a subagent.',
      );
    }
  }

  Future<McpToolResult> _startBackgroundSubagent({
    required ChatTurnOwner owner,
    required String taskId,
    required String label,
    required String prompt,
    required String parentToolUseId,
    required String toolName,
    String workflowTaskId = '',
    required List<Map<String, dynamic>> inheritedTools,
    int? interactionGeneration,
  }) async {
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    notifier.register(
      owner,
      SubagentTask(
        id: taskId,
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration,
        status: SubagentTaskStatus.running,
        description: label,
        prompt: prompt,
        workflowTaskId: workflowTaskId,
        parentToolUseId: parentToolUseId,
        isBackground: true,
        startedAt: DateTime.now(),
      ),
    );
    appLog('[Subagent] Spawning background "$label" (task=$taskId)');

    // Fire-and-forget: run asynchronously and update the notifier on finish.
    unawaited(
      _runBackgroundSubagent(
        owner: owner,
        taskId: taskId,
        label: label,
        prompt: prompt,
        workflowTaskId: workflowTaskId,
        parentToolUseId: parentToolUseId,
        inheritedTools: inheritedTools,
        interactionGeneration: interactionGeneration,
      ),
    );

    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'status': 'started',
        'task_id': taskId,
        'description': label,
        'note':
            'The subagent is running in the background. Call '
            'get_subagent_result with this task_id to retrieve the result '
            'once it finishes.',
      }),
      isSuccess: true,
    );
  }

  Future<void> _runBackgroundSubagent({
    required ChatTurnOwner owner,
    required String taskId,
    required String label,
    required String prompt,
    required String parentToolUseId,
    String workflowTaskId = '',
    required List<Map<String, dynamic>> inheritedTools,
    int? interactionGeneration,
  }) async {
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    final task = await _runSubagent(
      owner: owner,
      taskId: taskId,
      label: label,
      prompt: prompt,
      workflowTaskId: workflowTaskId,
      parentToolUseId: parentToolUseId,
      inheritedTools: inheritedTools,
      interactionGeneration: interactionGeneration,
      isBackground: true,
    );

    // If the user cancelled while it was running, drop the result.
    final current = notifier.byId(owner, taskId);
    if (current == null || current.status == SubagentTaskStatus.cancelled) {
      return;
    }

    if (task.status == SubagentTaskStatus.completed) {
      appLog('[Subagent] Background completed "$label" (task=$taskId)');
      notifier.complete(
        owner,
        taskId,
        output: task.output,
        summary: task.resultSummary,
      );
    } else {
      appLog('[Subagent] Background failed "$label" (task=$taskId)');
      notifier.fail(owner, taskId, task.error ?? 'Subagent failed');
    }
    await _notifySubagentDone(owner, taskId);
  }

  Future<SubagentTask> _runSubagent({
    required ChatTurnOwner owner,
    required String taskId,
    required String label,
    required String prompt,
    required String parentToolUseId,
    String workflowTaskId = '',
    required List<Map<String, dynamic>> inheritedTools,
    required bool isBackground,
    void Function(ToolCallInfo, McpToolResult)? onChildResult,
    int? interactionGeneration,
  }) async {
    final resolved = _meshRunner.resolve(
      primary: _dataSource,
      primaryBaseUrl: _settings.baseUrl,
      primaryApiKey: _settings.apiKey,
      endpoints: _settings.enabledLlmEndpoints,
      endpointId: _settings.llmProvider == LlmProvider.openAiCompatible
          ? _settings.subagentEndpointId
          : '',
      model: _settings.effectiveSubagentModel,
      fallbackModel: _settings.model,
    );
    final service = SubagentExecutionService(dataSource: resolved.dataSource);
    final task = await service.run(
      owner: owner,
      id: taskId,
      description: label,
      prompt: prompt,
      parentToolUseId: parentToolUseId,
      tools: inheritedTools,
      dispatchToolCall: (childToolCall) async {
        final result = await _dispatchChildToolCall(
          childToolCall,
          interactionGeneration: interactionGeneration,
        );
        if (SubagentCommandObservation.changesWorkspace(
          childToolCall,
          result,
        )) {
          await ref
              .read(conversationsNotifierProvider.notifier)
              .recordMutationGeneration(conversationId: owner.conversationId);
        }
        onChildResult?.call(childToolCall, result);
        return result;
      },
      model: resolved.model,
      temperature: _agenticRequestTemperature,
      maxTokens: _settings.maxTokens,
      isBackground: isBackground,
    );
    if (!resolved.isPrimary) {
      if (task.status == SubagentTaskStatus.failed) {
        _meshRunner.health.recordFailure(resolved.endpointId);
      } else {
        _meshRunner.health.recordSuccess(resolved.endpointId);
      }
    }
    // Stamped here rather than passed into the runner: the runner is shared
    // with paths that know nothing about saved plans, and the binding is the
    // delegation gate's fact, not the runner's.
    return workflowTaskId.isEmpty
        ? task
        : task.copyWith(workflowTaskId: workflowTaskId);
  }

  /// Dispatch wrapper for a child subagent: blocks the delegation tools so a
  /// child can never spawn another subagent or query task results, keeping
  /// delegation depth at 1 regardless of how the call was emitted.
  Future<McpToolResult> _dispatchChildToolCall(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) {
    if (SubagentToolPolicy.blockedTools.contains(toolCall.name)) {
      return Future<McpToolResult>.value(
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage:
              'Nested subagents and parent goal updates are not allowed. Return your result.',
        ),
      );
    }
    return _dispatchToolCall(
      toolCall,
      interactionGeneration: interactionGeneration,
    );
  }

  Future<void> _notifySubagentDone(ChatTurnOwner owner, String taskId) async {
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    final task = notifier.byId(owner, taskId);
    if (task == null || task.notified) {
      return;
    }
    final notification = SubagentCompletionNotification.forTask(task);
    try {
      await ref
          .read(notificationServiceProvider)
          .showSubagentCompletionNotification(
            taskId: notification.taskId,
            description: notification.description,
            isSuccessful: notification.isSuccessful,
            body: notification.body,
          );
    } catch (_) {
      // Notifications are best-effort; never fail the run on a notify error.
    }
    notifier.markNotified(owner, taskId);
  }

  Future<McpToolResult> _handleGetSubagentResult(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final owner = interactionGeneration == null
        ? null
        : _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    const payloads = SubagentResultPayloads();
    final taskId = trimStringArgument(toolCall.arguments, 'task_id');
    if (taskId.isEmpty) return payloads.missingTaskId(toolCall.name);
    // Conversation-scoped, like the acceptance audit below, and for the same
    // reason. `byId` matches the turn owner, so a child spawned in an earlier
    // turn read back as not_found -- measured: the parent asked for the result
    // it was told to judge, was told there was none, and re-delegated the task
    // instead. A delegated result has to outlive the turn that asked for it.
    final children = ref
        .read(subagentTaskNotifierProvider)
        .tasksForConversation(owner.conversationId);
    final task = children
        .where((candidate) => candidate.id == taskId)
        .lastOrNull;
    if (task != null) {
      return payloads.forTask(toolName: toolCall.name, task: task);
    }
    // Worktree children are looked up by id alone, because that is all they
    // carry: they are scoped to a coding project rather than a conversation, and
    // the id is the one the enqueue answer handed the parent.
    final worktrees = _worktreeChildrenOrNone();
    final worktree = worktrees
        .where((candidate) => candidate.id == taskId)
        .lastOrNull;
    if (worktree != null) {
      return payloads.forWorktreeTask(toolName: toolCall.name, task: worktree);
    }
    return payloads.unknownTask(
      toolName: toolCall.name,
      taskId: taskId,
      knownTaskIds: [
        for (final candidate in children) candidate.id,
        for (final candidate in worktrees)
          if (candidate.workflowTaskId.trim().isNotEmpty) candidate.id,
      ],
    );
  }

  List<WorktreeAgentTask> _worktreeChildrenOrNone() =>
      _acceptance.worktreeChildrenOrNone();

  /// Records the parent's acceptance of a delegated saved task.
  ///
  /// Refuses rather than judges. `mayParentAccept` decides, on evidence the
  /// runners already recorded, and a refusal names what is still outstanding so
  /// the parent can go and verify it. The rationale is stored as written.
  Future<McpToolResult> _handleAcceptTask(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final owner = interactionGeneration == null
        ? null
        : _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    const decisions = TaskAcceptanceDecisionService();
    final decision = decisions.decide(
      toolName: toolCall.name,
      isParentTurn: _anabasisRoles.isParentTurn(interactionGeneration!),
      conversation: _conversationForId(owner.conversationId),
      taskId: trimStringArgument(toolCall.arguments, 'workflow_task_id'),
      rationale: trimStringArgument(toolCall.arguments, 'rationale'),
      childrenForConversation: ref
          .read(subagentTaskNotifierProvider)
          .tasksForConversation(owner.conversationId),
      worktreeChildren: _worktreeChildrenOrNone(),
    );
    switch (decision) {
      case TaskAcceptanceRefusal(:final result):
        return result;
      case TaskAcceptanceContract():
        final wrote = await ref
            .read(conversationsNotifierProvider.notifier)
            .recordTaskAcceptance(
              taskId: decision.task.id,
              rationale: trimStringArgument(toolCall.arguments, 'rationale'),
              evidence: decision.evidence,
              premises: decision.premises,
              conversationId: owner.conversationId,
            );
        if (!wrote) return decisions.writeFailed(toolCall.name);
        appLog('[Anabasis] Accepted saved task ${decision.task.id}');
        return decisions.accepted(toolCall.name, decision);
    }
  }
}
