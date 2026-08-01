import 'dart:async';
import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import '../entities/tool_call_info.dart';
import 'subagent_tool_contract.dart';

// ChatNotifier decomposition collaborator: subagent-tool-handler

final class SubagentToolHandler {
  SubagentToolHandler({
    required SubagentTaskStorePort taskStore,
    required SubagentExecutionPort executionPort,
    required ChildToolExecutionPort childToolExecutionPort,
    required SubagentNotificationPort notificationPort,
    required SubagentOwnerLifecyclePort ownerLifecyclePort,
    required SubagentToolCatalogPort toolCatalogPort,
    required String Function() taskIdFactory,
    DateTime Function()? clock,
  }) : _taskStore = taskStore,
       _executionPort = executionPort,
       _childToolExecutionPort = childToolExecutionPort,
       _notificationPort = notificationPort,
       _ownerLifecyclePort = ownerLifecyclePort,
       _toolCatalogPort = toolCatalogPort,
       _taskIdFactory = taskIdFactory,
       _clock = clock ?? DateTime.now;

  static const String _identityMismatch =
      'Subagent execution returned a mismatched task identity';
  static const String _nestedDenial =
      'Nested subagents are not allowed. Finish this sub-task directly.';
  static const String _expired =
      'Subagent execution was cancelled because its exact owner expired';
  static const String _uncertain =
      'Subagent execution outcome is uncertain; inspect possible child-tool '
      'side effects before retrying';

  final SubagentTaskStorePort _taskStore;
  final SubagentExecutionPort _executionPort;
  final ChildToolExecutionPort _childToolExecutionPort;
  final SubagentNotificationPort _notificationPort;
  final SubagentOwnerLifecyclePort _ownerLifecyclePort;
  final SubagentToolCatalogPort _toolCatalogPort;
  final String Function() _taskIdFactory;
  final DateTime Function() _clock;

  Future<McpToolResult> handle(SubagentToolRequest request) async {
    return switch (request.toolName) {
      spawnSubagentToolName => await _handleSpawn(request),
      getSubagentResultToolName => _handleGetResult(request),
      _ => throw StateError('Subagent request validation was bypassed.'),
    };
  }

  Future<McpToolResult> _handleSpawn(SubagentToolRequest request) async {
    final description = _trimString(request.arguments, 'description');
    final prompt = _trimString(request.arguments, 'prompt');
    if (prompt.isEmpty) {
      return _failure(request.toolName, 'prompt is required');
    }
    final label = description.isEmpty ? 'Subagent task' : description;
    final tools = List<Map<String, dynamic>>.unmodifiable(
      _toolCatalogPort
          .filterInherited(request.parentToolDefinitions)
          .map(freezeSubagentMap),
    );
    final allowlist = Set<String>.unmodifiable(
      tools.map(_toolCatalogPort.toolName).where((name) => name.isNotEmpty),
    );
    final identity = SubagentTaskIdentity(
      owner: request.owner,
      parentToolCallId: request.toolCallId,
      taskId: _taskIdFactory(),
    );
    if (!_ownerLifecyclePort.isCurrent(identity)) {
      return _spawnFailure(request.toolName, identity, label, _expired);
    }
    final execution = SubagentExecutionRequest(
      identity: identity,
      description: label,
      prompt: prompt,
      tools: tools,
      allowedToolNames: allowlist,
      isBackground: request.arguments['background'] == true,
    );
    if (execution.isBackground) {
      return _startBackground(request.toolName, execution);
    }

    final completion = await _run(execution);
    if (completion.identity != identity ||
        !_matches(completion.task, identity)) {
      return _spawnFailure(
        request.toolName,
        identity,
        label,
        _identityMismatch,
      );
    }
    if (!_ownerLifecyclePort.isCurrent(identity)) {
      return _spawnFailure(request.toolName, identity, label, _uncertain);
    }
    final task = completion.task;
    if (task.status == SubagentTaskStatus.completed) {
      return McpToolResult(
        toolName: request.toolName,
        result: jsonEncode({
          'status': 'completed',
          'task_id': task.id,
          'description': task.description,
          'summary': task.resultSummary,
        }),
        isSuccess: true,
      );
    }
    return _spawnFailure(
      request.toolName,
      identity,
      task.description,
      task.error ?? 'Subagent failed',
    );
  }

