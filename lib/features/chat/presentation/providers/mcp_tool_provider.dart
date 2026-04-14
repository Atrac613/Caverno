import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/ble_service.dart';
import '../../../../core/services/lan_scan_service.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/wifi_service.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/mcp_client.dart';
import '../../data/datasources/mcp_stdio_client.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/searxng_client.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/datasources/filesystem_tools.dart';

/// Provides the configured MCP clients.
///
/// Returns one [McpClientBase] per enabled server when MCP is enabled.
/// Stdio clients are only created on desktop platforms.
final mcpClientsProvider = Provider<List<McpClientBase>>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (!settings.mcpEnabled) return const [];

  final isDesktop = FilesystemTools.isDesktopPlatform;
  final clients = <McpClientBase>[];

  for (final server in settings.enabledMcpServers) {
    switch (server.type) {
      case McpServerType.http:
        clients.add(McpClient(baseUrl: server.normalizedUrl));
      case McpServerType.stdio:
        if (isDesktop) {
          clients.add(McpStdioClient(
            command: server.command.trim(),
            args: server.args,
          ));
        }
    }
  }

  // Dispose all clients when the provider is invalidated (settings change,
  // app shutdown). This kills any stdio child processes.
  ref.onDispose(() {
    for (final client in clients) {
      client.dispose();
    }
  });

  return clients;
});

/// Provides the SearXNG client.
///
/// Uses the primary MCP URL for the legacy SearXNG fallback path.
final searxngClientProvider = Provider<SearxngClient?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  final primaryMcpUrl = settings.primaryMcpUrl;
  if (!settings.mcpEnabled || primaryMcpUrl.isEmpty) {
    return null;
  }
  return SearxngClient(baseUrl: primaryMcpUrl);
});

/// Provides the MCP tool service.
///
/// Exposes a service that fetches and executes tools from an MCP server.
/// Includes the SearXNG fallback path.
final mcpToolServiceProvider = Provider<McpToolService?>((ref) {
  final mcpClients = ref.watch(mcpClientsProvider);
  final searxngClient = ref.watch(searxngClientProvider);
  final conversationRepo = ref.watch(conversationRepositoryProvider);
  final memoryRepo = ref.watch(chatMemoryRepositoryProvider);
  final sshService = ref.watch(sshServiceProvider);
  final bleService = ref.watch(bleServiceProvider);
  final wifiService = ref.watch(wifiServiceProvider);
  final lanScanService = ref.watch(lanScanServiceProvider);
  final settings = ref.watch(settingsNotifierProvider);
  // Always provide the service so built-in local tools remain available.
  return McpToolService(
    mcpClients: mcpClients,
    searxngClient: searxngClient,
    conversationRepository: conversationRepo,
    memoryRepository: memoryRepo,
    sshService: sshService,
    bleService: bleService,
    wifiService: wifiService,
    lanScanService: lanScanService,
    disabledBuiltInTools: settings.disabledBuiltInToolsSet,
  );
});
