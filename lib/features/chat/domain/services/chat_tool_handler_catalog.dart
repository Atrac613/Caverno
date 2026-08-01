import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'chat_tool_dispatcher.dart';
import 'immutable_json_snapshot.dart';

typedef OwnerChatToolHandler =
    Future<McpToolResult> Function(ChatTurnOwner owner, ToolCallInfo toolCall);

typedef ChatMcpToolExecutionCallback =
    Future<McpToolResult> Function(ChatTurnOwner owner, ToolCallInfo toolCall);

/// Generic MCP execution kept explicit after specialized catalog dispatch.
abstract interface class ChatMcpToolExecutionPort {
  Future<McpToolResult> execute(ChatTurnOwner owner, ToolCallInfo toolCall);
}

final class CallbackChatMcpToolExecutionPort
    implements ChatMcpToolExecutionPort {
  const CallbackChatMcpToolExecutionPort(this._execute);

  final ChatMcpToolExecutionCallback _execute;

  @override
  Future<McpToolResult> execute(ChatTurnOwner owner, ToolCallInfo toolCall) =>
      _execute(owner, toolCall);
}

abstract interface class ToolDefinitionLogPort {
  void recordFilteredToolNames(List<String> names);

  void recordNoAllowlistMatches(Set<String> allowedToolNames);
}

abstract interface class ChatToolHandlerCatalogModule {
  Map<String, OwnerChatToolHandler> get handlers;
}

final class ProjectScopedChatToolHandlers
    implements ChatToolHandlerCatalogModule {
  ProjectScopedChatToolHandlers({
    required OwnerChatToolHandler projectScoped,
    required OwnerChatToolHandler lspGoToDefinition,
  }) : handlers = Map<String, OwnerChatToolHandler>.unmodifiable({
         for (final name in const [
           'list_directory',
           'read_file',
           'inspect_file',
           'find_files',
           'search_files',
         ])
           name: projectScoped,
         'lsp_go_to_definition': lspGoToDefinition,
       });

  @override
  final Map<String, OwnerChatToolHandler> handlers;
}

final class OwnerScopedChatToolHandlers
    implements ChatToolHandlerCatalogModule {
  OwnerScopedChatToolHandlers({
    required OwnerChatToolHandler fileMutation,
    required OwnerChatToolHandler fileRollback,
    required OwnerChatToolHandler localCommand,
    required OwnerChatToolHandler backgroundProcessMutation,
    required OwnerChatToolHandler projectScopedProcess,
    required OwnerChatToolHandler runTests,
    required OwnerChatToolHandler pythonScript,
    required OwnerChatToolHandler ssh,
    required OwnerChatToolHandler git,
    required OwnerChatToolHandler ble,
    required OwnerChatToolHandler serial,
    required OwnerChatToolHandler saveSkill,
    required OwnerChatToolHandler createRoutine,
  }) : handlers = Map<String, OwnerChatToolHandler>.unmodifiable({
         for (final name in const ['write_file', 'edit_file', 'delete_file'])
           name: fileMutation,
         'rollback_last_file_change': fileRollback,
         'local_execute_command': localCommand,
         for (final name in const ['process_start', 'process_cancel'])
           name: backgroundProcessMutation,
         for (final name in const [
           'process_status',
           'process_tail',
           'process_wait',
           'process_list',
         ])
           name: projectScopedProcess,
         'run_tests': runTests,
         'run_python_script': pythonScript,
         for (final name in const [
           'ssh_connect',
           'ssh_execute_command',
           'ssh_disconnect',
         ])
           name: ssh,
         for (final name in const [
           'git_execute_command',
           'git_finish_worktree_session',
         ])
           name: git,
         'ble_connect': ble,
         'serial_open': serial,
         'save_skill': saveSkill,
         'create_routine': createRoutine,
       });

  @override
  final Map<String, OwnerChatToolHandler> handlers;
}

final class ConversationChatToolHandlers
    implements ChatToolHandlerCatalogModule {
  ConversationChatToolHandlers({
    required OwnerChatToolHandler askUserQuestion,
    required OwnerChatToolHandler subagent,
    required OwnerChatToolHandler updateGoal,
  }) : handlers = Map<String, OwnerChatToolHandler>.unmodifiable({
         'ask_user_question': askUserQuestion,
         for (final name in const ['spawn_subagent', 'get_subagent_result'])
           name: subagent,
         'update_goal': updateGoal,
       });

  @override
  final Map<String, OwnerChatToolHandler> handlers;
}

