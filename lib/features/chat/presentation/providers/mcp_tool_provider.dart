import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/mcp_client.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/searxng_client.dart';

/// MCPクライアントプロバイダー
///
/// MCP設定が有効で、URLが設定されている場合にMcpClientを提供。
final mcpClientProvider = Provider<McpClient?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (!settings.mcpEnabled || settings.mcpUrl.isEmpty) {
    return null;
  }
  return McpClient(baseUrl: settings.mcpUrl);
});

/// SearXNGクライアントプロバイダー
///
/// MCP設定が有効で、URLが設定されている場合にSearxngClientを提供。
/// McpToolServiceからフォールバックとして使用される。
final searxngClientProvider = Provider<SearxngClient?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (!settings.mcpEnabled || settings.mcpUrl.isEmpty) {
    return null;
  }
  return SearxngClient(baseUrl: settings.mcpUrl);
});

/// MCPツールサービスプロバイダー
///
/// MCPサーバーからツールを動的に取得・実行するサービスを提供。
/// SearXNGへのフォールバックも含む。
final mcpToolServiceProvider = Provider<McpToolService?>((ref) {
  final mcpClient = ref.watch(mcpClientProvider);
  final searxngClient = ref.watch(searxngClientProvider);
  // ローカル内蔵ツール（日時取得）を常に使えるように、クライアント未設定でも提供する。
  return McpToolService(mcpClient: mcpClient, searxngClient: searxngClient);
});
