import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';

const String spawnSubagentToolName = 'spawn_subagent';
const String getSubagentResultToolName = 'get_subagent_result';

/// Exact identity of one parent subagent-tool invocation.
final class SubagentToolInvocation {
  SubagentToolInvocation({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) {
    if (toolCallId.trim().isEmpty) {
      throw ArgumentError.value(
        toolCallId,
        'toolCallId',
        'A non-empty tool call ID is required.',
      );
    }
    if (toolName != spawnSubagentToolName &&
        toolName != getSubagentResultToolName) {
      throw ArgumentError.value(
        toolName,
        'toolName',
        'A canonical subagent tool name is required.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
}

/// Exact owner, parent call, and task identity for asynchronous work.
final class SubagentTaskIdentity {
  SubagentTaskIdentity({
    required this.owner,
    required this.parentToolCallId,
    required this.taskId,
  }) {
    if (parentToolCallId.trim().isEmpty || taskId.trim().isEmpty) {
      throw ArgumentError(
        'Subagent parent call and task IDs must not be empty.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String parentToolCallId;
  final String taskId;

  @override
  bool operator ==(Object other) =>
      other is SubagentTaskIdentity &&
      other.owner == owner &&
      other.parentToolCallId == parentToolCallId &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(owner, parentToolCallId, taskId);
}

final class SubagentResultLookup {
  const SubagentResultLookup({required this.invocation, required this.taskId});

  final SubagentToolInvocation invocation;
  final String taskId;
}

final class SubagentToolRequest {
  SubagentToolRequest({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    List<Map<String, dynamic>> parentToolDefinitions = const [],
  }) : invocation = SubagentToolInvocation(
         owner: owner,
         toolCallId: toolCallId,
         toolName: toolName,
       ),
       arguments = freezeSubagentMap(arguments),
       parentToolDefinitions = List<Map<String, dynamic>>.unmodifiable(
         parentToolDefinitions.map(freezeSubagentMap),
       );

  final SubagentToolInvocation invocation;
  final Map<String, dynamic> arguments;
  final List<Map<String, dynamic>> parentToolDefinitions;

  ChatTurnOwner get owner => invocation.owner;
  String get toolCallId => invocation.toolCallId;
  String get toolName => invocation.toolName;
}

final class SubagentExecutionRequest {
  SubagentExecutionRequest({
    required this.identity,
    required this.description,
    required this.prompt,
    required List<Map<String, dynamic>> tools,
    required Set<String> allowedToolNames,
    required this.isBackground,
  }) : tools = List<Map<String, dynamic>>.unmodifiable(
         tools.map(freezeSubagentMap),
       ),
       allowedToolNames = Set<String>.unmodifiable(allowedToolNames);

  final SubagentTaskIdentity identity;
  final String description;
  final String prompt;
  final List<Map<String, dynamic>> tools;
  final Set<String> allowedToolNames;
  final bool isBackground;

  SubagentTaskIdentity get key => identity;
  String get parentToolUseId => identity.parentToolCallId;
}

final class SubagentExecutionCompletion {
  const SubagentExecutionCompletion({
    required this.identity,
    required this.task,
  });

  final SubagentTaskIdentity identity;
  final SubagentTask task;
}

final class ChildToolExecutionRequest {
  ChildToolExecutionRequest({
    required this.taskIdentity,
    required this.id,
    required this.name,
    required Map<String, dynamic> arguments,
    required Set<String> allowedToolNames,
  }) : arguments = freezeSubagentMap(arguments),
       allowedToolNames = Set<String>.unmodifiable(allowedToolNames) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Child tool call ID and name must not be empty.');
    }
  }

  final SubagentTaskIdentity taskIdentity;
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final Set<String> allowedToolNames;
}

final class ChildToolExecutionCompletion {
  const ChildToolExecutionCompletion({
    required this.request,
    required this.result,
  });

  final ChildToolExecutionRequest request;
  final McpToolResult result;
}

final class SubagentCompletionNotification {
  const SubagentCompletionNotification({
    required this.taskId,
    required this.description,
    required this.isSuccessful,
    required this.body,
  });

  final String taskId;
  final String description;
  final bool isSuccessful;
  final String body;
}

enum SubagentTransitionDisposition { accepted, rejected, effectUncertain }

final class SubagentTransitionReceipt {
  const SubagentTransitionReceipt({
    required this.identity,
    required this.disposition,
  });

  final SubagentTaskIdentity identity;
  final SubagentTransitionDisposition disposition;

  bool accepts(SubagentTaskIdentity expected) =>
      identity == expected &&
      disposition == SubagentTransitionDisposition.accepted;
}

final class SubagentTaskSnapshot {
  const SubagentTaskSnapshot({required this.identity, required this.task});

  final SubagentTaskIdentity identity;
  final SubagentTask task;
}

final class SubagentResultSnapshot {
  const SubagentResultSnapshot({
    required this.lookup,
    required this.taskIdentity,
    required this.task,
  });

  final SubagentResultLookup lookup;
  final SubagentTaskIdentity taskIdentity;
  final SubagentTask task;
}

abstract interface class SubagentOwnerLifecyclePort {
  bool isCurrent(SubagentTaskIdentity identity);

  bool isLookupCurrent(SubagentResultLookup lookup);
}

abstract interface class SubagentToolCatalogPort {
  List<Map<String, dynamic>> filterInherited(
    List<Map<String, dynamic>> parentDefinitions,
  );

  String toolName(Map<String, dynamic> tool);
}

abstract interface class SubagentTaskStorePort {
  /// Registration must reject a duplicate owner-plus-task ID even when the
  /// parent call differs, keeping result lookup unambiguous.
  SubagentTransitionReceipt register(
    SubagentTaskIdentity identity,
    SubagentTask task,
  );

  SubagentTaskSnapshot? lookupExact(SubagentTaskIdentity identity);

  SubagentResultSnapshot? lookupResult(SubagentResultLookup lookup);

  SubagentTransitionReceipt complete(
    SubagentTaskIdentity identity, {
    required String output,
    required String summary,
  });

  SubagentTransitionReceipt fail(SubagentTaskIdentity identity, String error);

  SubagentTransitionReceipt markNotified(SubagentTaskIdentity identity);
}

typedef SubagentChildToolDispatcher =
    Future<McpToolResult> Function(ToolCallInfo toolCall);

abstract interface class SubagentExecutionPort {
  Future<SubagentExecutionCompletion> run(
    SubagentExecutionRequest request, {
    required SubagentChildToolDispatcher dispatchToolCall,
  });
}

abstract interface class ChildToolExecutionPort {
  Future<ChildToolExecutionCompletion> execute(
    ChildToolExecutionRequest request,
  );
}

abstract interface class SubagentNotificationPort {
  Future<SubagentTransitionReceipt> notify(
    SubagentTaskIdentity identity,
    SubagentCompletionNotification notification,
  );
}

Map<String, dynamic> freezeSubagentMap(Map<String, dynamic> source) {
  return ImmutableJsonSnapshot.freezeMap(source);
}
