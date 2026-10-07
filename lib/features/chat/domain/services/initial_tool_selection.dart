import '../../../../core/utils/logger.dart';
import 'tool_definition_search_service.dart';

/// Selects a full stable catalogue or the initial searchable tool set.
final class InitialToolSelection {
  const InitialToolSelection();
  ToolDefinitionSearchSelection select(
    List<Map<String, dynamic>> tools,
    bool prefixStable,
  ) {
    final selection = prefixStable
        ? ToolDefinitionSearchSelection(
            toolSearchEnabled: false,
            toolDefinitions: tools,
            selectedToolNames:
                ToolDefinitionSearchService.toolNamesFromDefinitions(tools),
          )
        : ToolDefinitionSearchService.buildInitialSelection(tools);
    if (prefixStable) {
      appLog(
        '[Tool] Prefix-stable tool loop enabled; using a fixed full tool list',
      );
    }
    if (selection.toolSearchEnabled) {
      appLog(
        '[ToolSearch] Enabled dynamic tool loading. Initial tools: '
        '${ToolDefinitionSearchService.toolNamesFromDefinitions(selection.toolDefinitions).toList()}',
      );
    }
    return selection;
  }
}
