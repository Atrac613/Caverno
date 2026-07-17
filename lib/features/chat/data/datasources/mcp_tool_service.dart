import 'dart:convert';

import '../../../../core/services/ble_service.dart';
import '../../../../core/services/browser_session_service.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/lan_scan_service.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/services/serial_port_service.dart';
import '../../../../core/services/wifi_service.dart';
import '../../../../core/services/script_runtime/script_runtime.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/session_memory.dart';
import '../../domain/entities/skill.dart';
import '../../domain/services/tool_definition_search_service.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../repositories/chat_memory_repository.dart';
import '../repositories/conversation_repository_api.dart';
import '../repositories/skill_repository.dart';
import 'background_process_tools.dart';
import 'background_process_monitor_service.dart';
import 'built_in_ble_tool_handler.dart';
import 'built_in_browser_tool_handler.dart';
import 'built_in_computer_use_tool_handler.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'built_in_lan_scan_tool_handler.dart';
import 'built_in_local_command_tool_handler.dart';
import 'built_in_network_tool_handler.dart';
import 'built_in_serial_tool_handler.dart';
import 'built_in_ssh_tool_handler.dart';
import 'built_in_wifi_tool_handler.dart';
import 'conversation_search_tool.dart';
import 'file_rollback_checkpoint_store.dart';
import 'filesystem_tools.dart';
import 'git_execute_command_tool.dart';
import 'git_finish_worktree_session_tool.dart';
import 'git_tools.dart';
import 'installed_dependency_grounding_service.dart';
import 'local_shell_tools.dart';
import 'mcp_client.dart';
import 'mcp_tool_result_normalizer.dart';
import 'os_log_tools.dart';
import 'python_script_tools.dart';
import 'remote_mcp_connection_manager.dart';
import 'searxng_client.dart';

/// MCP tool management service.
///
/// Fetches tools dynamically from an MCP server and executes them.
/// Falls back to SearXNG when the MCP server is unavailable.
part 'mcp_tool_service_builtin_tool_definitions.dart';

class McpToolService {
  static const Set<String> _reservedToolNames = {
    'get_current_datetime',
    ConversationSearchTool.toolName,
    'recall_memory',
    ...{'ask_user_question', 'spawn_subagent', 'get_subagent_result'},
    ...{'load_skill', 'save_skill'},
    'create_routine',
    ...BuiltInNetworkToolHandler.toolNames,
    ...BuiltInFilesystemToolHandler.toolNames,
    InstalledDependencyGroundingService.toolName,
    'lsp_go_to_definition',
    ...BuiltInLocalCommandToolHandler.toolNames,
    'run_python_script',
    GitExecuteCommandTool.toolName,
    GitFinishWorktreeSessionTool.toolName,
    ...OsLogTools.allToolNames,
    ...BuiltInSshToolHandler.toolNames,
    ...BuiltInBleToolHandler.toolNames,
    ...BuiltInWifiToolHandler.toolNames,
    ...BuiltInLanScanToolHandler.toolNames,
    ...BuiltInSerialToolHandler.toolNames,
    ...BuiltInComputerUseToolHandler.toolNames,
    ...BuiltInBrowserToolHandler.toolNames,
    ToolDefinitionSearchService.toolName,
  };

