import '../../domain/services/tool_definition_search_service.dart';

final class McpToolSearchCatalog {
  const McpToolSearchCatalog._();

  /// Finishes the catalog handed to the model.
  ///
  /// Caverno used to append its own `web_search` here, backed by a SearXNG
  /// client pointed at the primary MCP URL. That could only work where the
  /// first MCP server also served SearXNG's `/search` JSON API on the same
  /// port, and it was gated on MCP being configured at all -- so it never
  /// covered the one case a fallback is for. Meanwhile the guard that was
  /// supposed to suppress it matched the name `web_search` exactly, and the
  /// SearXNG MCP wrapper calls its tool `search_web`, so both appeared and the
  /// model picked the broken one (session cad9b37c). Search now comes from MCP
  /// only.
  static List<Map<String, dynamic>> finalize(
    List<Map<String, dynamic>> definitions,
  ) {
    return ToolDefinitionSearchService.appendSearchToolIfUseful(definitions);
  }
}
