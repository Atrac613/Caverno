import '../../domain/entities/mcp_tool_entity.dart';

/// First-party tools another feature contributes to the built-in catalogue.
///
/// Lets a feature such as the project dashboard (FARM2) offer tools without
/// `McpToolService` depending on it. Unlike an MCP server, an extension is
/// first-party: its results are not classified as third-party provenance.
abstract interface class BuiltInToolExtension {
  /// OpenAI-style function definitions, offered after the core built-ins.
  List<Map<String, dynamic>> get definitions;

  /// The names [execute] answers for.
  Set<String> get toolNames;

  Future<McpToolResult> execute(String name, Map<String, dynamic> arguments);
}