  static final RegExp _whitespaceRun = RegExp(r'\s+');
  McpToolService({
    this.mcpClients = const [],
    this.searxngClient,
    this.conversationRepository,
    this.memoryRepository,
    this.skillRepository,
    this.sshService,
    this.bleService,
    this.wifiService,
    this.lanScanService,
    this.serialPortService,
    this.computerUseService,
    this.browserService,
    this.osLogProcessRunner,
    this.scriptRuntimeRegistry,
    this.backgroundProcessTools,
    this.backgroundProcessMonitorService,
    BuiltInNetworkToolHandler? networkToolHandler,
    BuiltInFilesystemToolHandler? filesystemToolHandler,
    BuiltInLocalCommandToolHandler? localCommandToolHandler,
    BuiltInSshToolHandler? sshToolHandler,
    BuiltInBleToolHandler? bleToolHandler,
    BuiltInWifiToolHandler? wifiToolHandler,
    BuiltInLanScanToolHandler? lanScanToolHandler,
    BuiltInSerialToolHandler? serialToolHandler,
    BuiltInComputerUseToolHandler? computerUseToolHandler,
    BuiltInBrowserToolHandler? browserToolHandler,
    RemoteMcpConnectionManager? remoteMcpConnectionManager,
    InstalledDependencyGroundingService? dependencyGroundingService,
    this.semanticConversationRanker,
    this.disabledBuiltInTools = const {},
  }) : networkToolHandler = networkToolHandler ?? BuiltInNetworkToolHandler(),
       filesystemToolHandler =
           filesystemToolHandler ?? BuiltInFilesystemToolHandler(),
       localCommandToolHandler =
           localCommandToolHandler ??
           BuiltInLocalCommandToolHandler(
             backgroundProcessTools: backgroundProcessTools,
             backgroundProcessMonitorService: backgroundProcessMonitorService,
           ),
       sshToolHandler =
           sshToolHandler ?? BuiltInSshToolHandler(sshService: sshService),
       bleToolHandler =
           bleToolHandler ?? BuiltInBleToolHandler(bleService: bleService),
       wifiToolHandler =
           wifiToolHandler ?? BuiltInWifiToolHandler(wifiService: wifiService),
       lanScanToolHandler =
           lanScanToolHandler ??
           BuiltInLanScanToolHandler(lanScanService: lanScanService),
       serialToolHandler =
           serialToolHandler ??
           BuiltInSerialToolHandler(serialPortService: serialPortService),
       computerUseToolHandler =
           computerUseToolHandler ??
           BuiltInComputerUseToolHandler(
             computerUseService: computerUseService,
           ),
       browserToolHandler =
           browserToolHandler ??
           BuiltInBrowserToolHandler(browserService: browserService),
       _remoteMcpConnectionManager =
           remoteMcpConnectionManager ??
           RemoteMcpConnectionManager(
             configuredClients: mcpClients,
             reservedToolNames: _reservedToolNames,
             reservedToolNamePrefixes: const {'browser_', 'computer_'},
           ),
       dependencyGroundingService =
           dependencyGroundingService ??
           const InstalledDependencyGroundingService();

  final List<McpClientBase> mcpClients;
  final SearxngClient? searxngClient;
  final ConversationRepositoryApi? conversationRepository;
  final ChatMemoryRepository? memoryRepository;
  final SkillRepository? skillRepository;
  final SshService? sshService;
  final BleService? bleService;
  final WifiService? wifiService;
  final LanScanService? lanScanService;
  final SerialPortService? serialPortService;
  final MacosComputerUseService? computerUseService;
  final BrowserSessionService? browserService;
  final OsLogProcessRunner? osLogProcessRunner;
  final ScriptRuntimeRegistry? scriptRuntimeRegistry;
  final BackgroundProcessTools? backgroundProcessTools;
  final BackgroundProcessMonitorService? backgroundProcessMonitorService;
  final BuiltInNetworkToolHandler networkToolHandler;
  final BuiltInFilesystemToolHandler filesystemToolHandler;
  final BuiltInLocalCommandToolHandler localCommandToolHandler;
  final BuiltInSshToolHandler sshToolHandler;
  final BuiltInBleToolHandler bleToolHandler;
  final BuiltInWifiToolHandler wifiToolHandler;
  final BuiltInLanScanToolHandler lanScanToolHandler;
  final BuiltInSerialToolHandler serialToolHandler;
  final BuiltInComputerUseToolHandler computerUseToolHandler;
  final BuiltInBrowserToolHandler browserToolHandler;
  final RemoteMcpConnectionManager _remoteMcpConnectionManager;
  final InstalledDependencyGroundingService dependencyGroundingService;

  /// LL5: ranks conversation ids by semantic similarity for
  /// `search_past_conversations`. Null when semantic search is disabled, in
  /// which case the tool falls back to a keyword scan.
  final SemanticConversationRanker? semanticConversationRanker;

  final Set<String> disabledBuiltInTools;

  McpConnectionStatus get status => _remoteMcpConnectionManager.status;
  List<McpToolEntity> get tools => _remoteMcpConnectionManager.tools;
  List<McpServerConnectionInfo> get serverStates =>
      _remoteMcpConnectionManager.serverStates;
  String? get lastError => _remoteMcpConnectionManager.lastError;
  bool isExternalMcpToolName(String name) =>
      _remoteMcpConnectionManager.isExternalToolName(name);

  bool get _hasEnabledSkills =>
      skillRepository?.getAll().any((skill) => skill.isUsable) ?? false;

