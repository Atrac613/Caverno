import '../../../../core/utils/logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'filesystem_tools.dart';
import 'mcp_client.dart';
import 'mcp_stdio_client.dart';
import 'mcp_tool_result_normalizer.dart';
import 'remote_mcp_tool_name_policy.dart';

typedef RemoteMcpHttpClientFactory = McpClientBase Function(String baseUrl);

typedef RemoteMcpStdioClientFactory =
    McpClientBase Function(
      String command,
      List<String> args,
      Map<String, String> environment,
    );

/// Owns remote MCP connection state, exposure, and invocation routing.
/// Configured clients keep their existing application-owned lifetime.
class RemoteMcpConnectionManager {
  RemoteMcpConnectionManager({
    required this.configuredClients,
    required Set<String> reservedToolNames,
    Set<String> reservedToolNamePrefixes = const {},
    RemoteMcpHttpClientFactory? httpClientFactory,
    RemoteMcpStdioClientFactory? stdioClientFactory,
    bool? isDesktopPlatform,
  }) : _toolNamePolicy = RemoteMcpToolNamePolicy(
         reservedToolNames: reservedToolNames,
         reservedToolNamePrefixes: reservedToolNamePrefixes,
       ),
       _httpClientFactory =
           httpClientFactory ?? ((baseUrl) => McpClient(baseUrl: baseUrl)),
       _stdioClientFactory =
           stdioClientFactory ??
           ((command, args, environment) =>
               McpStdioClient(command: command, args: args, env: environment)),
       _isDesktopPlatform =
           isDesktopPlatform ?? FilesystemTools.isDesktopPlatform;

  final List<McpClientBase> configuredClients;
  final RemoteMcpToolNamePolicy _toolNamePolicy;
  final RemoteMcpHttpClientFactory _httpClientFactory;
  final RemoteMcpStdioClientFactory _stdioClientFactory;
  final bool _isDesktopPlatform;

  List<McpToolEntity> _cachedTools = [];
  final Map<String, _RemoteToolBinding> _remoteToolBindings = {};
  List<McpServerConnectionInfo> _serverStates = const [];
  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  String? _lastError;

  McpConnectionStatus get status => _status;

  List<McpToolEntity> get tools => _cachedTools;
  List<McpServerConnectionInfo> get serverStates =>
      List.unmodifiable(_serverStates);
  String? get lastError => _lastError;
  bool isExternalToolName(String name) => _remoteToolBindings.containsKey(name);

  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {
    final clients = overrideServers != null
        ? _resolveClientsFromServers(overrideServers)
        : overrideUrls != null || overrideUrl != null
        ? _resolveUrlClients(overrideUrls ?? [overrideUrl!])
        : configuredClients;

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
    } catch (error, stackTrace) {
      appLog(
        '[McpToolService] Connection failed: ${error.runtimeType}: $error',
      );
      appLog('[McpToolService] stackTrace: $stackTrace');
      _status = McpConnectionStatus.error;
      _lastError = error.toString();
      _cachedTools = [];
      _remoteToolBindings.clear();
      _serverStates = clients
          .map(
            (client) => McpServerConnectionInfo(
              identifier: client.identifier,
              status: McpConnectionStatus.error,
              lastError: error.toString(),
            ),
          )
          .toList(growable: false);
    }
  }

  /// Executes an exposed remote tool, or returns null when it is unavailable.
  Future<McpToolResult?> tryExecute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final remoteBinding = _remoteToolBindings[name];
    if (_status != McpConnectionStatus.connected || remoteBinding == null) {
      return null;
    }

    try {
      final result = await remoteBinding.client.callTool(
        name: remoteBinding.remoteToolName,
        arguments: arguments,
      );
      appLog(
        '[McpToolService] MCP execution succeeded: ${result.length} chars',
      );
      return McpToolResultNormalizer.success(
        toolName: name,
        result: result,
        isExternalMcpResult: true,
      );
    } catch (error) {
      appLog('[McpToolService] MCP tool execution error: $error');
      return McpToolResultNormalizer.failure(
        toolName: name,
        isExternalMcpResult: true,
        errorMessage: error.toString(),
      );
    }
  }

  Future<_RemoteMcpConnectionResult> _connectClient(
    McpClientBase client,
  ) async {
    try {
      final tools = await client.listTools();
      return _RemoteMcpConnectionResult(
        identifier: client.identifier,
        client: client,
        tools: tools,
      );
    } catch (error, stackTrace) {
      appLog(
        '[McpToolService] Connection failed for ${client.identifier}: ${error.runtimeType}: $error',
      );
      appLog('[McpToolService] stackTrace: $stackTrace');
      return _RemoteMcpConnectionResult(
        identifier: client.identifier,
        client: client,
        error: error.toString(),
      );
    }
  }

  void _rebuildRemoteToolCache(List<_RemoteMcpConnectionResult> results) {
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

    final usedNames = _toolNamePolicy.createUsedNames();
    for (final result in successfulResults) {
      for (final tool in result.tools) {
        final exposedName = _toolNamePolicy.buildExposedName(
          baseName: tool.name,
          identifier: result.identifier,
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

  List<McpClientBase> _resolveUrlClients(List<String> targetUrls) {
    return targetUrls.map(_httpClientFactory).toList(growable: false);
  }

  List<McpClientBase> _resolveClientsFromServers(
    List<McpServerConfig> servers,
  ) {
    final clients = <McpClientBase>[];
    for (final server in servers) {
      if (!server.enabled || !server.isValid || server.isBlocked) {
        continue;
      }
      switch (server.type) {
        case McpServerType.http:
          clients.add(_httpClientFactory(server.normalizedUrl));
        case McpServerType.stdio:
          if (_isDesktopPlatform) {
            clients.add(
              _stdioClientFactory(
                server.command.trim(),
                server.args,
                server.normalizedEnv,
              ),
            );
          }
      }
    }
    return clients;
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

class _RemoteMcpConnectionResult {
  const _RemoteMcpConnectionResult({
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
