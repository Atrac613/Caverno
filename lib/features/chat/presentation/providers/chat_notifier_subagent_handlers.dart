// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// Handlers for subagent delegation tools (`spawn_subagent`,
/// `get_subagent_result`).
///
/// A subagent runs its own tool-calling loop via [SubagentExecutionService]
/// (which reuses `RoutineToolRunner`). Children are dispatched through
/// [_dispatchChildToolCall], which blocks the delegation tools so a child can
/// never spawn another subagent (delegation depth stays at 1). Foreground runs
/// return the summary inline; background runs register a task, run async, and
/// surface progress through [subagentTaskNotifierProvider] plus a completion
/// notification.
extension ChatNotifierSubagentHandlers on ChatNotifier {
  Future<McpToolResult> _handleSpawnSubagent(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final description = _trimStringArgument(toolCall.arguments, 'description');
    final prompt = _trimStringArgument(toolCall.arguments, 'prompt');
    if (prompt.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'prompt is required',
      );
    }
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
        taskId: taskId,
        label: label,
        prompt: prompt,
        parentToolUseId: toolCall.id,
        toolName: toolCall.name,
        inheritedTools: inheritedTools,
        interactionGeneration: interactionGeneration,
      );
    }

    appLog('[Subagent] Spawning "$label" (task=$taskId)');
    final task = await _runSubagent(
      taskId: taskId,
      label: label,
      prompt: prompt,
      parentToolUseId: toolCall.id,
      inheritedTools: inheritedTools,
      interactionGeneration: interactionGeneration,
      isBackground: false,
    );

    if (task.status == SubagentTaskStatus.completed) {
      appLog('[Subagent] Completed "$label" (task=$taskId)');
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'status': 'completed',
          'task_id': task.id,
          'description': task.description,
          'summary': task.resultSummary,
        }),
        isSuccess: true,
      );
    }

    appLog('[Subagent] Failed "$label" (task=$taskId): ${task.error}');
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'status': 'failed',
        'task_id': task.id,
        'description': task.description,
        'error': task.error ?? 'Subagent failed',
      }),
      isSuccess: false,
      errorMessage: task.error ?? 'Subagent failed',
    );
  }

  Future<McpToolResult> _startBackgroundSubagent({
    required String taskId,
    required String label,
    required String prompt,
    required String parentToolUseId,
    required String toolName,
    required List<Map<String, dynamic>> inheritedTools,
    int? interactionGeneration,
  }) async {
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    notifier.register(
      SubagentTask(
        id: taskId,
        status: SubagentTaskStatus.running,
        description: label,
        prompt: prompt,
        parentToolUseId: parentToolUseId,
        isBackground: true,
        startedAt: DateTime.now(),
      ),
    );
    appLog('[Subagent] Spawning background "$label" (task=$taskId)');

    // Fire-and-forget: run asynchronously and update the notifier on finish.
    unawaited(
      _runBackgroundSubagent(
        taskId: taskId,
        label: label,
        prompt: prompt,
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
    required String taskId,
    required String label,
    required String prompt,
    required String parentToolUseId,
    required List<Map<String, dynamic>> inheritedTools,
    int? interactionGeneration,
  }) async {
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    final task = await _runSubagent(
      taskId: taskId,
      label: label,
      prompt: prompt,
      parentToolUseId: parentToolUseId,
      inheritedTools: inheritedTools,
      interactionGeneration: interactionGeneration,
      isBackground: true,
    );

    // If the user cancelled while it was running, drop the result.
    final current = notifier.byId(taskId);
    if (current == null || current.status == SubagentTaskStatus.cancelled) {
      return;
    }

    if (task.status == SubagentTaskStatus.completed) {
      appLog('[Subagent] Background completed "$label" (task=$taskId)');
      notifier.complete(
        taskId,
        output: task.output,
        summary: task.resultSummary,
      );
    } else {
      appLog('[Subagent] Background failed "$label" (task=$taskId)');
      notifier.fail(taskId, task.error ?? 'Subagent failed');
    }
    await _notifySubagentDone(taskId);
  }

  Future<SubagentTask> _runSubagent({
    required String taskId,
    required String label,
    required String prompt,
    required String parentToolUseId,
    required List<Map<String, dynamic>> inheritedTools,
    required bool isBackground,
    int? interactionGeneration,
  }) {
    final service = SubagentExecutionService(dataSource: _dataSource);
    return service.run(
      id: taskId,
      description: label,
      prompt: prompt,
      parentToolUseId: parentToolUseId,
      tools: inheritedTools,
      dispatchToolCall: (childToolCall) => _dispatchChildToolCall(
        childToolCall,
        interactionGeneration: interactionGeneration,
      ),
      model: _settings.model,
      temperature: _settings.temperature,
      maxTokens: _settings.maxTokens,
      isBackground: isBackground,
    );
  }

  /// Dispatch wrapper for a child subagent: blocks the delegation tools so a
  /// child can never spawn another subagent or query task results, keeping
  /// delegation depth at 1 regardless of how the call was emitted.
  Future<McpToolResult> _dispatchChildToolCall(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) {
    if (toolCall.name == SubagentToolPolicy.spawnSubagentToolName ||
        toolCall.name == 'get_subagent_result') {
      return Future<McpToolResult>.value(
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage:
              'Nested subagents are not allowed. Finish this sub-task directly.',
        ),
      );
    }
    return _dispatchToolCall(
      toolCall,
      interactionGeneration: interactionGeneration,
    );
  }

  Future<void> _notifySubagentDone(String taskId) async {
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    final task = notifier.byId(taskId);
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
    notifier.markNotified(taskId);
  }

  Future<McpToolResult> _handleGetSubagentResult(ToolCallInfo toolCall) async {
    final taskId = _trimStringArgument(toolCall.arguments, 'task_id');
    if (taskId.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'task_id is required',
      );
    }
    final task = ref.read(subagentTaskNotifierProvider.notifier).byId(taskId);
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