  /// Connects to the MCP server and fetches available tools.
  ///
  /// Uses [overrideUrls] or [overrideUrl] for connection tests instead of
  /// the saved URLs.
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {
    await _remoteMcpConnectionManager.connect(
      overrideServers: overrideServers,
      overrideUrls: overrideUrls,
      overrideUrl: overrideUrl,
    );
  }

  /// Refreshes the tool list.
  Future<void> refresh() async {
    await connect();
  }

  /// Returns tool definitions for the LLM.
  ///
  /// Returns dynamically fetched tools when MCP is connected.
  /// Otherwise returns the fallback `web_search` tool for SearXNG.
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final toolDefinitions = <Map<String, dynamic>>[];

    _addIfEnabled(toolDefinitions, _mcpToolCurrentDatetimeTool);
    _addIfEnabled(toolDefinitions, _mcpToolAskUserQuestionTool);
    _addIfEnabled(toolDefinitions, _spawnSubagentTool);
    _addIfEnabled(toolDefinitions, _getSubagentResultTool);

    // Built-in memory tools (always available).
    if (conversationRepository != null) {
      _addIfEnabled(toolDefinitions, ConversationSearchTool.definition);
    }
    if (memoryRepository != null) {
      _addIfEnabled(toolDefinitions, _recallMemoryTool);
    }
    if (_hasEnabledSkills) {
      _addIfEnabled(toolDefinitions, _loadSkillTool);
    }
    if (skillRepository != null) {
      _addIfEnabled(toolDefinitions, _saveSkillTool);
    }
    // ROUTINE1: scheduling a routine from chat. Intercepted by ChatNotifier for
    // a non-cacheable approval; always offered like other built-ins.
    _addIfEnabled(toolDefinitions, _createRoutineTool);

    // Built-in network tools (always available).
    for (final tool in networkToolHandler.definitions) {
      _addIfEnabled(toolDefinitions, tool);
    }

    // Read-only file inspection is safe on every platform, including the
    // iOS/Android sandbox, so the model can analyze attached or referenced
    // files (e.g. large logs) on mobile too.
    for (final tool in filesystemToolHandler.inspectionDefinitions) {
      _addIfEnabled(toolDefinitions, tool);
    }
    _addIfEnabled(toolDefinitions, _resolveInstalledDependencyTool);
    _addIfEnabled(toolDefinitions, _lspGoToDefinitionTool);

