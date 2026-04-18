import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    show GATTCharacteristicWriteType;

import '../../../../core/services/ble_service.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/lan_scan_service.dart';
import '../../../../core/services/wifi_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/session_memory.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../repositories/chat_memory_repository.dart';
import '../repositories/conversation_repository.dart';
import 'ble_tools.dart';
import 'filesystem_tools.dart';
import 'git_tools.dart';
import 'lan_scan_tools.dart';
import 'local_shell_tools.dart';
import 'mcp_client.dart';
import 'mcp_stdio_client.dart';
import 'network_tools.dart';
import 'searxng_client.dart';
import 'wifi_tools.dart';

class FileRollbackPreview {
  const FileRollbackPreview({
    required this.path,
    required this.preview,
    required this.summary,
  });

  final String path;
  final String preview;
  final String summary;
}

/// MCP tool management service.
///
/// Fetches tools dynamically from an MCP server and executes them.
/// Falls back to SearXNG when the MCP server is unavailable.
class McpToolService {
  static const _maxToolNameLength = 64;
  static const Set<String> _reservedToolNames = {
    'get_current_datetime',
    'search_past_conversations',
    'recall_memory',
    'ping',
    'whois_lookup',
    'dns_lookup',
    'port_check',
    'ssl_certificate',
    'http_status',
    'http_get',
    'http_head',
    'http_post',
    'http_put',
    'http_patch',
    'http_delete',
    'traceroute',
    'list_directory',
    'read_file',
    'write_file',
    'edit_file',
    'rollback_last_file_change',
    'find_files',
    'search_files',
    'local_execute_command',
    'git_execute_command',
    'ssh_connect',
    'ssh_execute_command',
    'ssh_disconnect',
    ...BleTools.allToolNames,
    ...WifiTools.allToolNames,
    ...LanScanTools.allToolNames,
  };

  McpToolService({
    this.mcpClients = const [],
    this.searxngClient,
    this.conversationRepository,
    this.memoryRepository,
    this.sshService,
    this.bleService,
    this.wifiService,
    this.lanScanService,
    this.disabledBuiltInTools = const {},
  });

  final List<McpClientBase> mcpClients;
  final SearxngClient? searxngClient;
  final ConversationRepository? conversationRepository;
  final ChatMemoryRepository? memoryRepository;
  final SshService? sshService;
  final BleService? bleService;
  final WifiService? wifiService;
  final LanScanService? lanScanService;
  final Set<String> disabledBuiltInTools;

  List<McpToolEntity> _cachedTools = [];
  final Map<String, _RemoteToolBinding> _remoteToolBindings = {};
  final List<_FileRollbackEntry> _fileRollbackStack = [];
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

  Future<_McpConnectionResult> _connectClient(McpClientBase client) async {
    try {
      final tools = await client.listTools();
      return _McpConnectionResult(
        identifier: client.identifier,
        client: client,
        tools: tools,
      );
    } catch (e, stackTrace) {
      appLog(
        '[McpToolService] Connection failed for ${client.identifier}: ${e.runtimeType}: $e',
      );
      appLog('[McpToolService] stackTrace: $stackTrace');
      return _McpConnectionResult(
        identifier: client.identifier,
        client: client,
        error: e.toString(),
      );
    }
  }

