import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/ssh_service.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/mcp_client.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/searxng_client.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/conversation_repository.dart';

/// Provides the MCP client.
///
/// Returns an `McpClient` when MCP is enabled and a URL is configured.
final mcpClientProvider = Provider<McpClient?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (!settings.mcpEnabled || settings.mcpUrl.isEmpty) {
    return null;
  }
  return McpClient(baseUrl: settings.mcpUrl);
});

/// Provides the SearXNG client.
///
/// Returns a `SearxngClient` when MCP is enabled and a URL is configured.
/// `McpToolService` uses it as a fallback.
final searxngClientProvider = Provider<SearxngClient?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (!settings.mcpEnabled || settings.mcpUrl.isEmpty) {
    return null;
  }
  return SearxngClient(baseUrl: settings.mcpUrl);
});

/// Provides the MCP tool service.
///
/// Exposes a service that fetches and executes tools from an MCP server.
/// Includes the SearXNG fallback path.
final mcpToolServiceProvider = Provider<McpToolService?>((ref) {
  final mcpClient = ref.watch(mcpClientProvider);
  final searxngClient = ref.watch(searxngClientProvider);
  final conversationRepo = ref.watch(conversationRepositoryProvider);
  final memoryRepo = ref.watch(chatMemoryRepositoryProvider);
  final sshService = ref.watch(sshServiceProvider);
  // Always provide the service so built-in local tools remain available.
  return McpToolService(
    mcpClient: mcpClient,
    searxngClient: searxngClient,
    conversationRepository: conversationRepo,
    memoryRepository: memoryRepo,
    sshService: sshService,
  );
});