    // Mutating file tools stay desktop-only: writing arbitrary paths on a
    // sandboxed mobile OS is both risky and largely unusable.
    if (FilesystemTools.isDesktopPlatform) {
      for (final tool in filesystemToolHandler.mutationDefinitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    if (LocalShellTools.isDesktopPlatform) {
      _addIfEnabled(
        toolDefinitions,
        localCommandToolHandler.localExecuteCommandDefinition,
      );
      if (localCommandToolHandler.supportsBackgroundProcesses) {
        for (final tool in localCommandToolHandler.processDefinitions) {
          _addIfEnabled(toolDefinitions, tool);
        }
      }
      _addIfEnabled(
        toolDefinitions,
        localCommandToolHandler.runTestsDefinition,
      );
    }

    // Embedded Python script execution is available on every platform
    // (serious_python ships a native interpreter for iOS/Android/desktop).
    if (scriptRuntimeRegistry != null) {
      _addIfEnabled(toolDefinitions, PythonScriptTools.toolDefinition);
    }

    if (OsLogTools.supportsSystemInfo || OsLogTools.supportsLogRead) {
      for (final tool in OsLogTools.allTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // Git tools (desktop only — requires system git binary via Process.run).
    if (GitTools.isDesktopPlatform) {
      _addIfEnabled(toolDefinitions, GitExecuteCommandTool.toolDefinition);
      _addIfEnabled(
        toolDefinitions,
        GitFinishWorktreeSessionTool.toolDefinition,
      );
    }

    // SSH remote server tools (the session is managed per chat).
    if (sshToolHandler.isAvailable) {
      for (final tool in sshToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // BLE tools (available on all platforms; unsupported operations return
    // errors at runtime).
    if (bleToolHandler.isAvailable) {
      for (final tool in bleToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // WiFi tools (scan + connection info).
    if (wifiToolHandler.isAvailable) {
      for (final tool in wifiToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // LAN scan tools (subnet discovery + port scanning).
    if (lanScanToolHandler.isAvailable) {
      for (final tool in lanScanToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // Serial port tools (desktop only — macOS/Windows/Linux).
    if (serialToolHandler.canExposeDefinitions) {
      for (final tool in serialToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    if (computerUseToolHandler.isAvailable) {
      for (final tool in computerUseToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    if (browserToolHandler.isAvailable) {
      for (final tool in browserToolHandler.definitions) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // Use MCP tools when connected.
    if (status == McpConnectionStatus.connected && tools.isNotEmpty) {
      toolDefinitions.addAll(tools.map((tool) => tool.toOpenAiTool()));
    } else if (searxngClient != null) {
      // Fallback to the fixed SearXNG tool definition.
      _addIfEnabled(toolDefinitions, _mcpToolWebSearchToolFallback);
    }

    return ToolDefinitionSearchService.appendSearchToolIfUseful(
      toolDefinitions,
    );
  }

  void _addIfEnabled(
    List<Map<String, dynamic>> list,
    Map<String, dynamic> tool,
  ) {
    final name = (tool['function'] as Map<String, dynamic>)['name'] as String;
    if (!disabledBuiltInTools.contains(name)) {
      list.add(tool);
    }
  }

  /// Executes a tool.
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    appLog('[McpToolService] Executing tool: $name');
    appLog('[McpToolService] Arguments: $arguments');

    // 0. Built-in local tools.
    if (name == ToolDefinitionSearchService.toolName) {
      final query = (arguments['query'] as String?)?.trim() ?? '';
      final maxResults =
          ((arguments['max_results'] as num?)?.toInt() ??
                  ToolDefinitionSearchService.defaultMaxResults)
              .clamp(1, ToolDefinitionSearchService.maxResultsLimit)
              .toInt();
      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: getOpenAiToolDefinitions(),
        query: query,
        maxResults: maxResults,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'get_current_datetime') {
      final result = _buildCurrentDatetimeResult();
      appLog('[McpToolService] Local datetime tool executed successfully');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == ConversationSearchTool.toolName &&
        conversationRepository != null) {
      final result = await const ConversationSearchTool().run(
        arguments: arguments,
        conversations: conversationRepository!.getAll(),
        semanticRanker: semanticConversationRanker,
      );
      appLog(
        '[McpToolService] Conversation search executed: ${result.length} chars',
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'recall_memory' && memoryRepository != null) {
      final result = _recallMemory(arguments);
      appLog('[McpToolService] Memory recall executed: ${result.length} chars');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'load_skill' && skillRepository != null) {
      final result = _loadSkill(arguments);
      if (result == null) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'No matching enabled skill found',
        );
      }
      appLog('[McpToolService] Skill loaded: ${result.length} chars');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'save_skill') {
      // save_skill is intercepted by ChatNotifier for an interactive,
      // non-cacheable approval. Reaching here means there is no approval UI
      // (e.g. a routine or other background context), so refuse rather than
      // persist a skill without confirmation.
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage:
            'save_skill requires interactive approval and cannot run in this context',
      );
    }

    if (name == 'create_routine') {
      // create_routine is intercepted by ChatNotifier for an interactive,
      // non-cacheable approval. Reaching here means there is no approval UI
      // (e.g. a routine or other background context), so refuse rather than
      // schedule an autonomous routine without confirmation.
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage:
            'create_routine requires interactive approval and cannot run in this context',
      );
    }

    if (computerUseToolHandler.handles(name)) {
      return computerUseToolHandler.execute(name: name, arguments: arguments);
    }

    if (browserToolHandler.handles(name)) {
      return browserToolHandler.execute(name: name, arguments: arguments);
    }

    if (filesystemToolHandler.handles(name)) {
      return filesystemToolHandler.execute(name: name, arguments: arguments);
    }

    if (name == InstalledDependencyGroundingService.toolName) {
      final result = await dependencyGroundingService.resolve(arguments);
      return McpToolResultNormalizer.fromOkPayload(
        toolName: name,
        result: result,
        fallbackErrorMessage: 'Installed dependency grounding failed',
      );
    }

    if (name == 'lsp_go_to_definition') {
      return McpToolResultNormalizer.structuredFailure(
        toolName: name,
        payload: {
          'ok': false,
          'code': 'chat_handler_required',
          'error':
              'lsp_go_to_definition must be executed through the chat LSP session handler.',
        },
        errorMessage:
            'lsp_go_to_definition must be executed through the chat LSP session handler',
      );
    }

    if (localCommandToolHandler.handles(name)) {
      return localCommandToolHandler.execute(name: name, arguments: arguments);
    }

    if (name == 'run_python_script') {
      final runtime = scriptRuntimeRegistry?.forLanguage(
        ScriptRuntimeRegistry.defaultLanguage,
      );
      if (runtime == null) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'Python runtime is not available',
        );
      }
      final result = await PythonScriptTools.execute(
        runtime: runtime,
        arguments: arguments,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'os_get_system_info') {
      try {
        final result = await OsLogTools.getSystemInfo(
          processRunner: osLogProcessRunner,
        );
        appLog('[McpToolService] OS system info executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] OS system info error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'os_log_read') {
      try {
        final keywords = switch (arguments['keywords']) {
          final List<dynamic> values =>
            values.map((value) => value.toString()).toList(growable: false),
          final String value when value.trim().isNotEmpty => [value.trim()],
          _ => const <String>[],
        };
        final result = await OsLogTools.read(
          scope: (arguments['scope'] as String?)?.trim() ?? 'wifi',
          keywords: keywords,
          process: (arguments['process'] as String?)?.trim(),
          subsystem: (arguments['subsystem'] as String?)?.trim(),
          sinceMinutes: ((arguments['since_minutes'] as num?)?.toInt() ?? 30)
              .clamp(1, 1440),
          maxEntries: ((arguments['max_entries'] as num?)?.toInt() ?? 50).clamp(
            1,
            200,
          ),
          includeDebug: arguments['include_debug'] as bool? ?? false,
          processRunner: osLogProcessRunner,
        );
        appLog('[McpToolService] OS log read executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] OS log read error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    // Built-in network tools.
    if (networkToolHandler.handles(name)) {
      return networkToolHandler.execute(name: name, arguments: arguments);
    }

    // Built-in Git tool (desktop only).
    if (name == 'git_execute_command') {
      final command = (arguments['command'] as String?)?.trim() ?? '';
      final workingDirectory =
          (arguments['working_directory'] as String?)?.trim() ?? '';
      if (command.isEmpty || workingDirectory.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'command and working_directory are required',
        );
      }
      try {
        final result = await GitTools.execute(
          command: command,
          workingDirectory: workingDirectory,
          reason: (arguments['reason'] as String?)?.trim(),
        );
        final normalizedResult = McpToolResultNormalizer.fromCommandPayload(
          toolName: name,
          result: result,
          toolLabel: 'Git command',
        );
        if (!normalizedResult.isSuccess) {
          appLog(
            '[McpToolService] Git command failed: '
            '${normalizedResult.errorMessage}',
          );
          return normalizedResult;
        }
        appLog('[McpToolService] Git command executed successfully');
        return normalizedResult;
      } catch (e) {
        appLog('[McpToolService] Git command error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == GitFinishWorktreeSessionTool.toolName) {
      return GitFinishWorktreeSessionTool.execute(arguments);
    }

    // SSH connection and command approvals remain upstream in ChatNotifier.
    if (sshToolHandler.handles(name)) {
      return sshToolHandler.execute(name: name, arguments: arguments);
    }

    // Built-in BLE tools.
    if (bleToolHandler.isAvailable && bleToolHandler.handles(name)) {
      return bleToolHandler.execute(name: name, arguments: arguments);
    }

    // Built-in WiFi tools.
    if (wifiToolHandler.isAvailable && wifiToolHandler.handles(name)) {
      return wifiToolHandler.execute(name: name, arguments: arguments);
    }

    // Built-in LAN scan tools.
    if (lanScanToolHandler.isAvailable && lanScanToolHandler.handles(name)) {
      return lanScanToolHandler.execute(name: name, arguments: arguments);
    }

    // Built-in serial port tools (serial_open is handled in ChatNotifier for
    // user approval; the rest are dispatched here).
    if (serialToolHandler.isAvailable && serialToolHandler.handles(name)) {
      return serialToolHandler.execute(name: name, arguments: arguments);
    }

    // 1. Execute through the matching MCP server when connected.
    final remoteResult = await _remoteMcpConnectionManager.tryExecute(
      name: name,
      arguments: arguments,
    );
    if (remoteResult != null) {
      return remoteResult;
    }

    // 2. SearXNG fallback for `web_search` only.
    if (name == 'web_search' && searxngClient != null) {
      try {
        final query = arguments['query'] as String? ?? '';
        if (query.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Search query is empty',
          );
        }
        final result = await searxngClient!.searchAsText(query: query);
        appLog(
          '[McpToolService] SearXNG execution succeeded: ${result.length} chars',
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] SearXNG error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    // 3. No matching tool available.
    appLog('[McpToolService] No matching tool available: $name');
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: 'No matching tool available: $name',
    );
  }

  Future<FileRollbackPreview?> previewLastFileRollbackChange() async {
    return filesystemToolHandler.previewLastFileRollbackChange();
  }

  void beginFileTurnCheckpoint(String turnId) {
    filesystemToolHandler.beginFileTurnCheckpoint(turnId);
  }

  void endFileTurnCheckpoint() {
    filesystemToolHandler.endFileTurnCheckpoint();
  }

  Future<FileTurnRollbackPreview?> previewLastFileTurnCheckpoint() async {
    return filesystemToolHandler.previewLastFileTurnCheckpoint();
  }

  Future<McpToolResult> rollbackLastFileTurnCheckpoint() async {
    return filesystemToolHandler.rollbackLastFileTurnCheckpoint();
  }

  static Map<String, dynamic> get _spawnSubagentTool => {
    'type': 'function',
    'function': {
      'name': 'spawn_subagent',
      'description':
          'Delegate a focused, self-contained sub-task to a child agent that '
          'runs its own tool-calling loop and returns a concise summary. Use '
          'this to keep the main conversation focused: offload large file or '
          'code exploration, independent research, or a parallelizable step. '
          'The child inherits your tools except spawn_subagent itself (no '
          'nested delegation) and cannot see the main conversation, so the '
          'prompt must be complete on its own.',
      'parameters': {
        'type': 'object',
        'properties': {
          'description': {
            'type': 'string',
            'description':
                'Short label for the sub-task, shown in the UI and logs.',
          },
          'prompt': {
            'type': 'string',
            'description':
                'Full self-contained instructions for the subagent. Include '
                'all context it needs; it cannot see the main conversation.',
          },
          'background': {
            'type': 'boolean',
            'description':
                'Run asynchronously and return a task id immediately instead '
                'of waiting for the result. Defaults to false.',
          },
        },
        'required': ['description', 'prompt'],
      },
    },
  };

  static Map<String, dynamic> get _getSubagentResultTool => {
    'type': 'function',
    'function': {
      'name': 'get_subagent_result',
      'description':
          'Retrieve the status and result of a background subagent started '
          'with spawn_subagent(background: true). Pass the task_id returned '
          'when the subagent was started. Returns the summary once completed, '
          'or a running status if it is still working.',
      'parameters': {
        'type': 'object',
        'properties': {
          'task_id': {
            'type': 'string',
            'description': 'The task id returned by spawn_subagent.',
          },
        },
        'required': ['task_id'],
      },
    },
  };

  static Map<String, dynamic> get _loadSkillTool => {
    'type': 'function',
    'function': {
      'name': 'load_skill',
      'description':
          'Load the full markdown instructions for a saved user skill. Use this when the lightweight skills index says a skill matches the task.',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'Exact skill id from the lightweight index.',
          },
          'name': {
            'type': 'string',
            'description': 'Skill name when the id is unavailable.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _saveSkillTool => {
    'type': 'function',
    'function': {
      'name': 'save_skill',
      'description':
          'Save the current conversation\'s workflow as a reusable user skill '
          '(the inverse of load_skill). Use this when a repeatable, verified '
          'procedure emerges that the user will want to reuse later. The user '
          'must approve every save. Saving a name that already exists updates '
          'that skill instead of creating a duplicate. If a different-named but '
          'similar skill already exists, the tool returns the matches without '
          'saving; update the existing skill by reusing its exact name, or set '
          'allow_duplicate to true to create a separate skill anyway.',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Short, unique skill name (e.g. "iOS Release").',
          },
          'description': {
            'type': 'string',
            'description': 'One-line summary of what the skill does.',
          },
          'when_to_use': {
            'type': 'string',
            'description': 'When this skill should be applied.',
          },
          'content': {
            'type': 'string',
            'description':
                'The full skill instructions as markdown (the reusable steps).',
          },
          'allow_duplicate': {
            'type': 'boolean',
            'description':
                'Set to true to save a new skill even when a similar one '
                'already exists. Leave unset/false to be warned about '
                'near-duplicates first.',
          },
        },
        'required': ['name', 'content'],
      },
    },
  };

  static Map<String, dynamic> get _createRoutineTool => {
    'type': 'function',
    'function': {
      'name': 'create_routine',
      'description':
          'Schedule a recurring routine (an autonomous agent run) from the '
          'conversation. Use this when the user describes a repeating task on a '
          'schedule (e.g. "ping a host hourly and report the result"). The user '
          'must approve every routine; the approval previews the schedule, '
          'enabled tools, and delivery channels. The routine then runs '
          'unattended on its schedule.',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Short routine name (e.g. "Ping 192.168.0.1").',
          },
          'prompt': {
            'type': 'string',
            'description':
                'The instruction the routine runs each time (e.g. "Ping '
                '192.168.0.1 and report whether it is reachable").',
          },
          'schedule_mode': {
            'type': 'string',
            'enum': ['interval', 'daily'],
            'description':
                'interval = every N minutes/hours/days; daily = once per day '
                'at a fixed time. Defaults to interval.',
          },
          'interval_value': {
            'type': 'integer',
            'description': 'For interval mode: how many units between runs.',
            'minimum': 1,
          },
          'interval_unit': {
            'type': 'string',
            'enum': ['minutes', 'hours', 'days'],
            'description': 'For interval mode: the unit. Defaults to hours.',
          },
          'time_of_day': {
            'type': 'string',
            'description':
                'For daily mode: 24h "HH:MM" local time to run (e.g. "08:00").',
          },
          'tools_enabled': {
            'type': 'boolean',
            'description':
                'Allow the routine to use tools (required for tasks like ping). '
                'Defaults to false.',
          },
          'notify_on_completion': {
            'type': 'boolean',
            'description':
                'Show a local notification when the run completes. Defaults to '
                'true.',
          },
          'completion_action': {
            'type': 'string',
            'enum': ['none', 'google_chat', 'prompt_google_chat'],
            'description':
                'External delivery of the result. google_chat posts to the '
                'configured Google Chat webhook. Defaults to none.',
          },
          'google_chat_rule': {
            'type': 'string',
            'enum': ['on_success', 'on_failure', 'always'],
            'description':
                'When to post to Google Chat (if completion_action uses it). '
                'Defaults to on_failure.',
          },
          'workspace_directory': {
            'type': 'string',
            'description': 'Optional working directory for the routine run.',
          },
          'allow_workspace_writes': {
            'type': 'boolean',
            'description':
                'Allow the routine to write in the workspace directory. '
                'Defaults to false.',
          },
        },
        'required': ['name', 'prompt'],
      },
    },
  };

  String _buildCurrentDatetimeResult() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final thisWeekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekEnd.subtract(const Duration(days: 7));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final nextWeekEnd = thisWeekEnd.add(const Duration(days: 7));
    final recentStart = today.subtract(const Duration(days: 30));

    final payload = <String, dynamic>{
      'local_datetime': _formatDateTime(now),
      'timezone': now.timeZoneName,
      'utc_offset': _formatUtcOffset(now.timeZoneOffset),
      'relative_dates': {
        'today': _formatDate(today),
        'yesterday': _formatDate(yesterday),
        'tomorrow': _formatDate(tomorrow),
        'this_week': {
          'start': _formatDate(thisWeekStart),
          'end': _formatDate(thisWeekEnd),
        },
        'last_week': {
          'start': _formatDate(lastWeekStart),
          'end': _formatDate(lastWeekEnd),
        },
        'next_week': {
          'start': _formatDate(nextWeekStart),
          'end': _formatDate(nextWeekEnd),
        },
        'recent_30_days': {
          'start': _formatDate(recentStart),
          'end': _formatDate(today),
        },
      },
    };

    return jsonEncode(payload);
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateTime(DateTime value) {
    final date = _formatDate(value);
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$date $hour:$minute:$second';
  }

  String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  // ---------------------------------------------------------------------------
  // Built-in tool: recall_memory
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _recallMemoryTool => {
    'type': 'function',
    'function': {
      'name': 'recall_memory',
      'description':
          'Search stored memory entries (user preferences, facts, past '
          'topics) for relevant information. Faster than searching full '
          'conversations.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Keywords to search in stored memories',
          },
        },
        'required': ['query'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in coding tools (desktop only)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _resolveInstalledDependencyTool => {
    'type': 'function',
    'function': {
      'name': InstalledDependencyGroundingService.toolName,
      'description':
          'Resolve an installed dependency package or API symbol from the local project lockfile and installed source tree. Use this before guessing third-party APIs. The lookup is offline and returns only the locked installed version, never newer upstream docs.',
      'parameters': {
        'type': 'object',
        'properties': {
          'project_path': {
            'type': 'string',
            'description':
                'Absolute or project-relative project root. Optional when a coding project is selected.',
          },
          'ecosystem': {
            'type': 'string',
            'description':
                'Dependency ecosystem: auto, dart, node, python, or vendored.',
          },
          'package_name': {
            'type': 'string',
            'description':
                'Dependency package name from the project lockfile, such as openai_dart, @scope/pkg, or requests.',
          },
          'symbol': {
            'type': 'string',
            'description':
                'Optional API symbol, class, method, function, or import name to search inside the installed package source.',
          },
          'max_results': {
            'type': 'integer',
            'description':
                'Maximum number of source matches to return (default: 12, max: 50).',
          },
          'max_chars': {
            'type': 'integer',
            'description':
                'Maximum documentation excerpt size in characters (default: 12000, max: 60000).',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get _lspGoToDefinitionTool => {
    'type': 'function',
    'function': {
      'name': 'lsp_go_to_definition',
      'description':
          'Use the active language server to locate the definition for a '
          'symbol at a precise file position. Prefer this over broad text '
          'search when navigating from a usage to its declaration.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative source file path.',
          },
          'line': {
            'type': 'integer',
            'description':
                '1-based source line containing the symbol reference.',
          },
          'column': {
            'type': 'integer',
            'description': '1-based source column inside the symbol reference.',
          },
        },
        'required': ['path', 'line', 'column'],
      },
    },
  };

  String _recallMemory(Map<String, dynamic> arguments) {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) return 'Error: search query is empty';

    final memories = memoryRepository!.loadMemories();
    if (memories.isEmpty) return 'No memories stored yet.';

    final queryBiGrams = _biGrams(query);
    final scored = <_ScoredMemoryMatch>[];

    for (final memory in memories) {
      if (memory.isExpired) continue;
      final textBiGrams = _biGrams(memory.text);
      if (queryBiGrams.isEmpty || textBiGrams.isEmpty) continue;
      final intersection = queryBiGrams.intersection(textBiGrams).length;
      final union = queryBiGrams.union(textBiGrams).length;
      final similarity = union == 0 ? 0.0 : intersection / union;
      if (similarity > 0.05) {
        scored.add(_ScoredMemoryMatch(memory: memory, score: similarity));
      }
    }

    if (scored.isEmpty) return 'No matching memories found for: $query';

    scored.sort((a, b) => b.score.compareTo(a.score));
    final topMatches = scored.take(5);

    final buffer = StringBuffer();
    for (final match in topMatches) {
      final m = match.memory;
      buffer.writeln(
        '- [${m.type.name}] (confidence: ${m.confidence.toStringAsFixed(2)}) '
        '${m.text} (${_formatDate(m.updatedAt)})',
      );
    }
    return buffer.toString();
  }

  String? _loadSkill(Map<String, dynamic> arguments) {
    final id = (arguments['id'] as String?)?.trim() ?? '';
    final name = (arguments['name'] as String?)?.trim() ?? '';
    final lookup = id.isNotEmpty ? id : name;
    if (lookup.isEmpty) {
      return null;
    }

    final repository = skillRepository;
    if (repository == null) {
      return null;
    }

    final skill = repository.findByIdOrName(lookup);
    if (skill == null || !skill.isUsable) {
      return null;
    }
    return jsonEncode(_skillToToolResult(skill));
  }

  Map<String, dynamic> _skillToToolResult(Skill skill) {
    return {
      'id': skill.id,
      'name': skill.normalizedName,
      if (skill.normalizedDescription.isNotEmpty)
        'description': skill.normalizedDescription,
      if (skill.normalizedWhenToUse.isNotEmpty)
        'whenToUse': skill.normalizedWhenToUse,
      'content': skill.normalizedContent,
    };
  }

  Set<String> _biGrams(String text) {
    final normalized = text.toLowerCase().replaceAll(_whitespaceRun, '');
    if (normalized.isEmpty) return const {};
    if (normalized.length == 1) return {normalized};
    final grams = <String>{};
    for (var i = 0; i < normalized.length - 1; i++) {
      grams.add(normalized.substring(i, i + 2));
    }
    return grams;
  }
}

class _ScoredMemoryMatch {
  _ScoredMemoryMatch({required this.memory, required this.score});

  final MemoryEntry memory;
  final double score;
}