  void _rebuildRemoteToolCache(List<_McpConnectionResult> results) {
    _cachedTools = [];
    _remoteToolBindings.clear();

    final successfulResults = results
        .where((result) => result.isSuccess)
        .toList();
    if (successfulResults.isEmpty) {
      return;
    }

    final nameCounts = <String, int>{};
    for (final result in successfulResults) {
      for (final tool in result.tools) {
        nameCounts.update(tool.name, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final usedNames = {..._reservedToolNames};
    for (final result in successfulResults) {
      for (final tool in result.tools) {
        final exposedName = _buildExposedToolName(
          baseName: tool.name,
          url: result.identifier,
          usedNames: usedNames,
          duplicateCount: nameCounts[tool.name] ?? 1,
        );

        _cachedTools.add(
          McpToolEntity(
            name: exposedName,
            originalName: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema,
            sourceUrl: result.identifier,
          ),
        );
        _remoteToolBindings[exposedName] = _RemoteToolBinding(
          client: result.client,
          remoteToolName: tool.name,
        );
      }
    }
  }

  String _buildExposedToolName({
    required String baseName,
    required String url,
    required Set<String> usedNames,
    required int duplicateCount,
  }) {
    final serverKey = _buildServerKey(url);
    final shouldNamespace = duplicateCount > 1 || usedNames.contains(baseName);
    var candidate = shouldNamespace
        ? _buildNamespacedToolName(baseName: baseName, serverKey: serverKey)
        : _truncateToolName(baseName);
    var attempt = 2;

    while (!usedNames.add(candidate)) {
      candidate = _buildNamespacedToolName(
        baseName: baseName,
        serverKey: serverKey,
        attempt: attempt,
      );
      attempt += 1;
    }

    return candidate;
  }

  List<McpClientBase> _resolveClients({
    required List<String> targetUrls,
    required bool useOverrides,
  }) {
    if (useOverrides) {
      return targetUrls
          .map((url) => McpClient(baseUrl: url))
          .toList(growable: false);
    }

    final clientsById = <String, McpClientBase>{};
    for (final client in mcpClients) {
      clientsById.putIfAbsent(client.identifier.trim(), () => client);
    }

    return targetUrls
        .map((url) => clientsById[url] ?? McpClient(baseUrl: url))
        .toList(growable: false);
  }

  List<McpClientBase> _resolveClientsFromServers(
    List<McpServerConfig> servers,
  ) {
    final isDesktop = FilesystemTools.isDesktopPlatform;
    final clients = <McpClientBase>[];
    for (final server in servers) {
      if (!server.enabled || !server.isValid || server.isBlocked) {
        continue;
      }
      switch (server.type) {
        case McpServerType.http:
          clients.add(McpClient(baseUrl: server.normalizedUrl));
        case McpServerType.stdio:
          if (isDesktop) {
            clients.add(
              McpStdioClient(command: server.command.trim(), args: server.args),
            );
          }
      }
    }
    return clients;
  }

  String _buildNamespacedToolName({
    required String baseName,
    required String serverKey,
    int? attempt,
  }) {
    final suffix = attempt == null ? '__$serverKey' : '__${serverKey}_$attempt';
    final maxBaseLength = (_maxToolNameLength - suffix.length).clamp(1, 64);
    final truncatedBase = baseName.length <= maxBaseLength
        ? baseName
        : baseName.substring(0, maxBaseLength);
    return '$truncatedBase$suffix';
  }

  String _truncateToolName(String value) {
    if (value.length <= _maxToolNameLength) {
      return value;
    }
    return value.substring(0, _maxToolNameLength);
  }

  String _buildServerKey(String url) {
    final uri = Uri.tryParse(url);
    final rawValue = uri == null
        ? 'server'
        : [
            if (uri.host.isNotEmpty) uri.host else 'server',
            if (uri.hasPort) uri.port.toString(),
          ].join('_');
    final sanitized = rawValue.replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_');
    final collapsed = sanitized.replaceAll(RegExp(r'_+'), '_');
    final normalized = collapsed.replaceAll(RegExp(r'^_|_$'), '').toLowerCase();
    final shortBase = normalized.isEmpty
        ? 'server'
        : normalized.substring(
            0,
            normalized.length > 18 ? 18 : normalized.length,
          );
    return '${shortBase}_${_shortHash(url)}';
  }

  String _shortHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x3fffffff;
    }
    return hash.toRadixString(36).padLeft(6, '0');
  }

  /// Returns tool definitions for the LLM.
  ///
  /// Returns dynamically fetched tools when MCP is connected.
  /// Otherwise returns the fallback `web_search` tool for SearXNG.
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final toolDefinitions = <Map<String, dynamic>>[];

    _addIfEnabled(toolDefinitions, _currentDatetimeTool);

    // Built-in memory tools (always available).
    if (conversationRepository != null) {
      _addIfEnabled(toolDefinitions, _searchPastConversationsTool);
    }
    if (memoryRepository != null) {
      _addIfEnabled(toolDefinitions, _recallMemoryTool);
    }

    // Built-in network tools (always available).
    _addIfEnabled(toolDefinitions, _pingTool);
    _addIfEnabled(toolDefinitions, _whoisLookupTool);
    _addIfEnabled(toolDefinitions, _dnsLookupTool);
    _addIfEnabled(toolDefinitions, _portCheckTool);
    _addIfEnabled(toolDefinitions, _sslCertificateTool);
    _addIfEnabled(toolDefinitions, _httpStatusTool);
    _addIfEnabled(toolDefinitions, _httpGetTool);
    _addIfEnabled(toolDefinitions, _httpHeadTool);
    _addIfEnabled(toolDefinitions, _httpPostTool);
    _addIfEnabled(toolDefinitions, _httpPutTool);
    _addIfEnabled(toolDefinitions, _httpPatchTool);
    _addIfEnabled(toolDefinitions, _httpDeleteTool);
    _addIfEnabled(toolDefinitions, _tracerouteTool);

    if (FilesystemTools.isDesktopPlatform) {
      _addIfEnabled(toolDefinitions, _listDirectoryTool);
      _addIfEnabled(toolDefinitions, _readFileTool);
      _addIfEnabled(toolDefinitions, _writeFileTool);
      _addIfEnabled(toolDefinitions, _editFileTool);
      _addIfEnabled(toolDefinitions, _rollbackLastFileChangeTool);
      _addIfEnabled(toolDefinitions, _findFilesTool);
      _addIfEnabled(toolDefinitions, _searchFilesTool);
    }

    if (LocalShellTools.isDesktopPlatform) {
      _addIfEnabled(toolDefinitions, _localExecuteCommandTool);
    }

    // Git tools (desktop only — requires system git binary via Process.run).
    if (GitTools.isDesktopPlatform) {
      _addIfEnabled(toolDefinitions, _gitExecuteCommandTool);
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

    // Use MCP tools when connected.
    if (_status == McpConnectionStatus.connected && _cachedTools.isNotEmpty) {
      toolDefinitions.addAll(_cachedTools.map((t) => t.toOpenAiTool()));
      return toolDefinitions;
    }

    // Fallback to the fixed SearXNG tool definition.
    if (searxngClient != null) {
      _addIfEnabled(toolDefinitions, _webSearchToolFallback);
    }

    return toolDefinitions;
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
    if (name == 'get_current_datetime') {
      final result = _buildCurrentDatetimeResult();
      appLog('[McpToolService] Local datetime tool executed successfully');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'search_past_conversations' && conversationRepository != null) {
      final result = _searchConversations(arguments);
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

    if (name == 'list_directory') {
      final path = (arguments['path'] as String?)?.trim() ?? '';
      if (path.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'path is required',
        );
      }
      final recursive = arguments['recursive'] as bool? ?? false;
      final maxEntries = ((arguments['max_entries'] as num?)?.toInt() ?? 200)
          .clamp(1, 1000);
      final result = await FilesystemTools.listDirectory(
        path: path,
        recursive: recursive,
        maxEntries: maxEntries,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'read_file') {
      final path = (arguments['path'] as String?)?.trim() ?? '';
      if (path.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'path is required',
        );
      }
      final maxChars = ((arguments['max_chars'] as num?)?.toInt() ?? 120000)
          .clamp(100, 500000);
      final result = await FilesystemTools.readFile(
        path: path,
        maxChars: maxChars,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'write_file') {
      final path = (arguments['path'] as String?)?.trim() ?? '';
      final content = arguments['content'] as String? ?? '';
      if (path.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'path is required',
        );
      }
      final createParents = arguments['create_parents'] as bool? ?? true;
      final snapshot = await FilesystemTools.captureTextSnapshot(path);
      final result = await FilesystemTools.writeFile(
        path: path,
        content: content,
        createParents: createParents,
      );
      if (_isFilesystemPayloadSuccess(result)) {
        _pushFileRollbackEntry(snapshot);
      }
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'edit_file') {
      final path = (arguments['path'] as String?)?.trim() ?? '';
      final oldText = arguments['old_text'] as String? ?? '';
      final newText = arguments['new_text'] as String? ?? '';
      if (path.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'path is required',
        );
      }
      final replaceAll = arguments['replace_all'] as bool? ?? false;
      final snapshot = await FilesystemTools.captureTextSnapshot(path);
      final result = await FilesystemTools.editFile(
        path: path,
        oldText: oldText,
        newText: newText,
        replaceAll: replaceAll,
      );
      if (_isFilesystemPayloadSuccess(result)) {
        _pushFileRollbackEntry(snapshot);
      }
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'rollback_last_file_change') {
      final entry = _fileRollbackStack.isEmpty
          ? null
          : _fileRollbackStack.removeLast();
      if (entry == null) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'No recent file change is available to roll back',
        );
      }

