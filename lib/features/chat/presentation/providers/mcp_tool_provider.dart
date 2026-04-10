import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/ssh_service.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/mcp_client.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/searxng_client.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/conversation_repository.dart';

/// Provides the configured MCP clients.
///
/// Returns one `McpClient` per configured URL when MCP is enabled.
final mcpClientsProvider = Provider<List<McpClient>>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  final mcpUrls = settings.effectiveMcpUrls;
  if (!settings.mcpEnabled || mcpUrls.isEmpty) {
    return const [];
  }
  return mcpUrls.map((url) => McpClient(baseUrl: url)).toList(growable: false);
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
  final settings = ref.watch(settingsNotifierProvider);
  // Always provide the service so built-in local tools remain available.
  return McpToolService(
    mcpClients: mcpClients,
    searxngClient: searxngClient,
    conversationRepository: conversationRepo,
    memoryRepository: memoryRepo,
    sshService: sshService,
    disabledBuiltInTools: settings.disabledBuiltInToolsSet,
  );
});
