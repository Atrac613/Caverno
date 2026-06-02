// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// Handler for the `spawn_subagent` delegation tool.
///
/// A subagent runs its own tool-calling loop via [SubagentExecutionService]
/// (which reuses `RoutineToolRunner`) using the parent's inherited tools minus
/// `spawn_subagent` itself. The parent's [_dispatchToolCall] is injected so the
/// child shares the parent's tool execution and user-approval escalation.
extension ChatNotifierSubagentHandlers on ChatNotifier {
  Future<McpToolResult> _handleSpawnSubagent(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    // Depth guard: a subagent must never spawn another subagent. The child's
    // tool list already excludes spawn_subagent, but a model could still emit a
    // content-embedded call, so enforce delegation depth here as well.
    if (_subagentDepth > 0) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage:
            'Nested subagents are not allowed. Finish the current sub-task '
            'directly instead of spawning another subagent.',
      );
    }

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

    final toolService = _mcpToolService;
    final inheritedTools = toolService == null
        ? const <Map<String, dynamic>>[]
        : SubagentToolPolicy.filterInheritedToolDefinitions(
            toolService.getOpenAiToolDefinitions(),
          );

    final taskId = _uuid.v4();
    appLog('[Subagent] Spawning "$label" (task=$taskId)');

    final service = SubagentExecutionService(dataSource: _dataSource);
    _subagentDepth += 1;
    SubagentTask task;
    try {
      task = await service.run(
        id: taskId,
        description: label,
        prompt: prompt,
        parentToolUseId: toolCall.id,
        tools: inheritedTools,
        dispatchToolCall: (childToolCall) => _dispatchToolCall(
          childToolCall,
          interactionGeneration: interactionGeneration,
        ),
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );
    } finally {
      _subagentDepth -= 1;
    }

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
}