  McpToolResult _startBackground(
    String toolName,
    SubagentExecutionRequest execution,
  ) {
    final identity = execution.identity;
    if (!_ownerLifecyclePort.isCurrent(identity)) {
      return _spawnFailure(toolName, identity, execution.description, _expired);
    }
    final receipt = _taskStore.register(
      identity,
      SubagentTask(
        id: identity.taskId,
        conversationId: identity.owner.conversationId,
        interactionGeneration: identity.owner.interactionGeneration,
        status: SubagentTaskStatus.running,
        description: execution.description,
        prompt: execution.prompt,
        parentToolUseId: identity.parentToolCallId,
        isBackground: true,
        startedAt: _clock(),
      ),
    );
    if (!receipt.accepts(identity)) {
      final error =
          receipt.identity != identity ||
              receipt.disposition ==
                  SubagentTransitionDisposition.effectUncertain
          ? _uncertain
          : 'Subagent task registration failed';
      return _spawnFailure(toolName, identity, execution.description, error);
    }
    unawaited(_runBackground(execution));
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'status': 'started',
        'task_id': identity.taskId,
        'description': execution.description,
        'note':
            'The subagent is running in the background. Call '
            'get_subagent_result with this task_id to retrieve the result '
            'once it finishes.',
      }),
      isSuccess: true,
    );
  }

  Future<void> _runBackground(SubagentExecutionRequest execution) async {
    final identity = execution.identity;
    SubagentExecutionCompletion completion;
    try {
      completion = await _run(execution);
    } catch (error) {
      await _settleFailure(identity, error.toString());
      return;
    }
    if (!_ownerLifecyclePort.isCurrent(identity)) return;
    final snapshot = _taskStore.lookupExact(identity);
    if (!_isActiveSnapshot(snapshot, identity)) return;

    if (completion.identity != identity ||
        !_matches(completion.task, identity)) {
      await _settleFailure(identity, _identityMismatch);
      return;
    }
    final task = completion.task;
    final receipt = task.status == SubagentTaskStatus.completed
        ? _taskStore.complete(
            identity,
            output: task.output,
            summary: task.resultSummary,
          )
        : _taskStore.fail(identity, task.error ?? 'Subagent failed');
    if (receipt.accepts(identity) && _ownerLifecyclePort.isCurrent(identity)) {
      await _notifyDone(identity);
    } else if (receipt.disposition ==
            SubagentTransitionDisposition.effectUncertain ||
        receipt.identity != identity) {
      await _settleFailure(identity, _uncertain);
    }
  }

  Future<void> _settleFailure(
    SubagentTaskIdentity identity,
    String error,
  ) async {
    if (!_ownerLifecyclePort.isCurrent(identity)) return;
    final snapshot = _taskStore.lookupExact(identity);
    if (!_isActiveSnapshot(snapshot, identity)) return;
    final receipt = _taskStore.fail(identity, error);
    if (receipt.accepts(identity) && _ownerLifecyclePort.isCurrent(identity)) {
      await _notifyDone(identity);
    }
  }

  Future<SubagentExecutionCompletion> _run(SubagentExecutionRequest request) {
    return _executionPort.run(
      request,
      dispatchToolCall: (toolCall) =>
          _dispatchChild(request.identity, toolCall, request.allowedToolNames),
    );
  }

  Future<McpToolResult> _dispatchChild(
    SubagentTaskIdentity identity,
    ToolCallInfo toolCall,
    Set<String> allowlist,
  ) async {
    if (toolCall.name == spawnSubagentToolName ||
        toolCall.name == getSubagentResultToolName) {
      return _failure(toolCall.name, _nestedDenial);
    }
    if (!allowlist.contains(toolCall.name)) {
      return _failure(
        toolCall.name,
        'Tool ${toolCall.name} is not available to this subagent.',
      );
    }
    if (!_ownerLifecyclePort.isCurrent(identity)) {
      return _failure(toolCall.name, _expired);
    }
    final childRequest = ChildToolExecutionRequest(
      taskIdentity: identity,
      id: toolCall.id,
      name: toolCall.name,
      arguments: toolCall.arguments,
      allowedToolNames: allowlist,
    );
    try {
      final completion = await _childToolExecutionPort.execute(childRequest);
      if (!_sameChildRequest(completion.request, childRequest) ||
          !_ownerLifecyclePort.isCurrent(identity)) {
        return _failure(toolCall.name, _uncertain);
      }
      return completion.result;
    } catch (_) {
      if (!_ownerLifecyclePort.isCurrent(identity)) {
        return _failure(toolCall.name, _uncertain);
      }
      rethrow;
    }
  }

  Future<void> _notifyDone(SubagentTaskIdentity identity) async {
    if (!_ownerLifecyclePort.isCurrent(identity)) return;
    final snapshot = _taskStore.lookupExact(identity);
    if (!_isSnapshot(snapshot, identity)) return;
    final task = snapshot!.task;
    if (task.notified || !task.isTerminal) return;
    final succeeded = task.status == SubagentTaskStatus.completed;
    final rawBody = succeeded
        ? (task.resultSummary.isEmpty ? 'Completed.' : task.resultSummary)
        : (task.error ?? 'Subagent failed.');
    final body = rawBody.length > 200
        ? '${rawBody.substring(0, 200)}...'
        : rawBody;
    try {
      final receipt = await _notificationPort.notify(
        identity,
        SubagentCompletionNotification(
          taskId: task.id,
          description: task.description,
          isSuccessful: succeeded,
          body: body,
        ),
      );
      if (receipt.accepts(identity) &&
          _ownerLifecyclePort.isCurrent(identity)) {
        _taskStore.markNotified(identity);
      }
    } catch (_) {
      // A failed notification remains unacknowledged so a later retry is safe.
    }
  }

  McpToolResult _handleGetResult(SubagentToolRequest request) {
    final taskId = _trimString(request.arguments, 'task_id');
    if (taskId.isEmpty) {
      return _failure(request.toolName, 'task_id is required');
    }
    final lookup = SubagentResultLookup(
      invocation: request.invocation,
      taskId: taskId,
    );
    if (!_ownerLifecyclePort.isLookupCurrent(lookup)) {
      return _failure(request.toolName, _expired);
    }
    final snapshot = _taskStore.lookupResult(lookup);
    if (!_matchesLookup(snapshot, lookup)) {
      return McpToolResult(
        toolName: request.toolName,
        result: jsonEncode({'status': 'not_found', 'task_id': taskId}),
        isSuccess: false,
        errorMessage: 'No subagent task with id $taskId',
      );
    }
    final task = snapshot!.task;
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
      toolName: request.toolName,
      result: jsonEncode(payload),
      isSuccess: task.status != SubagentTaskStatus.failed,
    );
  }

  bool _matches(SubagentTask task, SubagentTaskIdentity identity) {
    return task.id == identity.taskId &&
        task.isOwnedBy(identity.owner) &&
        task.parentToolUseId == identity.parentToolCallId;
  }

  bool _isSnapshot(
    SubagentTaskSnapshot? snapshot,
    SubagentTaskIdentity identity,
  ) =>
      snapshot != null &&
      snapshot.identity == identity &&
      _matches(snapshot.task, identity);

  bool _isActiveSnapshot(
    SubagentTaskSnapshot? snapshot,
    SubagentTaskIdentity identity,
  ) => _isSnapshot(snapshot, identity) && snapshot!.task.isActive;

  bool _matchesLookup(
    SubagentResultSnapshot? snapshot,
    SubagentResultLookup lookup,
  ) {
    if (snapshot == null ||
        snapshot.lookup.invocation.owner != lookup.invocation.owner ||
        snapshot.lookup.invocation.toolCallId != lookup.invocation.toolCallId ||
        snapshot.lookup.invocation.toolName != lookup.invocation.toolName ||
        snapshot.lookup.taskId != lookup.taskId) {
      return false;
    }
    return snapshot.taskIdentity.owner == lookup.invocation.owner &&
        snapshot.taskIdentity.taskId == lookup.taskId &&
        _matches(snapshot.task, snapshot.taskIdentity);
  }

  bool _sameChildRequest(
    ChildToolExecutionRequest actual,
    ChildToolExecutionRequest expected,
  ) {
    return actual.taskIdentity == expected.taskIdentity &&
        actual.id == expected.id &&
        actual.name == expected.name &&
        identical(actual.arguments, expected.arguments) &&
        identical(actual.allowedToolNames, expected.allowedToolNames);
  }

  McpToolResult _spawnFailure(
    String toolName,
    SubagentTaskIdentity identity,
    String description,
    String error,
  ) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'status': 'failed',
        'task_id': identity.taskId,
        'description': description,
        'error': error,
      }),
      isSuccess: false,
      errorMessage: error,
    );
  }

  McpToolResult _failure(String toolName, String error) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: error,
    );
  }
}

String _trimString(Map<String, dynamic> arguments, String key) {
  return (arguments[key] as String?)?.trim() ?? '';
}
