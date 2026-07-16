import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    show GATTCharacteristicWriteType;

import '../../../../core/services/ble_service.dart';
import '../../../../core/services/browser_session_service.dart';
import '../../../../core/services/browser_tool_policy.dart';
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
import 'ble_tools.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'built_in_network_tool_handler.dart';
import 'conversation_search_tool.dart';
import 'file_rollback_checkpoint_store.dart';
import 'filesystem_tools.dart';
import 'git_execute_command_tool.dart';
import 'git_finish_worktree_session_tool.dart';
import 'git_tools.dart';
import 'installed_dependency_grounding_service.dart';
import 'lan_scan_tools.dart';
import 'local_shell_tools.dart';
import 'mcp_client.dart';
import 'mcp_stdio_client.dart';
import 'os_log_tools.dart';
import 'python_script_tools.dart';
import 'searxng_client.dart';
import 'serial_port_tools.dart';
import 'wifi_tools.dart';

/// MCP tool management service.
///
/// Fetches tools dynamically from an MCP server and executes them.
/// Falls back to SearXNG when the MCP server is unavailable.
part 'mcp_tool_service_connection.dart';
part 'mcp_tool_service_builtin_tool_definitions.dart';

class McpToolService {
  static const _maxToolNameLength = 64;
  static const Set<String> _reservedToolNames = {
    'get_current_datetime',
    ConversationSearchTool.toolName,
    'recall_memory',
    'ask_user_question',
    'load_skill',
    'create_routine',
    ...BuiltInNetworkToolHandler.toolNames,
    ...BuiltInFilesystemToolHandler.toolNames,
    InstalledDependencyGroundingService.toolName,
    'lsp_go_to_definition',
    'local_execute_command',
    'process_start',
    'process_status',
    'process_tail',
    'process_wait',
    'process_cancel',
    'process_list',
    'run_python_script',
    'run_tests',
    GitExecuteCommandTool.toolName,
    GitFinishWorktreeSessionTool.toolName,
    ...OsLogTools.allToolNames,
    'ssh_connect',
    'ssh_execute_command',
    'ssh_disconnect',
    ...BleTools.allToolNames,
    ...WifiTools.allToolNames,
    ...LanScanTools.allToolNames,
    ...SerialPortTools.allToolNames,
    'computer_get_permissions',
    'computer_request_permissions',
    'computer_open_system_settings',
    'computer_vision_observe',
    'computer_accessibility_snapshot',
    'computer_list_displays',
    'computer_list_windows',
    'computer_focus_window',
    'computer_screenshot',
    'computer_screenshot_window',
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_switch_space',
    'computer_press_key',
    'computer_start_system_audio_recording',
    'computer_stop_system_audio_recording',
    ...BrowserToolPolicy.allTools,
    ToolDefinitionSearchService.toolName,
  };

