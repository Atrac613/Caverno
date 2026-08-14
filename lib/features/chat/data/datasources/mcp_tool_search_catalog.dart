import '../../domain/services/tool_definition_search_service.dart';

final class McpToolSearchCatalog {
  const McpToolSearchCatalog._();

  static List<Map<String, dynamic>> finalize(
    List<Map<String, dynamic>> definitions, {
    required bool hasSearxngClient,
    required Map<String, dynamic> webSearchFallback,
    required Set<String> disabledBuiltInTools,
  }) {
    final hasWebSearch = definitions.any(
      (definition) =>
          ToolDefinitionSearchService.toolNameFromDefinition(definition) ==
          'web_search',
    );
    if (hasSearxngClient &&
        !hasWebSearch &&
        !disabledBuiltInTools.contains('web_search')) {
      definitions.add(webSearchFallback);
    }
    return ToolDefinitionSearchService.appendSearchToolIfUseful(definitions);
  }
}
