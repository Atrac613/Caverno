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
    final isSuccess = task.status == SubagentTaskStatus.completed;
    final rawBody = isSuccess
        ? (task.resultSummary.isEmpty ? 'Completed.' : task.resultSummary)
        : (task.error ?? 'Subagent failed.');
    final body = rawBody.length > 200
        ? '${rawBody.substring(0, 200)}...'
        : rawBody;
    try {
      await ref
          .read(notificationServiceProvider)
          .showSubagentCompletionNotification(
            taskId: task.id,
            description: task.description,
            isSuccessful: isSuccess,
            body: body,
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
    final taskId = trimStringArgument(toolCall.arguments, 'task_id');
    if (taskId.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'task_id is required',
      );
    }
    // Conversation-scoped, like the acceptance audit two methods down, and for
    // the same reason. `byId` matches the turn owner, so a child spawned in an
    // earlier turn read back as not_found -- measured: the parent asked for the
    // result it was told to judge, was told there was none, and re-delegated
    // the task instead. A delegated result has to outlive the turn that asked
    // for it; the conversation boundary is the one that matters.
    final task = ref
        .read(subagentTaskNotifierProvider)
        .tasksForConversation(owner.conversationId)
        .where((candidate) => candidate.id == taskId)
        .lastOrNull;
    if (task == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({'status': 'not_found', 'task_id': taskId}),
        isSuccess: false,
        errorMessage: 'No subagent task with id $taskId',
      );
    }

    final payload = <String, dynamic>{
      'task_id': task.id,
      'description': task.description,
      'status': task.status.name,
    };
    if (task.status == SubagentTaskStatus.completed) {
      payload['summary'] = task.resultSummary;
    } else if (task.status == SubagentTaskStatus.failed) {
      payload['error'] = task.error ?? 'Subagent failed';
    } else if (task.isActive) {
      payload['note'] = 'Still running. Check again shortly.';
    }

    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode(payload),
      isSuccess: task.status != SubagentTaskStatus.failed,
    );
  }

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
    McpToolResult refuse(String code, Map<String, Object?> detail) =>
        McpToolResult(
          toolName: toolCall.name,
          isSuccess: false,
          result: jsonEncode({
            'ok': false,
            'code': code,
            'result_origin': 'refusal',
            ...detail,
          }),
        );

    // A producer must not grade its own work. The child catalog already omits
    // this tool; this is the same rule at dispatch, for a model that
    // rediscovers the name through tool search.
    if (!_anabasisRoles.isParentTurn(interactionGeneration!)) {
      return refuse('acceptance_not_parent', {
        'required_action':
            'Only Anabasis accepts a result. Report what you produced and let '
            'the parent judge it.',
      });
    }

    final taskId = trimStringArgument(toolCall.arguments, 'workflow_task_id');
    final rationale = trimStringArgument(toolCall.arguments, 'rationale');
    final conversation = _conversationForId(owner.conversationId);
    final spec = conversation?.effectiveWorkflowSpec;
    final task = spec?.tasks
        .where((candidate) => candidate.id == taskId)
        .firstOrNull;
    if (conversation == null || spec == null || task == null) {
      return refuse('acceptance_unknown_task', {
        'known_task_ids': spec == null
            ? const <String>[]
            : spec.tasks.map((candidate) => candidate.id).toList(),
        'required_action':
            'Pass an exact workflow_task_id from the saved plan.',
      });
    }
    if (rationale.isEmpty) {
      return refuse('acceptance_rationale_missing', {
        'required_action':
            'Say why this satisfies the goal. An acceptance without a reason '
            'records nothing the next turn can act on.',
      });
    }

    // Audited against the child that was admitted for this task, which is why
    // the delegation gate records the binding: without it there is no way to
    // tell which result is the one being accepted.
    final children = ref
        .read(subagentTaskNotifierProvider)
        .tasksForConversation(owner.conversationId)
        .where((candidate) => candidate.workflowTaskId == taskId)
        .toList(growable: false);
    if (children.isEmpty) {
      return refuse('acceptance_no_delegated_result', {
        'required_action':
            'Delegate this task and verify the result before accepting it. '
            'There is nothing recorded to accept on.',
      });
    }

    // Subagent results only, and deliberately so for now: ANA2 PR 2's worktree
    // mapping is not dispatched yet, so no WorktreeAgentTask exists to audit.
    // `auditWorktreeResult` is the other half and is already written -- when
    // worktree delegation is wired, this is the line that has to choose between
    // them, or a worktree child's result refuses as
    // `acceptance_no_delegated_result` despite being the more evidenced kind.
    const audit = TaskAcceptanceAudit();
    final verdict = audit.auditSubagentResult(children.last);
    if (!audit.mayParentAccept(verdict)) {
      return refuse('acceptance_levels_outstanding', {
        'outstanding': verdict.outstanding
            .map((level) => level.name)
            .toList(growable: false),
        'required_action':
            'Verify what is outstanding before accepting. A rationale cannot '
            'stand in for a check that did not run.',
      });
    }

    final premises = const TaskDelegationBriefBuilder().premisesFor(spec, task);
    final progress = conversation.executionProgressForTask(task.id);
    final evidence = <String>[
      if (progress?.lastValidationCommand.trim().isNotEmpty ?? false)
        progress!.lastValidationCommand.trim(),
      if (children.last.resultSummary.trim().isNotEmpty)
        'child summary recorded',
    ];
    final wrote = await ref
        .read(conversationsNotifierProvider.notifier)
        .recordTaskAcceptance(
          taskId: task.id,
          rationale: rationale,
          evidence: evidence,
          premises: premises,
          conversationId: owner.conversationId,
        );
    if (!wrote) {
      return refuse('acceptance_write_failed', {
        'required_action': 'The conversation could not be updated; retry once.',
      });
    }
    appLog('[Anabasis] Accepted saved task $taskId');
    return McpToolResult(
      toolName: toolCall.name,
      isSuccess: true,
      result: jsonEncode({
        'ok': true,
        'accepted_task_id': task.id,
        'evidence': evidence,
        'premises': premises,
      }),
    );
  }
}
