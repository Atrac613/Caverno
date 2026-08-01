import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/subagent_task.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/subagent_tool_contract.dart';
import '../../domain/services/subagent_tool_handler.dart';

typedef SubagentTaskLookupCallback =
    SubagentTask? Function(ChatTurnOwner owner, String taskId);
typedef SubagentTaskRegisterCallback =
    bool Function(ChatTurnOwner owner, SubagentTask task);
typedef SubagentTaskCompleteCallback =
    bool Function(
      ChatTurnOwner owner,
      String taskId, {
      required String output,
      required String summary,
    });
typedef SubagentTaskFailCallback =
    bool Function(ChatTurnOwner owner, String taskId, String error);
typedef SubagentTaskMarkNotifiedCallback =
    bool Function(ChatTurnOwner owner, String taskId);
typedef SubagentTaskCurrentCallback =
    bool Function(SubagentTaskIdentity identity);
typedef SubagentLookupCurrentCallback =
    bool Function(SubagentResultLookup lookup);
typedef SubagentExecutionCallback =
    Future<SubagentTask> Function(
      SubagentExecutionRequest request, {
      required SubagentChildToolDispatcher dispatchToolCall,
    });
typedef SubagentChildExecutionCallback =
    Future<McpToolResult> Function(ChildToolExecutionRequest request);
typedef SubagentNotificationCallback =
    Future<void> Function(
      SubagentTaskIdentity identity,
      SubagentCompletionNotification notification,
    );
typedef SubagentToolFilterCallback =
    List<Map<String, dynamic>> Function(
      List<Map<String, dynamic>> parentDefinitions,
    );
typedef SubagentToolNameCallback = String Function(Map<String, dynamic> tool);

/// Production-facing adapter for the owner-aware subagent tool handler.
///
/// Callbacks keep Riverpod, LLM routing, notifications, and generic child-tool
/// execution outside the domain handler while preserving exact identities at
/// every port.
final class SubagentToolRuntimeAdapter {
  factory SubagentToolRuntimeAdapter({
    required SubagentTaskLookupCallback lookupTask,
    required SubagentTaskRegisterCallback registerTask,
    required SubagentTaskCompleteCallback completeTask,
    required SubagentTaskFailCallback failTask,
    required SubagentTaskMarkNotifiedCallback markTaskNotified,
    required SubagentTaskCurrentCallback isTaskCurrent,
    required SubagentLookupCurrentCallback isLookupCurrent,
    required SubagentExecutionCallback execute,
    required SubagentChildExecutionCallback executeChild,
    required SubagentNotificationCallback notify,
    required SubagentToolFilterCallback filterTools,
    required SubagentToolNameCallback toolName,
    required String Function() taskIdFactory,
    DateTime Function()? clock,
  }) {
    return SubagentToolRuntimeAdapter.withChildExecutionPort(
      lookupTask: lookupTask,
      registerTask: registerTask,
      completeTask: completeTask,
      failTask: failTask,
      markTaskNotified: markTaskNotified,
      isTaskCurrent: isTaskCurrent,
      isLookupCurrent: isLookupCurrent,
      execute: execute,
      childToolExecutionPort: CallbackChildToolExecutionPort(executeChild),
      notify: notify,
      filterTools: filterTools,
      toolName: toolName,
      taskIdFactory: taskIdFactory,
      clock: clock,
    );
  }

  SubagentToolRuntimeAdapter.withChildExecutionPort({
    required SubagentTaskLookupCallback lookupTask,
    required SubagentTaskRegisterCallback registerTask,
    required SubagentTaskCompleteCallback completeTask,
    required SubagentTaskFailCallback failTask,
    required SubagentTaskMarkNotifiedCallback markTaskNotified,
    required SubagentTaskCurrentCallback isTaskCurrent,
    required SubagentLookupCurrentCallback isLookupCurrent,
    required SubagentExecutionCallback execute,
    required ChildToolExecutionPort childToolExecutionPort,
    required SubagentNotificationCallback notify,
    required SubagentToolFilterCallback filterTools,
    required SubagentToolNameCallback toolName,
    required String Function() taskIdFactory,
    DateTime Function()? clock,
  }) : _handler = SubagentToolHandler(
         taskStore: SubagentTaskStoreAdapter(
           lookupTask: lookupTask,
           registerTask: registerTask,
           completeTask: completeTask,
           failTask: failTask,
           markTaskNotified: markTaskNotified,
         ),
         executionPort: CallbackSubagentExecutionPort(execute),
         childToolExecutionPort: childToolExecutionPort,
         notificationPort: CallbackSubagentNotificationPort(notify),
         ownerLifecyclePort: CallbackSubagentOwnerLifecyclePort(
           isTaskCurrent: isTaskCurrent,
           isLookupCurrent: isLookupCurrent,
         ),
         toolCatalogPort: CallbackSubagentToolCatalogPort(
           filterTools: filterTools,
           toolName: toolName,
         ),
         taskIdFactory: taskIdFactory,
         clock: clock,
       );