final class MapChatToolHandlerCatalogModule
    implements ChatToolHandlerCatalogModule {
  MapChatToolHandlerCatalogModule(Map<String, OwnerChatToolHandler> handlers)
    : handlers = Map<String, OwnerChatToolHandler>.unmodifiable(handlers);

  @override
  final Map<String, OwnerChatToolHandler> handlers;
}

// ChatNotifier decomposition collaborator: chat-tool-handler-catalog
final class ChatToolHandlerCatalog {
  factory ChatToolHandlerCatalog.standard({
    required ProjectScopedChatToolHandlers projectScoped,
    required OwnerScopedChatToolHandlers ownerScoped,
    required ConversationChatToolHandlers conversation,
    required ChatMcpToolExecutionPort fallback,
    ToolDefinitionLogPort? definitionLog,
  }) => ChatToolHandlerCatalog.fromModules(
    [projectScoped, ownerScoped, conversation],
    fallback: fallback,
    definitionLog: definitionLog,
  );

  factory ChatToolHandlerCatalog.fromModules(
    Iterable<ChatToolHandlerCatalogModule> modules, {
    required ChatMcpToolExecutionPort fallback,
    ToolDefinitionLogPort? definitionLog,
  }) {
    return ChatToolHandlerCatalog._(
      handlers: {for (final module in modules) ...module.handlers},
      fallback: fallback,
      definitionLog: definitionLog,
    );
  }

  ChatToolHandlerCatalog._({
    required Map<String, OwnerChatToolHandler> handlers,
    required ChatMcpToolExecutionPort fallback,
    required ToolDefinitionLogPort? definitionLog,
  }) : _handlers = Map<String, OwnerChatToolHandler>.unmodifiable(handlers),
       _fallback = fallback,
       _definitionLog = definitionLog;

  static const Set<String> standardToolNames = {
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
    'lsp_go_to_definition',
    'write_file',
    'edit_file',
    'delete_file',
    'rollback_last_file_change',
    'local_execute_command',
    'process_start',
    'process_cancel',
    'process_status',
    'process_tail',
    'process_wait',
    'process_list',
    'run_tests',
    'run_python_script',
    'ssh_connect',
    'ssh_execute_command',
    'ssh_disconnect',
    'git_execute_command',
    'git_finish_worktree_session',
    'ble_connect',
    'serial_open',
    'save_skill',
    'create_routine',
    'ask_user_question',
    'spawn_subagent',
    'get_subagent_result',
    'update_goal',
  };

  final Map<String, OwnerChatToolHandler> _handlers;
  final ChatMcpToolExecutionPort _fallback;
  final ToolDefinitionLogPort? _definitionLog;

  Set<String> get toolNames => Set<String>.unmodifiable(_handlers.keys);

  List<Map<String, dynamic>> definitionsAllowedBy(
    Iterable<Map<String, dynamic>> definitions,
    Set<String>? allowedToolNames,
  ) {
    final frozenDefinitions = List<Map<String, dynamic>>.unmodifiable(
      definitions.map(ImmutableJsonSnapshot.freezeMap),
    );
    final filtered = allowedToolNames == null
        ? frozenDefinitions
        : List<Map<String, dynamic>>.unmodifiable(
            frozenDefinitions.where((definition) {
              final function = definition['function'];
              final name = function is Map
                  ? function['name']?.toString()
                  : null;
              return name != null && allowedToolNames.contains(name);
            }),
          );
    final names = List<String>.unmodifiable(
      filtered
          .map((definition) => (definition['function'] as Map?)?['name'])
          .whereType<Object>()
          .map((name) => name.toString()),
    );
    _definitionLog?.recordFilteredToolNames(names);
    if (allowedToolNames != null && filtered.isEmpty) {
      _definitionLog?.recordNoAllowlistMatches(
        Set<String>.unmodifiable(allowedToolNames),
      );
    }
    return filtered;
  }

  ChatToolHandlerRegistry registryFor(ChatTurnOwner owner) {
    return ChatToolHandlerRegistry({
      for (final entry in _handlers.entries)
        entry.key: (toolCall) => entry.value(owner, _freezeToolCall(toolCall)),
    });
  }

  ChatToolHandler fallbackHandlerFor(ChatTurnOwner owner) {
    return (toolCall) => _fallback.execute(owner, _freezeToolCall(toolCall));
  }

  Future<McpToolResult> dispatch(ChatTurnOwner owner, ToolCallInfo toolCall) {
    final frozenCall = _freezeToolCall(toolCall);
    final handler = _handlers[frozenCall.name];
    return handler == null
        ? _fallback.execute(owner, frozenCall)
        : handler(owner, frozenCall);
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo source) => ToolCallInfo(
  id: source.id,
  name: source.name,
  arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
);
