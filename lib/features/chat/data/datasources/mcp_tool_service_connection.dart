// Same-library extension on [McpToolService]: MCP client connection management
// and exposed/namespaced tool-name construction. Pure relocation from
// mcp_tool_service.dart (F5), no behavior change.
part of 'mcp_tool_service.dart';

extension McpToolServiceConnection on McpToolService {
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

    final usedNames = {...McpToolService._reservedToolNames};
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
              McpStdioClient(
                command: server.command.trim(),
                args: server.args,
                env: server.normalizedEnv,
              ),
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
    final maxBaseLength = (McpToolService._maxToolNameLength - suffix.length).clamp(1, 64);
    final truncatedBase = baseName.length <= maxBaseLength
        ? baseName
        : baseName.substring(0, maxBaseLength);
    return '$truncatedBase$suffix';
  }

  String _truncateToolName(String value) {
    if (value.length <= McpToolService._maxToolNameLength) {
      return value;
    }
    return value.substring(0, McpToolService._maxToolNameLength);
  }

  String _buildServerKey(String url) {
    final uri = Uri.tryParse(url);
    final rawValue = uri == null
        ? 'server'
        : [
            if (uri.host.isNotEmpty) uri.host else 'server',
            if (uri.hasPort) uri.port.toString(),
          ].join('_');
    final sanitized = rawValue.replaceAll(McpToolService._serverKeyInvalidChars, '_');
    final collapsed = sanitized.replaceAll(
      McpToolService._serverKeyConsecutiveUnderscores,
      '_',
    );
    final normalized = collapsed
        .replaceAll(McpToolService._serverKeyEdgeUnderscores, '')
        .toLowerCase();
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
}