  static final RegExp _serverKeyInvalidChars = RegExp(r'[^a-zA-Z0-9_]+');
  static final RegExp _serverKeyConsecutiveUnderscores = RegExp(r'_+');
  static final RegExp _serverKeyEdgeUnderscores = RegExp(r'^_|_$');
  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _hexSeparatorChars = RegExp(r'[\s:-]');

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
    InstalledDependencyGroundingService? dependencyGroundingService,
    this.semanticConversationRanker,
    this.disabledBuiltInTools = const {},
  }) : networkToolHandler = networkToolHandler ?? BuiltInNetworkToolHandler(),
       filesystemToolHandler =
           filesystemToolHandler ?? BuiltInFilesystemToolHandler(),
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
  final InstalledDependencyGroundingService dependencyGroundingService;

  /// LL5: ranks conversation ids by semantic similarity for
  /// `search_past_conversations`. Null when semantic search is disabled, in
  /// which case the tool falls back to a keyword scan.
  final SemanticConversationRanker? semanticConversationRanker;

  final Set<String> disabledBuiltInTools;

  List<McpToolEntity> _cachedTools = [];
  final Map<String, _RemoteToolBinding> _remoteToolBindings = {};
  List<McpServerConnectionInfo> _serverStates = const [];
  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  String? _lastError;

  /// Current connection status.
  McpConnectionStatus get status => _status;

  /// Cached tool definitions.
  List<McpToolEntity> get tools => _cachedTools;

  /// Current connection status for each configured MCP server.
  List<McpServerConnectionInfo> get serverStates =>
      List.unmodifiable(_serverStates);

  /// Most recent error message.
  String? get lastError => _lastError;

  bool get _hasEnabledSkills =>
      skillRepository?.getAll().any((skill) => skill.isUsable) ?? false;

  String _backgroundProcessUnavailableResult() {
    return jsonEncode({
      'ok': false,
      'code': 'background_process_tools_unavailable',
      'error': 'Background process tools are not available',
    });
  }

  /// Connects to the MCP server and fetches available tools.
  ///
  /// Uses [overrideUrls] or [overrideUrl] for connection tests instead of
  /// the saved URLs.
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {
    final clients = overrideServers != null
        ? _resolveClientsFromServers(overrideServers)
        : overrideUrls != null || overrideUrl != null
        ? _resolveClients(
            targetUrls: overrideUrls ?? [overrideUrl!],
            useOverrides: true,
          )
        : mcpClients;

    if (clients.isEmpty) {
      appLog(
        '[McpToolService] No MCP clients configured, running without remote MCP',
      );
      _status = McpConnectionStatus.disconnected;
      _lastError = null;
      _cachedTools = [];
      _remoteToolBindings.clear();
      _serverStates = const [];
      return;
    }

    _status = McpConnectionStatus.connecting;
    _lastError = null;
    _serverStates = clients
        .map(
          (client) => McpServerConnectionInfo(
            identifier: client.identifier,
            status: McpConnectionStatus.connecting,
          ),
        )
        .toList(growable: false);

    try {
      final results = await Future.wait(clients.map(_connectClient));
      _serverStates = results
          .map(
            (result) => McpServerConnectionInfo(
              identifier: result.identifier,
              status: result.status,
              toolCount: result.tools.length,
              lastError: result.error,
            ),
          )
          .toList(growable: false);
      _rebuildRemoteToolCache(results);

      final successfulResults = results.where((result) => result.isSuccess);
      final failedResults = results
          .where((result) => !result.isSuccess)
          .toList();

      if (successfulResults.isNotEmpty) {
        _status = McpConnectionStatus.connected;
        _lastError = failedResults.isEmpty
            ? null
            : failedResults
                  .map((result) => '${result.identifier}: ${result.error}')
                  .join(' | ');
        appLog(
          '[McpToolService] Connected to ${successfulResults.length} MCP server(s): fetched ${_cachedTools.length} tools',
        );
        for (final tool in _cachedTools) {
          appLog('[McpToolService]   - ${tool.name}: ${tool.description}');
        }
        return;
      }

      _status = McpConnectionStatus.error;
      _lastError = failedResults
          .map((result) => '${result.identifier}: ${result.error}')
          .join(' | ');
      _cachedTools = [];
      _remoteToolBindings.clear();
    } catch (e, stackTrace) {
      appLog('[McpToolService] Connection failed: ${e.runtimeType}: $e');
      appLog('[McpToolService] stackTrace: $stackTrace');
      _status = McpConnectionStatus.error;
      _lastError = e.toString();
      _cachedTools = [];
      _remoteToolBindings.clear();
      _serverStates = clients
          .map(
            (client) => McpServerConnectionInfo(
              identifier: client.identifier,
              status: McpConnectionStatus.error,
              lastError: e.toString(),
            ),
          )
          .toList(growable: false);
    }
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
      _addIfEnabled(toolDefinitions, _localExecuteCommandTool);
      if (backgroundProcessTools?.isSupported ?? false) {
        _addIfEnabled(toolDefinitions, _processStartTool);
        _addIfEnabled(toolDefinitions, _processStatusTool);
        _addIfEnabled(toolDefinitions, _processTailTool);
        _addIfEnabled(toolDefinitions, _processWaitTool);
        _addIfEnabled(toolDefinitions, _processCancelTool);
        _addIfEnabled(toolDefinitions, _processListTool);
      }
      _addIfEnabled(toolDefinitions, _runTestsTool);
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

    // SSH remote server tools (always available — the session is managed
    // per-chat via ssh_connect / ssh_disconnect).
    if (sshService != null) {
      _addIfEnabled(toolDefinitions, _sshConnectTool);
      _addIfEnabled(toolDefinitions, _sshExecuteCommandTool);
      _addIfEnabled(toolDefinitions, _sshDisconnectTool);
    }

    // BLE tools (available on all platforms; unsupported operations return
    // errors at runtime).
    if (bleService != null) {
      for (final tool in BleTools.allTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // WiFi tools (scan + connection info).
    if (wifiService != null) {
      for (final tool in WifiTools.allTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // LAN scan tools (subnet discovery + port scanning).
    if (lanScanService != null) {
      for (final tool in LanScanTools.allTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // Serial port tools (desktop only — macOS/Windows/Linux).
    if (serialPortService != null && SerialPortService.isSupported) {
      for (final tool in SerialPortTools.allTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    if (computerUseService?.isAvailable ?? false) {
      for (final tool in _computerUseTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    if (browserService?.isAvailable ?? false) {
      for (final tool in _browserTools) {
        _addIfEnabled(toolDefinitions, tool);
      }
    }

    // Use MCP tools when connected.
    if (_status == McpConnectionStatus.connected && _cachedTools.isNotEmpty) {
      toolDefinitions.addAll(_cachedTools.map((t) => t.toOpenAiTool()));
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

  String? _commandResultFailureMessage(String result, String toolLabel) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map<String, dynamic>) return null;

      final error = decoded['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }

      final exitCode = decoded['exit_code'];
      if (exitCode is num && exitCode.toInt() != 0) {
        final stderr = decoded['stderr'];
        final stdout = decoded['stdout'];
        final detail = stderr is String && stderr.trim().isNotEmpty
            ? stderr.trim()
            : stdout is String && stdout.trim().isNotEmpty
            ? stdout.trim()
            : null;
        return detail == null
            ? '$toolLabel exited with code ${exitCode.toInt()}'
            : '$toolLabel exited with code ${exitCode.toInt()}: $detail';
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _asBool(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
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

    if (name.startsWith('computer_')) {
      final service = computerUseService;
      if (service == null || !service.isAvailable) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'macOS computer use tools are unavailable',
        );
      }
      final result = await _executeComputerUseTool(service, name, arguments);
      final decoded = _tryDecodeMap(result);
      final success = decoded == null || decoded['ok'] != false;
      return McpToolResult(
        toolName: name,
        result: result,
        isSuccess: success,
        errorMessage: success
            ? null
            : (decoded['error'] as String? ?? 'Computer use tool failed'),
      );
    }

    if (name.startsWith('browser_')) {
      final service = browserService;
      if (service == null || !service.isAvailable) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'Built-in browser tools are unavailable',
        );
      }
      final result = await _executeBrowserTool(service, name, arguments);
      final decoded = _tryDecodeMap(result);
      final success = decoded == null || decoded['ok'] != false;
      return McpToolResult(
        toolName: name,
        result: result,
        isSuccess: success,
        errorMessage: success
            ? null
            : (decoded['error'] as String? ?? 'Browser tool failed'),
      );
    }

    if (filesystemToolHandler.handles(name)) {
      return filesystemToolHandler.execute(name: name, arguments: arguments);
    }

    if (name == InstalledDependencyGroundingService.toolName) {
      final result = await dependencyGroundingService.resolve(arguments);
      final decoded = _tryDecodeMap(result);
      final success = decoded == null || decoded['ok'] != false;
      return McpToolResult(
        toolName: name,
        result: result,
        isSuccess: success,
        errorMessage: success
            ? null
            : (decoded['error'] as String? ??
                  'Installed dependency grounding failed'),
      );
    }

    if (name == 'lsp_go_to_definition') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'ok': false,
          'code': 'chat_handler_required',
          'error':
              'lsp_go_to_definition must be executed through the chat LSP session handler.',
        }),
        isSuccess: false,
        errorMessage:
            'lsp_go_to_definition must be executed through the chat LSP session handler',
      );
    }

    if (name == 'local_execute_command') {
      final command = LocalShellTools.normalizeCommand(
        (arguments['command'] as String?)?.trim() ?? '',
      );
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
      final gitWriteBlockedResult =
          LocalShellTools.gitWriteCommandBlockedResult(
            command: command,
            workingDirectory: workingDirectory,
          );
      if (gitWriteBlockedResult != null) {
        return McpToolResult(
          toolName: name,
          result: gitWriteBlockedResult,
          isSuccess: false,
          errorMessage: 'Use git_execute_command for git write commands',
        );
      }
      final isBackground = _asBool(arguments['background']);
      if (isBackground) {
        final tools = backgroundProcessTools;
        if (tools == null || !tools.isSupported) {
          return McpToolResult(
            toolName: name,
            result: _backgroundProcessUnavailableResult(),
            isSuccess: false,
            errorMessage: 'Background process tools are not available',
          );
        }
        final result = await tools.start(
          command: command,
          workingDirectory: workingDirectory,
          label: (arguments['label'] as String?)?.trim(),
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      }
      final result = await LocalShellTools.execute(
        command: command,
        workingDirectory: workingDirectory,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'process_start') {
      final command = LocalShellTools.normalizeCommand(
        (arguments['command'] as String?)?.trim() ?? '',
      );
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
      final gitWriteBlockedResult =
          LocalShellTools.gitWriteCommandBlockedResult(
            command: command,
            workingDirectory: workingDirectory,
          );
      if (gitWriteBlockedResult != null) {
        return McpToolResult(
          toolName: name,
          result: gitWriteBlockedResult,
          isSuccess: false,
          errorMessage: 'Use git_execute_command for git write commands',
        );
      }
      final tools = backgroundProcessTools;
      if (tools == null || !tools.isSupported) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'Background process tools are not available',
        );
      }
      final result = await tools.start(
        command: command,
        workingDirectory: workingDirectory,
        label: (arguments['label'] as String?)?.trim(),
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'process_status') {
      final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
      if (jobId.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'job_id is required',
        );
      }
      final result = await backgroundProcessTools?.status(
        jobId: jobId,
        tailChars: (arguments['tail_chars'] as num?)?.toInt(),
      );
      return McpToolResult(
        toolName: name,
        result: result ?? _backgroundProcessUnavailableResult(),
        isSuccess: result != null,
        errorMessage: result == null
            ? 'Background process tools are not available'
            : null,
      );
    }

    if (name == 'process_tail') {
      final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
      if (jobId.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'job_id is required',
        );
      }
      final result = await backgroundProcessTools?.tail(
        jobId: jobId,
        maxChars: (arguments['max_chars'] as num?)?.toInt(),
      );
      return McpToolResult(
        toolName: name,
        result: result ?? _backgroundProcessUnavailableResult(),
        isSuccess: result != null,
        errorMessage: result == null
            ? 'Background process tools are not available'
            : null,
      );
    }

    if (name == 'process_wait') {
      final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
      if (jobId.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'job_id is required',
        );
      }
      final result = await backgroundProcessTools?.wait(
        jobId: jobId,
        waitMs: (arguments['wait_ms'] as num?)?.toInt(),
      );
      return McpToolResult(
        toolName: name,
        result: result ?? _backgroundProcessUnavailableResult(),
        isSuccess: result != null,
        errorMessage: result == null
            ? 'Background process tools are not available'
            : null,
      );
    }

    if (name == 'process_list') {
      final monitor = backgroundProcessMonitorService;
      if (monitor == null) {
        return McpToolResult(
          toolName: name,
          result: jsonEncode({
            'ok': false,
            'code': 'background_process_monitor_unavailable',
            'error': 'Background process monitor is not available',
          }),
          isSuccess: false,
          errorMessage: 'Background process monitor is not available',
        );
      }

      final jobIdsArgument = arguments['job_ids'];
      List<String> jobIds;
      if (jobIdsArgument == null) {
        jobIds = const [];
      } else if (jobIdsArgument is List<dynamic>) {
        jobIds = jobIdsArgument
            .whereType<String>()
            .map((jobId) => jobId.trim())
            .where((jobId) => jobId.isNotEmpty)
            .toList(growable: false);
      } else {
        return McpToolResult(
          toolName: name,
          result: jsonEncode({
            'ok': false,
            'code': 'invalid_job_ids',
            'error': 'job_ids must be an array of strings',
          }),
          isSuccess: false,
          errorMessage: 'job_ids must be an array of strings',
        );
      }

      final includeFinished = arguments['include_finished'] is bool
          ? arguments['include_finished'] as bool
          : true;
      final refresh = arguments['refresh'] is bool
          ? arguments['refresh'] as bool
          : false;
      final requestedLimit = (arguments['limit'] as num?)?.toInt();
      if (refresh) {
        if (jobIds.isEmpty) {
          await monitor.refreshActiveJobs();
        } else {
          await monitor.refreshJobs(jobIds);
        }
      }

      final snapshots = monitor.listJobs(
        jobIds: jobIds,
        includeFinished: includeFinished,
        limit: requestedLimit,
      );
      final now = DateTime.now().toIso8601String();
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'ok': true,
          'generated_at': now,
          'job_count': snapshots.length,
          'jobs': snapshots
              .map((snapshot) => snapshot.toJson())
              .toList(growable: false),
          'active_count': monitor.activeSnapshots.length,
          'finished_count': snapshots
              .where((snapshot) => !snapshot.isRunning)
              .length,
        }),
        isSuccess: true,
      );
    }

    if (name == 'process_cancel') {
      final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
      if (jobId.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'job_id is required',
        );
      }
      final result = await backgroundProcessTools?.cancel(jobId: jobId);
      return McpToolResult(
        toolName: name,
        result: result ?? _backgroundProcessUnavailableResult(),
        isSuccess: result != null,
        errorMessage: result == null
            ? 'Background process tools are not available'
            : null,
      );
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

    if (name == 'run_tests') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'error':
              'run_tests must be executed through the chat command approval flow.',
          'code': 'approval_required',
        }),
        isSuccess: false,
        errorMessage:
            'run_tests must be executed through the chat command approval flow',
      );
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
        final failureMessage = _commandResultFailureMessage(
          result,
          'Git command',
        );
        if (failureMessage != null) {
          appLog('[McpToolService] Git command failed: $failureMessage');
          return McpToolResult(
            toolName: name,
            result: result,
            isSuccess: false,
            errorMessage: failureMessage,
          );
        }
        appLog('[McpToolService] Git command executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
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

    // SSH remote server tools.
    //
    // Contract: `ssh_connect` and the per-command confirmation for
    // `ssh_execute_command` are handled upstream in ChatNotifier, which has
    // access to the UI for user dialogs. By the time we reach this branch
    // for `ssh_execute_command`, the user has already approved the specific
    // command. `ssh_connect` should never reach this dispatch — the
    // notifier short-circuits it — so we return an error if it does.
    if (name == 'ssh_connect') {
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage:
            'ssh_connect must be handled by ChatNotifier (internal error)',
      );
    }

    if (name == 'ssh_execute_command') {
      if (sshService == null) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'SSH service is unavailable',
        );
      }
      if (!sshService!.isConnected) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'No active SSH session — call ssh_connect first',
        );
      }
      try {
        final command = (arguments['command'] as String?)?.trim() ?? '';
        if (command.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'command is required',
          );
        }
        final result = await sshService!.execute(command);
        appLog('[McpToolService] SSH command executed successfully');
        return McpToolResult(
          toolName: name,
          result: result.formatted(),
          isSuccess: true,
        );
      } catch (e) {
        appLog('[McpToolService] SSH execution error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'ssh_disconnect') {
      if (sshService == null) {
        return McpToolResult(
          toolName: name,
          result: 'No active SSH session',
          isSuccess: true,
        );
      }
      final wasConnected = sshService!.isConnected;
      try {
        await sshService!.disconnect();
        return McpToolResult(
          toolName: name,
          result: wasConnected ? 'Disconnected' : 'No active SSH session',
          isSuccess: true,
        );
      } catch (e) {
        appLog('[McpToolService] SSH disconnect error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    // Built-in BLE tools.
    if (BleTools.allToolNames.contains(name) && bleService != null) {
      return _executeBleToolCall(name, arguments);
    }

    // Built-in WiFi tools.
    if (WifiTools.allToolNames.contains(name) && wifiService != null) {
      return _executeWifiToolCall(name, arguments);
    }

    // Built-in LAN scan tools.
    if (LanScanTools.allToolNames.contains(name) && lanScanService != null) {
      return _executeLanScanToolCall(name, arguments);
    }

    // Built-in serial port tools (serial_open is handled in ChatNotifier for
    // user approval; the rest are dispatched here).
    if (SerialPortTools.allToolNames.contains(name) &&
        serialPortService != null) {
      return _executeSerialPortToolCall(name, arguments);
    }

    // 1. Execute through the matching MCP server when connected.
    final remoteBinding = _remoteToolBindings[name];
    if (_status == McpConnectionStatus.connected && remoteBinding != null) {
      try {
        final result = await remoteBinding.client.callTool(
          name: remoteBinding.remoteToolName,
          arguments: arguments,
        );
        appLog(
          '[McpToolService] MCP execution succeeded: ${result.length} chars',
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] MCP tool execution error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
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

  Map<String, dynamic>? _tryDecodeMap(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _executeComputerUseTool(
    MacosComputerUseService service,
    String name,
    Map<String, dynamic> arguments,
  ) {
    return switch (name) {
      'computer_get_permissions' => service.getPermissions(),
      'computer_request_permissions' => service.requestPermissions(
        accessibility: arguments['accessibility'] as bool? ?? true,
        screenCapture:
            arguments['screen_capture'] as bool? ??
            arguments['screenCapture'] as bool? ??
            true,
      ),
      'computer_open_system_settings' => service.openSystemSettings(
        section: arguments['section'] as String? ?? 'privacy',
      ),
      'computer_vision_observe' => service.visionObserve(arguments),
      'computer_accessibility_snapshot' => service.accessibilitySnapshot(
        arguments,
      ),
      'computer_list_displays' => service.listDisplays(arguments),
      'computer_list_windows' => service.listWindows(arguments),
      'computer_focus_window' => service.focusWindow(arguments),
      'computer_screenshot' => service.screenshot(arguments),
      'computer_screenshot_window' => service.screenshotWindow(arguments),
      'computer_move_mouse' => service.moveMouse(arguments),
      'computer_click' => service.click(arguments),
      'computer_drag' => service.drag(arguments),
      'computer_scroll' => service.scroll(arguments),
      'computer_type_text' => service.typeText(arguments),
      'computer_switch_space' => service.switchSpace(arguments),
      'computer_press_key' => service.pressKey(arguments),
      'computer_start_system_audio_recording' =>
        service.startSystemAudioRecording(arguments),
      'computer_stop_system_audio_recording' =>
        service.stopSystemAudioRecording(),
      _ => Future.value(
        jsonEncode({
          'ok': false,
          'code': 'tool_not_available',
          'error': 'No matching computer use tool is available: $name',
        }),
      ),
    };
  }

  Future<String> _executeBrowserTool(
    BrowserSessionService service,
    String name,
    Map<String, dynamic> arguments,
  ) {
    int? readRef() {
      final ref = arguments['ref'];
      if (ref is int) return ref;
      if (ref is num) return ref.toInt();
      if (ref is String) return int.tryParse(ref);
      return null;
    }

    String? readSelector() {
      final selector = (arguments['selector'] as String?)?.trim();
      return (selector == null || selector.isEmpty) ? null : selector;
    }

    return switch (name) {
      'browser_open' => service.openUrl((arguments['url'] as String?) ?? ''),
      'browser_snapshot' => service.snapshot(
        maxElements: (arguments['max_elements'] as num?)?.toInt(),
      ),
      'browser_get_content' => service.getContent(
        format: (arguments['format'] as String?) ?? 'text',
        maxChars: (arguments['max_chars'] as num?)?.toInt(),
      ),
      'browser_screenshot' => service.screenshot(),
      'browser_wait' => service.waitFor(
        selector: readSelector(),
        timeoutMs: (arguments['timeout_ms'] as num?)?.toInt(),
      ),
      'browser_navigate_history' => service.navigateHistory(
        (arguments['direction'] as String?) ?? 'reload',
      ),
      'browser_close' => Future.value(service.closePanel()),
      'browser_fill' => service.fillField(
        ref: readRef(),
        selector: readSelector(),
        value: (arguments['value'] as String?) ?? '',
      ),
      'browser_click' => service.clickElement(
        ref: readRef(),
        selector: readSelector(),
      ),
      'browser_submit' => service.submitForm(selector: readSelector()),
      'browser_eval' => service.evaluateJs(
        (arguments['script'] as String?) ?? '',
      ),
      'browser_save_data' => service.saveData(
        filename: (arguments['filename'] as String?) ?? 'browser_data',
        data: (arguments['data'] as String?) ?? '',
        format: (arguments['format'] as String?) ?? 'json',
        destination: arguments['destination'] as String?,
      ),
      _ => Future.value(
        jsonEncode({
          'ok': false,
          'code': 'tool_not_available',
          'error': 'No matching browser tool is available: $name',
        }),
      ),
    };
  }

  /// OpenAI tool schemas for the built-in agent-controlled browser.
  static List<Map<String, dynamic>> get _browserTools => [
    {
      'type': 'function',
      'function': {
        'name': 'browser_open',
        'description':
            'Open a URL in the built-in browser pane. On wide layouts it opens to the right of the workspace; on narrow layouts it opens above the chat input. Use this first, then browser_snapshot to inspect the page. Returns the final URL and title.',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description':
                  'The URL to navigate to. https:// is assumed if no scheme is given.',
            },
            'reason': {
              'type': 'string',
              'description': 'Short note on why you are opening this page.',
            },
          },
          'required': ['url'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_snapshot',
        'description':
            'List the visible interactive elements (links, buttons, inputs, selects) of the current page, each with a stable "ref" index plus tag, label, name and type. Pass a ref to browser_fill / browser_click. Re-run after navigation.',
        'parameters': {
          'type': 'object',
          'properties': {
            'max_elements': {
              'type': 'integer',
              'description':
                  'Maximum number of elements to return (default 80).',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_get_content',
        'description':
            'Read the current page for parsing/scraping. format "text" returns rendered innerText; "html" returns full HTML. Large content is truncated.',
        'parameters': {
          'type': 'object',
          'properties': {
            'format': {
              'type': 'string',
              'enum': ['text', 'html'],
              'description':
                  'text (default) for readable text, html for raw markup.',
            },
            'max_chars': {
              'type': 'integer',
              'description': 'Maximum characters to return (default 100000).',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_screenshot',
        'description':
            'Capture a PNG screenshot of the current page. Returns base64 image data.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_wait',
        'description':
            'Wait for the page to finish loading, or until a CSS selector appears. Use after a click that triggers navigation or async content.',
        'parameters': {
          'type': 'object',
          'properties': {
            'selector': {
              'type': 'string',
              'description':
                  'Optional CSS selector to wait for. Omit to just wait for load.',
            },
            'timeout_ms': {
              'type': 'integer',
              'description':
                  'Maximum time to wait in milliseconds (default 8000).',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_navigate_history',
        'description':
            'Navigate the browser history: back, forward, or reload.',
        'parameters': {
          'type': 'object',
          'properties': {
            'direction': {
              'type': 'string',
              'enum': ['back', 'forward', 'reload'],
              'description': 'Which history navigation to perform.',
            },
          },
          'required': ['direction'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_close',
        'description': 'Close the built-in browser pane.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_fill',
        'description':
            'Type a value into a form field, identified by "ref" (from browser_snapshot) or a CSS "selector". Requires user approval. Password values are redacted in the approval prompt.',
        'parameters': {
          'type': 'object',
          'properties': {
            'ref': {
              'type': 'integer',
              'description': 'Element ref from browser_snapshot.',
            },
            'selector': {
              'type': 'string',
              'description': 'CSS selector (alternative to ref).',
            },
            'value': {'type': 'string', 'description': 'The text to enter.'},
            'reason': {
              'type': 'string',
              'description': 'Why this field is being filled.',
            },
          },
          'required': ['value'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_click',
        'description':
            'Click an element identified by "ref" (from browser_snapshot) or a CSS "selector". May navigate or change page state. Requires user approval. Use only refs from the latest browser_snapshot; if you need to submit a form after filling a field, prefer browser_submit instead of guessing a submit button ref.',
        'parameters': {
          'type': 'object',
          'properties': {
            'ref': {
              'type': 'integer',
              'description': 'Element ref from browser_snapshot.',
            },
            'selector': {
              'type': 'string',
              'description': 'CSS selector (alternative to ref).',
            },
            'reason': {
              'type': 'string',
              'description': 'Why this element is being clicked.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_submit',
        'description':
            'Submit a form. Optionally provide a CSS "selector" for a field/button inside the target form; otherwise the first form is submitted. Requires user approval. Prefer this after browser_fill for searches and forms instead of guessing a submit button ref.',
        'parameters': {
          'type': 'object',
          'properties': {
            'selector': {
              'type': 'string',
              'description': 'Optional CSS selector inside the target form.',
            },
            'reason': {
              'type': 'string',
              'description': 'Why the form is being submitted.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_eval',
        'description':
            'Run JavaScript in the current page and return its result (the body should "return" a JSON-serializable value). Use for advanced scraping when snapshot/content are insufficient. Requires user approval.',
        'parameters': {
          'type': 'object',
          'properties': {
            'script': {
              'type': 'string',
              'description':
                  'JavaScript body; use "return <value>" to return data.',
            },
            'reason': {
              'type': 'string',
              'description': 'Why this script needs to run.',
            },
          },
          'required': ['script'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browser_save_data',
        'description':
            'Save extracted data to a file. Defaults to Caverno application storage; set destination to downloads or documents only when the user explicitly requested that location. Requires user approval.',
        'parameters': {
          'type': 'object',
          'properties': {
            'filename': {
              'type': 'string',
              'description': 'File name, e.g. "usage.json".',
            },
            'data': {
              'type': 'string',
              'description': 'The file content (typically a JSON string).',
            },
            'format': {
              'type': 'string',
              'description': 'File extension to enforce (default "json").',
            },
            'destination': {
              'type': 'string',
              'enum': ['app', 'downloads', 'documents'],
              'description':
                  'Optional save location. Use "app" by default. Use "downloads" or "documents" only when the user explicitly asks for that folder.',
            },
            'reason': {'type': 'string', 'description': 'What is being saved.'},
          },
          'required': ['filename', 'data'],
        },
      },
    },
  ];

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

  static List<Map<String, dynamic>> get _computerUseTools => [
    {
      'type': 'function',
      'function': {
        'name': 'computer_get_permissions',
        'description':
            'Check macOS Accessibility, Screen Recording, and system audio recording availability for computer-use tools.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_request_permissions',
        'description':
            'Ask macOS to open prompts for Accessibility and/or Screen Recording permissions required by computer-use tools.',
        'parameters': {
          'type': 'object',
          'properties': {
            'accessibility': {
              'type': 'boolean',
              'description': 'Request Accessibility permission.',
            },
            'screen_capture': {
              'type': 'boolean',
              'description': 'Request Screen Recording permission.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_open_system_settings',
        'description':
            'Open the relevant macOS Privacy & Security pane for granting Accessibility or Screen Recording permissions. The user must still grant access manually.',
        'parameters': {
          'type': 'object',
          'properties': {
            'section': {
              'type': 'string',
              'enum': ['accessibility', 'screen_recording', 'privacy'],
              'description':
                  'System Settings section to open. Use screen_recording for Screen & System Audio Recording.',
            },
          },
          'required': ['section'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_vision_observe',
        'description':
            'Observe the macOS desktop for a vision LLM loop. Returns permission status, display inventory, optional visible-window metadata, one display or window screenshot as image content, coordinate guidance, and the approved next computer-use tool surface. This tool is read-only.',
        'parameters': {
          'type': 'object',
          'properties': {
            'target': {
              'type': 'string',
              'enum': ['display', 'window', 'front_window'],
              'description':
                  'Observation target. Use window with window_id for a known window, front_window for the first visible non-Caverno window, or display for the full display.',
            },
            'window_id': {
              'type': 'integer',
              'description':
                  'Window ID from computer_list_windows. Required when target is window.',
            },
            'display_id': {
              'type': 'integer',
              'description':
                  'Optional CGDirectDisplayID from computer_list_displays. Used when target is display.',
            },
            'max_width': {
              'type': 'integer',
              'description':
                  'Optional maximum PNG width to reduce tokens. Defaults to 900.',
            },
            'include_windows': {
              'type': 'boolean',
              'description':
                  'Include visible-window metadata. Defaults to true.',
            },
            'space_scope': {
              'type': 'string',
              'enum': ['active_space', 'all_spaces'],
              'description':
                  'macOS Spaces scope for window metadata. Use all_spaces when the target app may be on another desktop; input still requires observing the active Space first.',
            },
            'include_displays': {
              'type': 'boolean',
              'description':
                  'Include display inventory metadata. Defaults to true.',
            },
            'include_accessibility': {
              'type': 'boolean',
              'description':
                  'Include accessibility-derived candidate element metadata for window observations. Defaults to true.',
            },
            'max_candidate_elements': {
              'type': 'integer',
              'description':
                  'Maximum candidate elements to expose in elementGrounding. Defaults to 12.',
            },
            'max_accessibility_elements': {
              'type': 'integer',
              'description':
                  'Maximum accessibility elements to read before selecting candidates. Defaults to 50.',
            },
            'max_accessibility_depth': {
              'type': 'integer',
              'description':
                  'Maximum accessibility tree depth to read for candidate selection. Defaults to 4.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_accessibility_snapshot',
        'description':
            'Read a bounded macOS Accessibility snapshot for the front window or a selected window. Returns roles, safe labels, frames, enabled/focused state, child counts, and redaction metadata without taking any desktop action.',
        'parameters': {
          'type': 'object',
          'properties': {
            'target': {
              'type': 'string',
              'enum': ['front_window', 'window'],
              'description':
                  'Snapshot target. Use front_window for the first visible non-Caverno window or window with window_id for a known window.',
            },
            'window_id': {
              'type': 'integer',
              'description':
                  'Window ID from computer_list_windows. Required when target is window.',
            },
            'max_depth': {
              'type': 'integer',
              'description':
                  'Maximum accessibility tree depth to traverse. Defaults to 4 and is capped by the helper.',
            },
            'max_elements': {
              'type': 'integer',
              'description':
                  'Maximum number of elements to return. Defaults to 80 and is capped by the helper.',
            },
            'label_max_characters': {
              'type': 'integer',
              'description':
                  'Maximum safe label length per element before truncation. Defaults to 120.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_list_displays',
        'description':
            'List macOS displays with display IDs, indexes, names, point bounds, pixel sizes, and main-display status. Use this before selecting a non-main display for screenshots or desktop actions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'display_id': {
              'type': 'integer',
              'description':
                  'Optional CGDirectDisplayID to validate a selected display.',
            },
            'display_index': {
              'type': 'integer',
              'description':
                  'Optional zero-based display index to validate a selected display.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_screenshot',
        'description':
            'Capture a macOS display screenshot for visual inspection. Use returned screenshot pixel coordinates for computer input tools.',
        'parameters': {
          'type': 'object',
          'properties': {
            'display_id': {
              'type': 'integer',
              'description':
                  'Optional CGDirectDisplayID from computer_list_displays. Defaults to the main display.',
            },
            'max_width': {
              'type': 'integer',
              'description': 'Optional maximum PNG width to reduce tokens.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_list_windows',
        'description':
            'List macOS application windows with window IDs, app names, titles, bounds, and macOS Spaces visibility status. Prefer this before focusing or capturing a specific app window.',
        'parameters': {
          'type': 'object',
          'properties': {
            'include_current_app': {
              'type': 'boolean',
              'description':
                  'Include Caverno windows in the result. Defaults to false.',
            },
            'max_windows': {
              'type': 'integer',
              'description': 'Maximum number of windows to return.',
            },
            'space_scope': {
              'type': 'string',
              'enum': ['active_space', 'all_spaces'],
              'description':
                  'Use active_space for the current macOS Space, or all_spaces for best-effort discovery across Spaces.',
            },
            'include_hidden': {
              'type': 'boolean',
              'description':
                  'Include hidden, minimized, or non-active-Space windows when supported by macOS. Defaults to true for all_spaces.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_focus_window',
        'description':
            'Bring a specific macOS window to the foreground by window_id. Optionally focus an element_id from the latest elementGrounding candidates. Requires Accessibility permission.',
        'parameters': {
          'type': 'object',
          'properties': {
            'window_id': {
              'type': 'integer',
              'description':
                  'Window ID from computer_list_windows or computer_screenshot_window.',
            },
            ..._computerElementTargetProperties,
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['window_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_screenshot_window',
        'description':
            'Capture a specific macOS window screenshot. Use returned window pixel coordinates and window_id for follow-up computer input tools.',
        'parameters': {
          'type': 'object',
          'properties': {
            'window_id': {
              'type': 'integer',
              'description': 'Window ID from computer_list_windows.',
            },
            'max_width': {
              'type': 'integer',
              'description': 'Optional maximum PNG width to reduce tokens.',
            },
          },
          'required': ['window_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_move_mouse',
        'description':
            'Move the macOS pointer to screenshot pixel coordinates.',
        'parameters': _computerPointParameters(required: ['x', 'y']),
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_click',
        'description':
            'Click an element_id from the latest elementGrounding candidates, or fall back to screenshot pixel coordinates. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          ..._computerPointParameters(),
          'properties': {
            ..._computerPointProperties,
            ..._computerElementTargetProperties,
            'button': {
              'type': 'string',
              'enum': ['left', 'right', 'middle'],
              'description': 'Mouse button. Defaults to left.',
            },
            'click_count': {
              'type': 'integer',
              'description': 'Number of clicks, from 1 to 3.',
            },
            'reason': {
              'type': 'string',
              'description': 'Why this click is needed.',
            },
            ..._computerActionTargetMetadataProperties,
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_drag',
        'description':
            'Drag from one screenshot pixel coordinate to another. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          'type': 'object',
          'properties': {
            ..._computerDisplayProperties,
            'from_x': {'type': 'number'},
            'from_y': {'type': 'number'},
            'to_x': {'type': 'number'},
            'to_y': {'type': 'number'},
            'duration_ms': {
              'type': 'integer',
              'description': 'Drag duration in milliseconds.',
            },
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['from_x', 'from_y', 'to_x', 'to_y'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_scroll',
        'description':
            'Scroll the active macOS target, optionally after moving to screenshot pixel coordinates.',
        'parameters': {
          'type': 'object',
          'properties': {
            ..._computerPointProperties,
            'delta_x': {'type': 'integer'},
            'delta_y': {
              'type': 'integer',
              'description': 'Positive scrolls up, negative scrolls down.',
            },
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_type_text',
        'description':
            'Type text into an element_id from the latest elementGrounding candidates, or into the currently focused macOS UI element when no element target is provided. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
            ..._computerWindowElementTargetProperties,
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['text'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_press_key',
        'description':
            'Press a keyboard key, optionally with modifiers such as command, shift, option, or control. Use computer_switch_space for macOS Spaces switching.',
        'parameters': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string'},
            'modifiers': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['key'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_switch_space',
        'description':
            'Switch to an adjacent macOS Space with Control-Left or Control-Right. Requires explicit user approval and must be followed by computer_vision_observe before pointer or keyboard input.',
        'parameters': {
          'type': 'object',
          'properties': {
            'direction': {
              'type': 'string',
              'enum': ['next', 'previous'],
              'description':
                  'Use next for Control-Right, or previous for Control-Left.',
            },
            'reason': {
              'type': 'string',
              'description': 'Why switching Spaces is needed.',
            },
          },
          'required': ['direction'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_start_system_audio_recording',
        'description':
            'Start recording macOS system audio to a CAF file via ScreenCaptureKit. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          'type': 'object',
          'properties': {
            'output_path': {
              'type': 'string',
              'description': 'Optional absolute CAF output path.',
            },
            'exclude_current_process_audio': {
              'type': 'boolean',
              'description':
                  'Exclude Caverno audio from the recording. Defaults to true.',
            },
            'reason': {'type': 'string'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_stop_system_audio_recording',
        'description':
            'Stop the active macOS system audio recording and return the output file path.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
  ];

  static Map<String, dynamic> _computerPointParameters({
    List<String> required = const [],
  }) {
    return {
      'type': 'object',
      'properties': _computerPointProperties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  static Map<String, dynamic> get _computerPointProperties => {
    ..._computerDisplayProperties,
    'x': {
      'type': 'number',
      'description': 'X coordinate in screenshot pixels from the top-left.',
    },
    'y': {
      'type': 'number',
      'description': 'Y coordinate in screenshot pixels from the top-left.',
    },
  };

  static Map<String, dynamic> get _computerDisplayProperties => {
    'window_id': {
      'type': 'integer',
      'description':
          'Optional window ID from computer_list_windows or computer_screenshot_window. When set, x/y are interpreted as window screenshot pixels.',
    },
    'display_id': {
      'type': 'integer',
      'description':
          'Optional display ID from computer_list_displays, computer_vision_observe, or computer_screenshot.',
    },
    'source_width': {
      'type': 'number',
      'description': 'Width of the screenshot used to choose coordinates.',
    },
    'source_height': {
      'type': 'number',
      'description': 'Height of the screenshot used to choose coordinates.',
    },
    'coordinate_space': {
      'type': 'string',
      'description':
          'Coordinate space from computer_vision_observe, such as window_pixels or display_pixels.',
    },
    'vision_observation_id': {
      'type': 'string',
      'description':
          'Observation ID from the latest computer_vision_observe result used to choose this action.',
    },
  };

  static Map<String, dynamic> get _computerElementTargetProperties => {
    'element_id': {
      'type': 'string',
      'description':
          'Optional execution target elementId from the latest computer_vision_observe elementGrounding candidateElements.',
    },
    'max_accessibility_elements': {
      'type': 'integer',
      'description':
          'Maximum accessibility elements to scan while resolving element_id. Defaults to 80.',
    },
    'max_accessibility_depth': {
      'type': 'integer',
      'description':
          'Maximum accessibility tree depth to scan while resolving element_id. Defaults to 4.',
    },
  };

  static Map<String, dynamic> get _computerWindowElementTargetProperties => {
    'window_id': {
      'type': 'integer',
      'description':
          'Window ID from the latest computer_vision_observe or computer_list_windows result. Required when element_id is provided.',
    },
    ..._computerElementTargetProperties,
  };

  static Map<String, dynamic> get _computerActionTargetMetadataProperties => {
    'target': {
      'type': 'object',
      'description':
          'Optional visible UI target metadata used only for Caverno approval. Mark public posting, sending, submitting, or publishing controls with risk=public_action. Mark secure fields, credential prompts, payment flows, and destructive controls with their matching risk.',
      'properties': {
        'label': {
          'type': 'string',
          'description': 'Visible label or accessible name of the target.',
        },
        'role': {
          'type': 'string',
          'description': 'Visible or accessibility role of the target.',
        },
        'appName': {
          'type': 'string',
          'description':
              'Visible application name from the latest observation or window list.',
        },
        'appBundleId': {
          'type': 'string',
          'description':
              'Application bundle identifier when available from the latest observation or window list.',
        },
        'windowTitle': {
          'type': 'string',
          'description':
              'Window title from the latest observation or window list.',
        },
        'windowId': {
          'type': 'integer',
          'description':
              'Window ID from the latest observation or window list.',
        },
        'elementId': {
          'type': 'string',
          'description':
              'Optional elementId from the latest computer_vision_observe elementGrounding candidates.',
        },
        'action': {
          'type': 'string',
          'description': 'Intended action, such as click, submit, or publish.',
        },
        'risk': {
          'type': 'string',
          'enum': [
            'input',
            'public_action',
            'secure_field',
            'credential',
            'payment',
            'destructive',
            'sensitive',
            'unknown',
          ],
          'description':
              'Use public_action for controls that post, send, submit, publish, or otherwise change external state. Use secure_field, credential, payment, or destructive for targets that should be blocked or manually handled.',
        },
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
  // Built-in tool: ssh_connect / ssh_execute_command / ssh_disconnect
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _sshConnectTool => {
    'type': 'function',
    'function': {
      'name': 'ssh_connect',
      'description':
          "Open an interactive SSH session to a remote host. The user will "
          "see a dialog to confirm or edit the connection details and enter "
          "the password (pre-filled if previously saved for this host). "
          "Keeps the session alive for subsequent ssh_execute_command calls "
          "until ssh_disconnect is called. Use this when the user asks to "
          "connect to a server via SSH.",
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                "Hostname or IP of the SSH server, e.g. '192.168.1.10' or "
                "'example.com'.",
          },
          'port': {
            'type': 'integer',
            'description': 'SSH port. Defaults to 22 when omitted.',
          },
          'username': {
            'type': 'string',
            'description':
                'SSH username. Optional — if omitted, the confirmation '
                'dialog will ask the user to enter it.',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _sshExecuteCommandTool => {
    'type': 'function',
    'function': {
      'name': 'ssh_execute_command',
      'description':
          "Execute a shell command on the currently active SSH session. "
          "Requires ssh_connect to have succeeded first. Each command is "
          "shown to the user in a confirmation dialog and must be approved "
          "before it runs. Returns stdout, stderr, and the exit code.",
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Exact shell command to run on the remote server.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown to the user in the '
                'confirmation dialog.',
          },
        },
        'required': ['command'],
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

  static Map<String, dynamic> get _localExecuteCommandTool => {
    'type': 'function',
    'function': {
      'name': 'local_execute_command',
      'description':
          'Execute an exact shell command or multiline shell script inside the current project. Batch related commands such as format, analyze, and test into one call, using && between independent commands when portable early exit is required. On POSIX, unhandled failures in newline-separated foreground scripts also stop execution. Read-only commands may run immediately; commands that can modify files or state require user approval. Use git_execute_command for git write operations such as add, commit, checkout, merge, rebase, branch changes, worktree changes, tag creation, or reset. Prefer file tools for file discovery and reading; prefer absolute paths or working_directory over shell-only features such as pipes, redirection, environment variables, or command substitution. Do not use shell commands (cat, stty, screen, xxd, etc.) on serial port devices such as /dev/tty.*, /dev/cu.*, or COM ports — they block on serial I/O and are platform-fragile; use the dedicated serial_* tools (serial_list_ports, serial_open, serial_read, serial_decode, serial_write, serial_close) instead.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description':
                'Exact native-shell command or multiline script. Use && between independent commands for portable early exit; foreground POSIX newline scripts also stop at the first unhandled failure.',
          },
          'background': {
            'type': 'boolean',
            'description':
                'Run the command in the background and return a job id without '
                'waiting for completion.',
          },
          'label': {
            'type': 'string',
            'description':
                'Optional short label for background runs (required when '
                'background=true).',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Absolute or project-relative working directory. Optional when a coding project is selected.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog for non-read-only commands.',
          },
        },
        'required': ['command'],
      },
    },
  };

  static Map<String, dynamic> get _processStartTool => {
    'type': 'function',
    'function': {
      'name': 'process_start',
      'description':
          'Start a long-running local shell command as a background process and return a job_id immediately. Use this instead of local_execute_command for builds, releases, deploys, uploads, long tests, or commands expected to run longer than about one minute. Use git_execute_command, not process_start, for git write operations. Pair this with process_list/process_status/process_tail/process_wait to observe completion. Starting a process may modify files or external state and requires the same approval as local_execute_command.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Exact shell command to start.',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Absolute or project-relative working directory. Optional when a coding project is selected.',
          },
          'label': {
            'type': 'string',
            'description':
                'Short label for the background job, such as "iOS release".',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['command'],
      },
    },
  };

  static Map<String, dynamic> get _processStatusTool => {
    'type': 'function',
    'function': {
      'name': 'process_status',
      'description':
          'Check the status of a background process started with process_start or background local_execute_command. This is read-only and returns running/exited state, PID, exit code when available, elapsed time, and recent output tails.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
          'tail_chars': {
            'type': 'integer',
            'description':
                'Optional number of stdout/stderr tail characters to include.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processTailTool => {
    'type': 'function',
    'function': {
      'name': 'process_tail',
      'description':
          'Read stdout/stderr tails for a background process started with '
          'process_start or background local_execute_command. This is read-only.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
          'max_chars': {
            'type': 'integer',
            'description': 'Maximum tail characters per stream.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processWaitTool => {
    'type': 'function',
    'function': {
      'name': 'process_wait',
      'description':
          'Wait briefly for a background process and return its current status. Keep '
          'wait_ms short and call process_status/process_tail again as needed '
          'instead of starting the command again. Use the returned status and '
          'output tails to report concise progress before continuing to wait.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
          'wait_ms': {
            'type': 'integer',
            'description': 'Milliseconds to wait, capped by the app.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processCancelTool => {
    'type': 'function',
    'function': {
      'name': 'process_cancel',
      'description':
          'Request cancellation of a running background process by job_id. This can '
          'stop a local command and may require user approval depending on '
          'context.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processListTool => {
    'type': 'function',
    'function': {
      'name': 'process_list',
      'description':
          'List monitored background processes started with process_start or '
          'background local_execute_command and return current status snapshots, '
          'including optional completed jobs.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_ids': {
            'type': 'array',
            'description': 'Optional list of job IDs to filter results.',
            'items': {'type': 'string'},
          },
          'include_finished': {
            'type': 'boolean',
            'description':
                'Whether to include exited/finished jobs. Defaults to true.',
          },
          'refresh': {
            'type': 'boolean',
            'description':
                'Refresh statuses before listing. Defaults to false.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of jobs to return.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _runTestsTool => {
    'type': 'function',
    'function': {
      'name': 'run_tests',
      'description':
          'Run scoped Dart or Flutter tests in the selected coding project. Use this only with a specific test file or directory. For full suites such as flutter test, fvm flutter test, dart test, or fvm dart test with no specific test path, use process_start or local_execute_command with background=true so the app can monitor the long-running command.',
      'parameters': {
        'type': 'object',
        'properties': {
          'test_path': {
            'type': 'string',
            'description':
                'Optional test file or directory to run. Paths may be project-relative, working-directory-relative, or absolute, but must stay inside the selected project.',
          },
          'runner': {
            'type': 'string',
            'enum': ['auto', 'flutter', 'dart'],
            'description':
                'Test runner to use. auto uses Flutter and prefixes fvm when the project has FVM metadata.',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Optional absolute or project-relative package directory. Defaults to the selected project root.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog when approval is required.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _sshDisconnectTool => {
    'type': 'function',
    'function': {
      'name': 'ssh_disconnect',
      'description':
          'Close the currently active SSH session. Safe to call even if '
          'nothing is connected.',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  };

  // ---------------------------------------------------------------------------
  // BLE tool execution
  // ---------------------------------------------------------------------------

  Future<McpToolResult> _executeBleToolCall(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final ble = bleService!;

    try {
      switch (name) {
        case 'ble_start_scan':
          final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 10).clamp(
            1,
            60,
          );
          final serviceUuids = (arguments['service_uuids'] as List?)
              ?.cast<String>();
          await ble.startScan(
            timeout: Duration(seconds: timeout),
            serviceUuids: serviceUuids,
          );
          return McpToolResult(
            toolName: name,
            result:
                'Scan started (${timeout}s timeout). '
                'Use ble_get_scan_results to see discovered devices.',
            isSuccess: true,
          );

        case 'ble_stop_scan':
          await ble.stopScan();
          return McpToolResult(
            toolName: name,
            result:
                'Scan stopped. ${ble.getScanResults().length} devices found.',
            isSuccess: true,
          );

        case 'ble_get_scan_results':
          final sortBy = arguments['sort_by'] as String?;
          final results = ble.getScanResults(sortBy: sortBy);
          if (results.isEmpty) {
            return McpToolResult(
              toolName: name,
              result: 'No devices found. Try ble_start_scan first.',
              isSuccess: true,
            );
          }
          final buf = StringBuffer();
          buf.writeln('Found ${results.length} device(s):');
          for (final d in results) {
            buf.writeln(
              '- device_id: ${d.peripheral.uuid}  '
              'name: ${d.name ?? "(unknown)"}  '
              'rssi: ${d.rssi} dBm  '
              'services: ${d.serviceUuids.isEmpty ? "none" : d.serviceUuids.join(", ")}',
            );
          }
          return McpToolResult(
            toolName: name,
            result: buf.toString(),
            isSuccess: true,
          );

        case 'ble_connect':
          // Handled by ChatNotifier for user confirmation.
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage:
                'ble_connect must be handled by ChatNotifier (internal error)',
          );

        case 'ble_disconnect':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty) {
            return _missingParam(name, 'device_id');
          }
          await ble.disconnect(deviceId);
          return McpToolResult(
            toolName: name,
            result: 'Disconnected from $deviceId',
            isSuccess: true,
          );

        case 'ble_discover_services':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty) {
            return _missingParam(name, 'device_id');
          }
          final services = await ble.discoverServices(deviceId);
          final result = jsonEncode(services);
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'ble_read_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final charUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'hex';
          if (deviceId.isEmpty || serviceUuid.isEmpty || charUuid.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid',
            );
          }
          final value = await ble.readCharacteristic(
            deviceId,
            serviceUuid,
            charUuid,
          );
          final encoded = BleService.encodeValue(value, encoding);

          // Include notification buffer info if subscribed.
          final buffer = ble.getNotificationBuffer(
            deviceId,
            serviceUuid,
            charUuid,
          );
          final buf = StringBuffer();
          buf.writeln('value ($encoding): $encoded');
          if (buffer.isNotEmpty) {
            buf.writeln('notification_buffer (${buffer.length} entries):');
            for (final entry in buffer) {
              buf.writeln(
                '  ${entry.timestamp.toIso8601String()}: '
                '${BleService.encodeValue(entry.value, encoding)}',
              );
            }
          }
          return McpToolResult(
            toolName: name,
            result: buf.toString(),
            isSuccess: true,
          );

        case 'ble_write_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final charUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          final rawValue = (arguments['value'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'hex';
          final writeTypeStr =
              (arguments['write_type'] as String?) ?? 'withResponse';
          if (deviceId.isEmpty ||
              serviceUuid.isEmpty ||
              charUuid.isEmpty ||
              rawValue.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid, value',
            );
          }
          final writeType = writeTypeStr == 'withoutResponse'
              ? GATTCharacteristicWriteType.withoutResponse
              : GATTCharacteristicWriteType.withResponse;
          final valueBytes = _decodeValueForWrite(rawValue, encoding);
          await ble.writeCharacteristic(
            deviceId,
            serviceUuid,
            charUuid,
            valueBytes,
            type: writeType,
          );
          return McpToolResult(
            toolName: name,
            result: 'Written ${valueBytes.length} bytes to $charUuid',
            isSuccess: true,
          );

        case 'ble_subscribe_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final charUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty || serviceUuid.isEmpty || charUuid.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid',
            );
          }
          await ble.subscribeCharacteristic(deviceId, serviceUuid, charUuid);
          return McpToolResult(
            toolName: name,
            result:
                'Subscribed to notifications on $charUuid. '
                'Use ble_read_characteristic to get latest values.',
            isSuccess: true,
          );

        case 'ble_unsubscribe_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final charUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty || serviceUuid.isEmpty || charUuid.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid',
            );
          }
          await ble.unsubscribeCharacteristic(deviceId, serviceUuid, charUuid);
          return McpToolResult(
            toolName: name,
            result: 'Unsubscribed from $charUuid',
            isSuccess: true,
          );

        case 'ble_get_connection_state':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty) {
            return _missingParam(name, 'device_id');
          }
          final state = ble.getConnectionState(deviceId);
          return McpToolResult(
            toolName: name,
            result: 'Device $deviceId: $state',
            isSuccess: true,
          );

        case 'ble_start_advertising':
          final localName = arguments['local_name'] as String?;
          final serviceUuids = (arguments['service_uuids'] as List?)
              ?.cast<String>();
          await ble.startAdvertising(
            localName: localName,
            serviceUuids: serviceUuids,
          );
          return McpToolResult(
            toolName: name,
            result: 'Advertising started',
            isSuccess: true,
          );

        case 'ble_stop_advertising':
          await ble.stopAdvertising();
          return McpToolResult(
            toolName: name,
            result: 'Advertising stopped',
            isSuccess: true,
          );

        case 'ble_add_service':
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final chars =
              (arguments['characteristics'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          if (serviceUuid.isEmpty || chars.isEmpty) {
            return _missingParam(name, 'service_uuid, characteristics');
          }
          await ble.addService(
            serviceUuid: serviceUuid,
            characteristics: chars,
          );
          return McpToolResult(
            toolName: name,
            result:
                'Service $serviceUuid added with ${chars.length} characteristic(s)',
            isSuccess: true,
          );

        case 'ble_update_characteristic':
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final charUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          final rawValue = (arguments['value'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'hex';
          if (serviceUuid.isEmpty || charUuid.isEmpty || rawValue.isEmpty) {
            return _missingParam(
              name,
              'service_uuid, characteristic_uuid, value',
            );
          }
          final bytes = _decodeValueForWrite(rawValue, encoding);
          await ble.updateCharacteristic(serviceUuid, charUuid, bytes);
          return McpToolResult(
            toolName: name,
            result: 'Characteristic $charUuid updated and subscribers notified',
            isSuccess: true,
          );

        case 'ble_get_peripheral_state':
          final state = ble.getPeripheralState();
          return McpToolResult(
            toolName: name,
            result: jsonEncode(state),
            isSuccess: true,
          );

        default:
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Unknown BLE tool: $name',
          );
      }
    } catch (e) {
      appLog('[McpToolService] BLE tool error ($name): $e');
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // WiFi tool execution
  // ---------------------------------------------------------------------------

  Future<McpToolResult> _executeWifiToolCall(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final wifi = wifiService!;
    try {
      switch (name) {
        case 'wifi_scan':
          final result = await wifi.startScan();
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'wifi_get_scan_results':
          final sortBy = arguments['sort_by'] as String?;
          final result = wifi.getScanResults(sortBy: sortBy);
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'wifi_get_connection_info':
          final result = await wifi.getConnectionInfo();
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        default:
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Unknown WiFi tool: $name',
          );
      }
    } catch (e) {
      appLog('[McpToolService] WiFi tool error ($name): $e');
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // LAN scan tool execution
  // ---------------------------------------------------------------------------

  Future<McpToolResult> _executeLanScanToolCall(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final lanScan = lanScanService!;
    try {
      switch (name) {
        case 'lan_scan':
          final subnet = (arguments['subnet'] as String?)?.trim();
          final ipVersion = (arguments['ip_version'] as String?)?.trim();
          final timeout = (arguments['timeout'] as num?)?.toInt() ?? 1000;
          final ports = (arguments['ports'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList();
          final result = await lanScan.startScan(
            subnet: subnet,
            ipVersion: ipVersion,
            timeoutMs: timeout,
            ports: ports,
          );
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'lan_get_scan_results':
          final sortBy = arguments['sort_by'] as String?;
          final result = lanScan.getScanResults(sortBy: sortBy);
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        default:
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Unknown LAN scan tool: $name',
          );
      }
    } catch (e) {
      appLog('[McpToolService] LAN scan tool error ($name): $e');
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Serial port tool execution
  //
  // serial_open is handled in ChatNotifier (it requires user approval), so it
  // is intentionally not executed here.
  // ---------------------------------------------------------------------------

  Future<McpToolResult> _executeSerialPortToolCall(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final serial = serialPortService!;
    try {
      switch (name) {
        case 'serial_list_ports':
          final result = serial.listPorts();
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'serial_read':
          final port = (arguments['port'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'utf8';
          final maxBytes = (arguments['max_bytes'] as num?)?.toInt();
          final clear = (arguments['clear'] as bool?) ?? true;
          final frameDelimiter = arguments['frame_delimiter'] as String?;
          final frameLength = (arguments['frame_length'] as num?)?.toInt();
          final maxFrames = (arguments['max_frames'] as num?)?.toInt() ?? 200;
          final includeStats = (arguments['include_stats'] as bool?) ?? false;
          final result = serial.read(
            port,
            encoding: encoding,
            maxBytes: maxBytes,
            clear: clear,
            frameDelimiterHex: frameDelimiter,
            frameLength: frameLength,
            maxFrames: maxFrames,
            includeStats: includeStats,
          );
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'serial_decode':
          final dataHex = arguments['data'] as String?;
          final port = (arguments['port'] as String?)?.trim();
          final format = arguments['format'] as String? ?? '';
          final fields = (arguments['fields'] as List?)
              ?.map((e) => e.toString())
              .toList();
          final consume = (arguments['consume'] as bool?) ?? false;
          final result = serial.decode(
            dataHex: dataHex,
            port: port,
            format: format,
            fields: fields,
            consume: consume,
          );
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'serial_write':
          final port = (arguments['port'] as String?)?.trim() ?? '';
          final data = arguments['data'] as String? ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'utf8';
          final result = await serial.write(port, data, encoding: encoding);
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        case 'serial_close':
          final port = (arguments['port'] as String?)?.trim() ?? '';
          final result = await serial.close(port);
          return McpToolResult(toolName: name, result: result, isSuccess: true);

        default:
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage:
                'Serial tool $name must be invoked with user '
                'approval and cannot be executed directly.',
          );
      }
    } catch (e) {
      appLog('[McpToolService] Serial tool error ($name): $e');
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  static McpToolResult _missingParam(String toolName, String params) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: '$params required',
    );
  }

  static Uint8List _decodeValueForWrite(String value, String encoding) {
    return switch (encoding) {
      'utf8' => Uint8List.fromList(utf8.encode(value)),
      'base64' => base64Decode(value),
      _ => _hexDecodeValue(value),
    };
  }

  static Uint8List _hexDecodeValue(String hex) {
    final clean = hex.replaceAll(_hexSeparatorChars, '');
    final bytes = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

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

class _RemoteToolBinding {
  const _RemoteToolBinding({
    required this.client,
    required this.remoteToolName,
  });

  final McpClientBase client;
  final String remoteToolName;
}

class _McpConnectionResult {
  const _McpConnectionResult({
    required this.identifier,
    required this.client,
    this.tools = const [],
    this.error,
  });

  final String identifier;
  final McpClientBase client;
  final List<McpTool> tools;
  final String? error;

  bool get isSuccess => error == null;

  McpConnectionStatus get status =>
      isSuccess ? McpConnectionStatus.connected : McpConnectionStatus.error;
}

class _ScoredMemoryMatch {
  _ScoredMemoryMatch({required this.memory, required this.score});

  final MemoryEntry memory;
  final double score;
}