      final result = await FilesystemTools.restoreTextSnapshot(
        path: entry.path,
        existedBefore: entry.existedBefore,
        content: entry.previousContent,
      );
      if (!_isFilesystemPayloadSuccess(result)) {
        _fileRollbackStack.add(entry);
        return McpToolResult(
          toolName: name,
          result: result,
          isSuccess: false,
          errorMessage: 'Failed to roll back the last file change',
        );
      }

      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'find_files') {
      final path = (arguments['path'] as String?)?.trim() ?? '';
      final pattern = (arguments['pattern'] as String?)?.trim() ?? '';
      if (path.isEmpty || pattern.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'path and pattern are required',
        );
      }
      final recursive = arguments['recursive'] as bool? ?? true;
      final maxResults = ((arguments['max_results'] as num?)?.toInt() ?? 200)
          .clamp(1, 1000);
      final result = await FilesystemTools.findFiles(
        path: path,
        pattern: pattern,
        recursive: recursive,
        maxResults: maxResults,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'search_files') {
      final path = (arguments['path'] as String?)?.trim() ?? '';
      final query = (arguments['query'] as String?)?.trim() ?? '';
      if (path.isEmpty || query.isEmpty) {
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'path and query are required',
        );
      }
      final filePattern = (arguments['file_pattern'] as String?)?.trim();
      final caseSensitive = arguments['case_sensitive'] as bool? ?? false;
      final maxResults = ((arguments['max_results'] as num?)?.toInt() ?? 200)
          .clamp(1, 1000);
      final result = await FilesystemTools.searchFiles(
        path: path,
        query: query,
        filePattern: filePattern,
        caseSensitive: caseSensitive,
        maxResults: maxResults,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
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
      final result = await LocalShellTools.execute(
        command: command,
        workingDirectory: workingDirectory,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    // Built-in network tools.
    if (name == 'ping') {
      try {
        final host = (arguments['host'] as String?)?.trim() ?? '';
        if (host.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Host is required',
          );
        }
        final count = ((arguments['count'] as num?)?.toInt() ?? 4).clamp(1, 10);
        final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 5).clamp(
          1,
          30,
        );
        final result = await NetworkTools.ping(
          host: host,
          count: count,
          timeoutSeconds: timeout,
        );
        appLog('[McpToolService] Ping tool executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] Ping tool error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'whois_lookup') {
      try {
        final domain = (arguments['domain'] as String?)?.trim() ?? '';
        if (domain.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Domain is required',
          );
        }
        final result = await NetworkTools.whoisLookup(domain: domain);
        appLog('[McpToolService] Whois tool executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] Whois tool error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'dns_lookup') {
      try {
        final host = (arguments['host'] as String?)?.trim() ?? '';
        if (host.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Host is required',
          );
        }
        final result = await NetworkTools.dnsLookup(host: host);
        appLog('[McpToolService] DNS lookup executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] DNS lookup error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'port_check') {
      try {
        final host = (arguments['host'] as String?)?.trim() ?? '';
        final port = (arguments['port'] as num?)?.toInt();
        if (host.isEmpty || port == null) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Host and port are required',
          );
        }
        final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 5).clamp(
          1,
          30,
        );
        final result = await NetworkTools.portCheck(
          host: host,
          port: port,
          timeoutSeconds: timeout,
        );
        appLog('[McpToolService] Port check executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] Port check error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'ssl_certificate') {
      try {
        final host = (arguments['host'] as String?)?.trim() ?? '';
        if (host.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Host is required',
          );
        }
        final port = ((arguments['port'] as num?)?.toInt() ?? 443).clamp(
          1,
          65535,
        );
        final result = await NetworkTools.sslCertificate(
          host: host,
          port: port,
        );
        appLog('[McpToolService] SSL certificate check executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] SSL certificate error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'http_status') {
      try {
        final url = (arguments['url'] as String?)?.trim() ?? '';
        if (url.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'URL is required',
          );
        }
        final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 10).clamp(
          1,
          30,
        );
        final result = await NetworkTools.httpStatus(
          url: url,
          timeoutSeconds: timeout,
        );
        appLog('[McpToolService] HTTP status check executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] HTTP status error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'http_get' ||
        name == 'http_head' ||
        name == 'http_post' ||
        name == 'http_put' ||
        name == 'http_patch' ||
        name == 'http_delete') {
      try {
        final url = (arguments['url'] as String?)?.trim() ?? '';
        if (url.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'URL is required',
          );
        }
        final headers = _parseHeaderMap(arguments['headers']);
        final body = arguments['body'] as String?;
        final contentType = (arguments['content_type'] as String?)?.trim();
        final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 10).clamp(
          1,
          30,
        );
        final followRedirects = arguments['follow_redirects'] as bool? ?? true;
        final maxRedirects =
            ((arguments['max_redirects'] as num?)?.toInt() ?? 5).clamp(0, 10);

        late final String result;
        switch (name) {
          case 'http_get':
            result = await NetworkTools.httpGet(
              url: url,
              headers: headers,
              timeoutSeconds: timeout,
              followRedirects: followRedirects,
              maxRedirects: maxRedirects,
            );
            break;
          case 'http_head':
            result = await NetworkTools.httpHead(
              url: url,
              headers: headers,
              timeoutSeconds: timeout,
              followRedirects: followRedirects,
              maxRedirects: maxRedirects,
            );
            break;
          case 'http_post':
            result = await NetworkTools.httpPost(
              url: url,
              headers: headers,
              body: body,
              contentType: contentType,
              timeoutSeconds: timeout,
              followRedirects: followRedirects,
              maxRedirects: maxRedirects,
            );
            break;
          case 'http_put':
            result = await NetworkTools.httpPut(
              url: url,
              headers: headers,
              body: body,
              contentType: contentType,
              timeoutSeconds: timeout,
              followRedirects: followRedirects,
              maxRedirects: maxRedirects,
            );
            break;
          case 'http_patch':
            result = await NetworkTools.httpPatch(
              url: url,
              headers: headers,
              body: body,
              contentType: contentType,
              timeoutSeconds: timeout,
              followRedirects: followRedirects,
              maxRedirects: maxRedirects,
            );
            break;
          case 'http_delete':
            result = await NetworkTools.httpDelete(
              url: url,
              headers: headers,
              body: body,
              contentType: contentType,
              timeoutSeconds: timeout,
              followRedirects: followRedirects,
              maxRedirects: maxRedirects,
            );
            break;
        }

        appLog('[McpToolService] $name executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] $name error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    if (name == 'traceroute') {
      try {
        final host = (arguments['host'] as String?)?.trim() ?? '';
        if (host.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Host is required',
          );
        }
        final maxHops = ((arguments['max_hops'] as num?)?.toInt() ?? 20).clamp(
          1,
          30,
        );
        final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 3).clamp(
          1,
          10,
        );
        final result = await NetworkTools.traceroute(
          host: host,
          maxHops: maxHops,
          timeoutSeconds: timeout,
        );
        appLog('[McpToolService] Traceroute executed successfully');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] Traceroute error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
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
        );
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
    final entry = _fileRollbackStack.isEmpty ? null : _fileRollbackStack.last;
    if (entry == null) return null;

    final currentSnapshot = await FilesystemTools.captureTextSnapshot(
      entry.path,
    );
    final summary = entry.existedBefore
        ? 'Restore the previous contents of this file.'
        : 'Delete the newly created file.';

    if (currentSnapshot.error != null) {
      return FileRollbackPreview(
        path: entry.path,
        preview:
            'Diff preview unavailable: ${currentSnapshot.error}\n\n'
            'Rollback target: ${entry.path}\n'
            '$summary',
        summary: summary,
      );
    }

    return FileRollbackPreview(
      path: entry.path,
      preview: FilesystemTools.buildUnifiedDiff(
        path: entry.path,
        oldContent: currentSnapshot.exists ? currentSnapshot.content : null,
        newContent: entry.existedBefore ? (entry.previousContent ?? '') : null,
      ),
      summary: summary,
    );
  }

  bool _isFilesystemPayloadSuccess(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is! Map<String, dynamic> || decoded['error'] == null;
    } catch (_) {
      return true;
    }
  }

  void _pushFileRollbackEntry(TextFileSnapshot snapshot) {
    if (snapshot.exists && snapshot.error != null) {
      return;
    }

    _fileRollbackStack.add(
      _FileRollbackEntry(
        path: snapshot.path,
        existedBefore: snapshot.exists,
        previousContent: snapshot.content,
      ),
    );

    if (_fileRollbackStack.length > 20) {
      _fileRollbackStack.removeAt(0);
    }
  }

  /// Fallback `web_search` tool definition for SearXNG.
  static Map<String, dynamic> get _webSearchToolFallback => {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description':
          'Perform a web search on the Internet. Use this to look up the latest information, news, weather, etc.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query'},
        },
        'required': ['query'],
      },
    },
  };

  /// Built-in local datetime tool definition.
  static Map<String, dynamic> get _currentDatetimeTool => {
    'type': 'function',
    'function': {
      'name': 'get_current_datetime',
      'description':
          'Returns the current local date/time and reference date ranges for interpreting relative expressions such as today/this week/recent.',
      'parameters': {'type': 'object', 'properties': {}, 'required': []},
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
  // Built-in tool: search_past_conversations
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _searchPastConversationsTool => {
    'type': 'function',
    'function': {
      'name': 'search_past_conversations',
      'description':
          'Search past conversation history for specific topics, facts, '
          'or information the user discussed previously. Use this when the '
          'user asks about something they mentioned in a past conversation.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search keywords to find in past conversations',
          },
          'max_results': {
            'type': 'integer',
            'description':
                'Maximum number of matching messages to return (default: 5, max: 10)',
          },
        },
        'required': ['query'],
      },
    },
  };

  String _searchConversations(Map<String, dynamic> arguments) {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    final maxResults = ((arguments['max_results'] as num?)?.toInt() ?? 5).clamp(
      1,
      10,
    );
    if (query.isEmpty) return 'Error: search query is empty';

    final conversations = conversationRepository!.getAll();
    final keywords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();
    if (keywords.isEmpty) return 'Error: no valid search keywords';

    final matches = <_ConversationMatch>[];
    for (final conversation in conversations) {
      for (final message in conversation.messages) {
        if (message.role == MessageRole.system) continue;
        final content = message.content.toLowerCase();
        final matchCount = keywords.where((kw) => content.contains(kw)).length;
        if (matchCount > 0) {
          matches.add(
            _ConversationMatch(
              title: conversation.title,
              date: message.timestamp,
              conversationDate: conversation.updatedAt,
              role: message.role.name,
              content: message.content,
              score: matchCount / keywords.length,
            ),
          );
        }
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    final topMatches = matches.take(maxResults);

    if (topMatches.isEmpty) {
      return 'No matching conversations found for: $query';
    }

    final buffer = StringBuffer();
    for (final match in topMatches) {
      buffer.writeln(
        '--- [${_formatDate(match.conversationDate)}] ${match.title} ---',
      );
      buffer.writeln('${match.role}: ${_truncateText(match.content, 400)}');
      buffer.writeln();
    }
    return buffer.toString();
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
  // Built-in tool: ping
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _pingTool => {
    'type': 'function',
    'function': {
      'name': 'ping',
      'description':
          'Ping a network host to check reachability and measure latency. '
          'Returns round-trip times, packet loss, and statistics.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                'Hostname or IP address to ping (e.g., google.com, 8.8.8.8)',
          },
          'count': {
            'type': 'integer',
            'description':
                'Number of ping packets to send (default: 4, max: 10)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout per ping in seconds (default: 5)',
          },
        },
        'required': ['host'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in tool: whois_lookup
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _whoisLookupTool => {
    'type': 'function',
    'function': {
      'name': 'whois_lookup',
      'description':
          'Look up domain registration information (WHOIS). Returns registrar, '
          'creation/expiry dates, name servers, and registrant details.',
      'parameters': {
        'type': 'object',
        'properties': {
          'domain': {
            'type': 'string',
            'description': 'Domain name to look up (e.g., example.com)',
          },
        },
        'required': ['domain'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in tool: dns_lookup
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _dnsLookupTool => {
    'type': 'function',
    'function': {
      'name': 'dns_lookup',
      'description':
          'Resolve a hostname to IP addresses (A/AAAA records). '
          'Returns all resolved addresses with their type.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname to resolve (e.g., google.com)',
          },
        },
        'required': ['host'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in tool: port_check
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _portCheckTool => {
    'type': 'function',
    'function': {
      'name': 'port_check',
      'description':
          'Test whether a specific TCP port is open on a host. '
          'Returns open/closed status and response time.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname or IP address to check',
          },
          'port': {
            'type': 'integer',
            'description': 'TCP port number to test (e.g., 80, 443, 8080)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout in seconds (default: 5)',
          },
        },
        'required': ['host', 'port'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in tool: ssl_certificate
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _sslCertificateTool => {
    'type': 'function',
    'function': {
      'name': 'ssl_certificate',
      'description':
          'Inspect the TLS/SSL certificate of a host. Returns subject, issuer, '
          'validity dates, and whether it is currently valid.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname to inspect (e.g., google.com)',
          },
          'port': {
            'type': 'integer',
            'description': 'Port number (default: 443)',
          },
        },
        'required': ['host'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in tool: http_status
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _httpStatusTool => {
    'type': 'function',
    'function': {
      'name': 'http_status',
      'description':
          'Check if a URL is reachable. Returns HTTP status code, response '
          'headers, response time, and redirect chain.',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'Full URL to check (e.g., https://example.com)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout in seconds (default: 10)',
          },
        },
        'required': ['url'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Built-in tool: HTTP method tools (GET / HEAD / POST / PUT / PATCH / DELETE)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _httpMethodSchema({
    required String name,
    required String description,
    required bool acceptsBody,
  }) {
    final properties = <String, dynamic>{
      'url': {
        'type': 'string',
        'description': 'Full URL to request (e.g., https://example.com/api)',
      },
      'headers': {
        'type': 'object',
        'description':
            'Optional request headers as a JSON object of string values '
            '(e.g., {"Authorization": "Bearer ..."}).',
        'additionalProperties': {'type': 'string'},
      },
      'timeout': {
        'type': 'integer',
        'description': 'Timeout in seconds (default: 10, max: 30)',
      },
      'follow_redirects': {
        'type': 'boolean',
        'description': 'Whether to follow HTTP redirects (default: true)',
      },
      'max_redirects': {
        'type': 'integer',
        'description': 'Maximum redirects to follow (default: 5, max: 10)',
      },
    };

    if (acceptsBody) {
      properties['body'] = {
        'type': 'string',
        'description':
            'Raw request body as a string. For JSON, pass a stringified '
            'JSON document and set content_type accordingly.',
      };
      properties['content_type'] = {
        'type': 'string',
        'description':
            'Convenience for the Content-Type header (default: '
            'application/json when body is provided). Ignored if a '
            'Content-Type entry is also supplied via headers.',
      };
    }

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': ['url'],
        },
      },
    };
  }

  static Map<String, dynamic> get _httpGetTool => _httpMethodSchema(
    name: 'http_get',
    description:
        'Perform an HTTP GET request and return status code, headers, '
        'and the response body (UTF-8 decoded, truncated to 4000 chars).',
    acceptsBody: false,
  );

  static Map<String, dynamic> get _httpHeadTool => _httpMethodSchema(
    name: 'http_head',
    description:
        'Perform an HTTP HEAD request. Returns status code and response '
        'headers without the body.',
    acceptsBody: false,
  );

  static Map<String, dynamic> get _httpPostTool => _httpMethodSchema(
    name: 'http_post',
    description:
        'Perform an HTTP POST request with an optional request body. '
        'Returns status code, headers, and response body (truncated to '
        '4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _httpPutTool => _httpMethodSchema(
    name: 'http_put',
    description:
        'Perform an HTTP PUT request with an optional request body. '
        'Returns status code, headers, and response body (truncated to '
        '4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _httpPatchTool => _httpMethodSchema(
    name: 'http_patch',
    description:
        'Perform an HTTP PATCH request with an optional request body. '
        'Returns status code, headers, and response body (truncated to '
        '4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _httpDeleteTool => _httpMethodSchema(
    name: 'http_delete',
    description:
        'Perform an HTTP DELETE request. A request body is permitted '
        'but optional. Returns status code, headers, and response body '
        '(truncated to 4000 chars).',
    acceptsBody: true,
  );

  /// Coerces an arbitrary `headers` argument into a `Map<String, String>`.
  ///
  /// Non-string values are converted via `toString()`. Returns `null` when
  /// no usable headers were supplied so callers can skip the parameter.
  static Map<String, String>? _parseHeaderMap(dynamic raw) {
    if (raw is! Map) return null;
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key == null || value == null) return;
      result[key.toString()] = value.toString();
    });
    return result.isEmpty ? null : result;
  }

  // ---------------------------------------------------------------------------
  // Built-in tool: traceroute
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _tracerouteTool => {
    'type': 'function',
    'function': {
      'name': 'traceroute',
      'description':
          'Trace the network path to a host by incrementing TTL. '
          'Shows each hop with IP address and response time.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname or IP address to trace (e.g., google.com)',
          },
          'max_hops': {
            'type': 'integer',
            'description': 'Maximum number of hops (default: 20, max: 30)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout per hop in seconds (default: 3)',
          },
        },
        'required': ['host'],
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

  static Map<String, dynamic> get _listDirectoryTool => {
    'type': 'function',
    'function': {
      'name': 'list_directory',
      'description':
          'List files and directories inside a local directory. Useful for '
          'understanding project structure before reading or editing files.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute or project-relative directory path. Optional when a coding project is selected.',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Whether to include nested files and folders.',
          },
          'max_entries': {
            'type': 'integer',
            'description': 'Maximum number of entries to return.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _readFileTool => {
    'type': 'function',
    'function': {
      'name': 'read_file',
      'description':
          'Read a UTF-8 text file from the local project. Use this to inspect source files and configs.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'max_chars': {
            'type': 'integer',
            'description': 'Maximum number of characters to return.',
          },
        },
        'required': ['path'],
      },
    },
  };

  static Map<String, dynamic> get _writeFileTool => {
    'type': 'function',
    'function': {
      'name': 'write_file',
      'description':
          'Write a full UTF-8 text file in the local project. This can create or overwrite files and requires user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'content': {
            'type': 'string',
            'description': 'Complete file content to write.',
          },
          'create_parents': {
            'type': 'boolean',
            'description': 'Create parent directories when needed.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['path', 'content'],
      },
    },
  };

  static Map<String, dynamic> get _editFileTool => {
    'type': 'function',
    'function': {
      'name': 'edit_file',
      'description':
          'Replace text inside a local UTF-8 file. This is useful for targeted edits and requires user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'old_text': {
            'type': 'string',
            'description': 'Exact text to replace.',
          },
          'new_text': {'type': 'string', 'description': 'Replacement text.'},
          'replace_all': {
            'type': 'boolean',
            'description': 'Replace all matches instead of only the first.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['path', 'old_text', 'new_text'],
      },
    },
  };

  static Map<String, dynamic> get _rollbackLastFileChangeTool => {
    'type': 'function',
    'function': {
      'name': 'rollback_last_file_change',
      'description':
          'Revert the most recent successful local file change performed '
          'through write_file or edit_file. This requires user approval and '
          'restores the previous UTF-8 contents, or deletes the file if it '
          'was newly created.',
      'parameters': {
        'type': 'object',
        'properties': {
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _findFilesTool => {
    'type': 'function',
    'function': {
      'name': 'find_files',
      'description':
          'Find files in the local project by wildcard pattern such as "*.dart" or "*test*".',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute or project-relative directory path. Optional when a coding project is selected.',
          },
          'pattern': {
            'type': 'string',
            'description': 'Wildcard filename or path pattern.',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Whether to search subdirectories.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of matches to return.',
          },
        },
        'required': ['pattern'],
      },
    },
  };

  static Map<String, dynamic> get _searchFilesTool => {
    'type': 'function',
    'function': {
      'name': 'search_files',
      'description':
          'Search text across local project files and return matching lines with file paths and line numbers.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute or project-relative directory path. Optional when a coding project is selected.',
          },
          'query': {'type': 'string', 'description': 'Text to search for.'},
          'file_pattern': {
            'type': 'string',
            'description': 'Optional wildcard filter such as "*.dart".',
          },
          'case_sensitive': {
            'type': 'boolean',
            'description': 'Whether the search should be case-sensitive.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of matching lines to return.',
          },
        },
        'required': ['query'],
      },
    },
  };

  static Map<String, dynamic> get _localExecuteCommandTool => {
    'type': 'function',
    'function': {
      'name': 'local_execute_command',
      'description':
          'Execute a local shell command inside the current project. Read-only commands may run immediately; commands that can modify files or state require user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Exact shell command to run.',
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

  // ---------------------------------------------------------------------------
  // Built-in tool: git_execute_command (desktop only)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _gitExecuteCommandTool => {
    'type': 'function',
    'function': {
      'name': 'git_execute_command',
      'description':
          'Execute a git command in a local repository (desktop only — '
          'macOS, Linux, Windows). Read-only commands (status, log, diff, '
          'show, branch, tag, remote, blame, etc.) run immediately. Write '
          'operations (commit, push, pull, checkout, merge, rebase, reset, '
          'etc.) require user approval before execution. Always use '
          'non-interactive flags (e.g. commit -m "message", not bare commit).',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description':
                'Git subcommand and arguments (without the leading "git"), '
                'e.g. "status", "log --oneline -20", "diff HEAD~1", '
                '"commit -m \\"fix typo\\"".',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory. '
                'Optional when a coding project is currently selected; the '
                'project root can be used as the default.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable explanation shown to the user in the '
                'confirmation dialog (only used for write operations).',
          },
        },
        'required': ['command'],
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
          final timeout = (arguments['timeout'] as num?)?.toInt() ?? 1000;
          final ports = (arguments['ports'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList();
          final result = await lanScan.startScan(
            subnet: subnet,
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
    final clean = hex.replaceAll(RegExp(r'[\s:-]'), '');
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

  Set<String> _biGrams(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return const {};
    if (normalized.length == 1) return {normalized};
    final grams = <String>{};
    for (var i = 0; i < normalized.length - 1; i++) {
      grams.add(normalized.substring(i, i + 2));
    }
    return grams;
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

class _ConversationMatch {
  _ConversationMatch({
    required this.title,
    required this.date,
    required this.conversationDate,
    required this.role,
    required this.content,
    required this.score,
  });

  final String title;
  final DateTime date;
  final DateTime conversationDate;
  final String role;
  final String content;
  final double score;
}

class _FileRollbackEntry {
  const _FileRollbackEntry({
    required this.path,
    required this.existedBefore,
    this.previousContent,
  });

  final String path;
  final bool existedBefore;
  final String? previousContent;
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
