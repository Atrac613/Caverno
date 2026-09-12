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
    final task = ref
        .read(subagentTaskNotifierProvider.notifier)
        .byId(owner, taskId);
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
}
