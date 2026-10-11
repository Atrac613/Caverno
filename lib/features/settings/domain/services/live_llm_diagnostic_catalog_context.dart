import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../entities/live_llm_diagnostic.dart';

/// Projects acquired tools into initial selection and diagnostic report metadata.
class LiveLlmDiagnosticCatalogContext {
  const LiveLlmDiagnosticCatalogContext._({
    required this.definitions,
    required this.initialDefinitions,
    required this.selectedToolNames,
    required this.toolSearchEnabled,
    required this.catalog,
  });

  factory LiveLlmDiagnosticCatalogContext.empty(String connectionSummary) {
    return LiveLlmDiagnosticCatalogContext._(
      definitions: const [],
      initialDefinitions: const [],
      selectedToolNames: const {},
      toolSearchEnabled: false,
      catalog: LiveLlmDiagnosticToolCatalog(
        mcpConnectionSummary: connectionSummary,
      ),
    );
  }

  factory LiveLlmDiagnosticCatalogContext.fromDefinitions(
    List<Map<String, dynamic>> definitions, {
    required int remoteServerCount,
    required String connectionSummary,
  }) {
    final initialSelection = ToolDefinitionSearchService.buildInitialSelection(
      definitions,
    );
    final toolNames = _toolNames(definitions);
    final initialToolNames = _toolNames(initialSelection.toolDefinitions);
    final remoteToolNames = definitions
        .where(_isRemoteMcpTool)
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .whereType<String>()
        .toList(growable: false);
    return LiveLlmDiagnosticCatalogContext._(
      definitions: definitions,
      initialDefinitions: initialSelection.toolDefinitions,
      selectedToolNames: initialSelection.selectedToolNames,
      toolSearchEnabled: initialSelection.toolSearchEnabled,
      catalog: LiveLlmDiagnosticToolCatalog(
        totalToolCount: definitions.length,
        initialToolCount: initialSelection.toolDefinitions.length,
        remoteToolCount: remoteToolNames.length,
        remoteServerCount: remoteServerCount,
        toolSearchEnabled: initialSelection.toolSearchEnabled,
        toolNames: toolNames,
        initialToolNames: initialToolNames,
        remoteToolNames: remoteToolNames,
        mcpConnectionSummary: connectionSummary,
      ),
    );
  }

  final List<Map<String, dynamic>> definitions;
  final List<Map<String, dynamic>> initialDefinitions;
  final Set<String> selectedToolNames;
  final bool toolSearchEnabled;
  final LiveLlmDiagnosticToolCatalog catalog;

  static List<String> _toolNames(Iterable<Map<String, dynamic>> definitions) {
    return definitions
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .whereType<String>()
        .toList(growable: false);
  }

  static bool _isRemoteMcpTool(Map<String, dynamic> definition) {
    return definition[McpToolEntity.openAiExternalToolKey] == true;
  }
}