  final SubagentToolHandler _handler;

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required List<Map<String, dynamic>> parentToolDefinitions,
  }) {
    return _handler.handle(
      SubagentToolRequest(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        arguments: toolCall.arguments,
        parentToolDefinitions: parentToolDefinitions,
      ),
    );
  }
}

final class SubagentTaskStoreAdapter implements SubagentTaskStorePort {
  const SubagentTaskStoreAdapter({
    required SubagentTaskLookupCallback lookupTask,
    required SubagentTaskRegisterCallback registerTask,
    required SubagentTaskCompleteCallback completeTask,
    required SubagentTaskFailCallback failTask,
    required SubagentTaskMarkNotifiedCallback markTaskNotified,
  }) : _lookupTask = lookupTask,
       _registerTask = registerTask,
       _completeTask = completeTask,
       _failTask = failTask,
       _markTaskNotified = markTaskNotified;

  final SubagentTaskLookupCallback _lookupTask;
  final SubagentTaskRegisterCallback _registerTask;
  final SubagentTaskCompleteCallback _completeTask;
  final SubagentTaskFailCallback _failTask;
  final SubagentTaskMarkNotifiedCallback _markTaskNotified;

  @override
  SubagentTransitionReceipt register(
    SubagentTaskIdentity identity,
    SubagentTask task,
  ) {
    if (!_matchesIdentity(task, identity) ||
        _lookupTask(identity.owner, identity.taskId) != null) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    final reported = _registerTask(identity.owner, task);
    final after = _lookupTask(identity.owner, identity.taskId);
    if (reported && _matchesIdentity(after, identity) && after == task) {
      return _receipt(identity, SubagentTransitionDisposition.accepted);
    }
    if (!reported && after == null) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    return _receipt(identity, SubagentTransitionDisposition.effectUncertain);
  }

  @override
  SubagentTaskSnapshot? lookupExact(SubagentTaskIdentity identity) {
    final task = _lookupTask(identity.owner, identity.taskId);
    if (!_matchesIdentity(task, identity)) return null;
    return SubagentTaskSnapshot(identity: identity, task: task!);
  }

  @override
  SubagentResultSnapshot? lookupResult(SubagentResultLookup lookup) {
    final task = _lookupTask(lookup.invocation.owner, lookup.taskId);
    if (task == null ||
        task.id != lookup.taskId ||
        !task.isOwnedBy(lookup.invocation.owner) ||
        task.parentToolUseId == null ||
        task.parentToolUseId!.trim().isEmpty) {
      return null;
    }
    return SubagentResultSnapshot(
      lookup: lookup,
      taskIdentity: SubagentTaskIdentity(
        owner: lookup.invocation.owner,
        parentToolCallId: task.parentToolUseId!,
        taskId: lookup.taskId,
      ),
      task: task,
    );
  }

  @override
  SubagentTransitionReceipt complete(
    SubagentTaskIdentity identity, {
    required String output,
    required String summary,
  }) {
    final before = lookupExact(identity)?.task;
    if (before == null || !before.isActive) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    final reported = _completeTask(
      identity.owner,
      identity.taskId,
      output: output,
      summary: summary,
    );
    final after = lookupExact(identity)?.task;
    if (reported &&
        after?.status == SubagentTaskStatus.completed &&
        after?.output == output &&
        after?.resultSummary == summary) {
      return _receipt(identity, SubagentTransitionDisposition.accepted);
    }
    if (!reported && after == before) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    return _receipt(identity, SubagentTransitionDisposition.effectUncertain);
  }

  @override
  SubagentTransitionReceipt fail(SubagentTaskIdentity identity, String error) {
    final before = lookupExact(identity)?.task;
    if (before == null || !before.isActive) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    final reported = _failTask(identity.owner, identity.taskId, error);
    final after = lookupExact(identity)?.task;
    if (reported &&
        after?.status == SubagentTaskStatus.failed &&
        after?.error == error) {
      return _receipt(identity, SubagentTransitionDisposition.accepted);
    }
    if (!reported && after == before) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    return _receipt(identity, SubagentTransitionDisposition.effectUncertain);
  }

  @override
  SubagentTransitionReceipt markNotified(SubagentTaskIdentity identity) {
    final before = lookupExact(identity)?.task;
    if (before == null || before.notified || !before.isTerminal) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    final reported = _markTaskNotified(identity.owner, identity.taskId);
    final after = lookupExact(identity)?.task;
    if (reported && after?.notified == true) {
      return _receipt(identity, SubagentTransitionDisposition.accepted);
    }
    if (!reported && after == before) {
      return _receipt(identity, SubagentTransitionDisposition.rejected);
    }
    return _receipt(identity, SubagentTransitionDisposition.effectUncertain);
  }

  static bool _matchesIdentity(
    SubagentTask? task,
    SubagentTaskIdentity identity,
  ) {
    return task != null &&
        task.id == identity.taskId &&
        task.isOwnedBy(identity.owner) &&
        task.parentToolUseId == identity.parentToolCallId;
  }

  static SubagentTransitionReceipt _receipt(
    SubagentTaskIdentity identity,
    SubagentTransitionDisposition disposition,
  ) {
    return SubagentTransitionReceipt(
      identity: identity,
      disposition: disposition,
    );
  }
}

final class CallbackSubagentOwnerLifecyclePort
    implements SubagentOwnerLifecyclePort {
  const CallbackSubagentOwnerLifecyclePort({
    required SubagentTaskCurrentCallback isTaskCurrent,
    required SubagentLookupCurrentCallback isLookupCurrent,
  }) : _isTaskCurrent = isTaskCurrent,
       _isLookupCurrent = isLookupCurrent;

  final SubagentTaskCurrentCallback _isTaskCurrent;
  final SubagentLookupCurrentCallback _isLookupCurrent;

  @override
  bool isCurrent(SubagentTaskIdentity identity) => _isTaskCurrent(identity);

  @override
  bool isLookupCurrent(SubagentResultLookup lookup) => _isLookupCurrent(lookup);
}

final class CallbackSubagentExecutionPort implements SubagentExecutionPort {
  const CallbackSubagentExecutionPort(this._execute);

  final SubagentExecutionCallback _execute;

  @override
  Future<SubagentExecutionCompletion> run(
    SubagentExecutionRequest request, {
    required SubagentChildToolDispatcher dispatchToolCall,
  }) async {
    final task = await _execute(request, dispatchToolCall: dispatchToolCall);
    return SubagentExecutionCompletion(identity: request.identity, task: task);
  }
}

final class CallbackChildToolExecutionPort implements ChildToolExecutionPort {
  const CallbackChildToolExecutionPort(this._execute);

  final SubagentChildExecutionCallback _execute;

  @override
  Future<ChildToolExecutionCompletion> execute(
    ChildToolExecutionRequest request,
  ) async {
    final result = await _execute(request);
    return ChildToolExecutionCompletion(request: request, result: result);
  }
}

final class CallbackSubagentNotificationPort
    implements SubagentNotificationPort {
  const CallbackSubagentNotificationPort(this._notify);

  final SubagentNotificationCallback _notify;

  @override
  Future<SubagentTransitionReceipt> notify(
    SubagentTaskIdentity identity,
    SubagentCompletionNotification notification,
  ) async {
    await _notify(identity, notification);
    return SubagentTransitionReceipt(
      identity: identity,
      disposition: SubagentTransitionDisposition.accepted,
    );
  }
}

final class CallbackSubagentToolCatalogPort implements SubagentToolCatalogPort {
  const CallbackSubagentToolCatalogPort({
    required SubagentToolFilterCallback filterTools,
    required SubagentToolNameCallback toolName,
  }) : _filterTools = filterTools,
       _toolName = toolName;

  final SubagentToolFilterCallback _filterTools;
  final SubagentToolNameCallback _toolName;

  @override
  List<Map<String, dynamic>> filterInherited(
    List<Map<String, dynamic>> parentDefinitions,
  ) => _filterTools(parentDefinitions);

  @override
  String toolName(Map<String, dynamic> tool) => _toolName(tool);
}
