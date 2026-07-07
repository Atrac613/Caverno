import 'tool_definition_search_service.dart';
import 'tool_result_prompt_builder.dart';

/// Tool-access policy for delegated subagents.
///
/// A subagent inherits the parent's enabled tools so it can do real work, but
/// the delegation tool itself ([spawnSubagentToolName]) is stripped so a child
/// cannot spawn further children. This fixes delegation depth at 1 and prevents
/// unbounded fan-out. High-risk tools (file writes, shell, git, ssh, computer
/// use) stay in the inherited set on purpose — they are escalated to the user's
/// approval dialog at dispatch time, exactly like the parent loop.
class SubagentToolPolicy {
  SubagentToolPolicy._();

  /// Tool name that must never be visible to a child subagent.
  static const String spawnSubagentToolName = 'spawn_subagent';

  /// Returns the parent tool definitions with the delegation tool removed,
  /// de-duplicated by name and curated to the parent loop's tool shaping.
  ///
  /// When the inherited catalog is large enough to enable tool-search it is
  /// narrowed to the same initial selection the parent loop starts from.
  /// Passing the full catalog (~166 tools) instead overflows a 32768-token
  /// model context and fails every subagent request with HTTP 400; the
  /// subagent can still widen its set at runtime via tool-search, which the
  /// initial selection keeps available. Smaller catalogs are returned intact,
  /// so behaviour below the tool-search threshold is unchanged.
  static List<Map<String, dynamic>> filterInheritedToolDefinitions(
    List<Map<String, dynamic>> parentDefinitions,
  ) {
    final filtered = parentDefinitions
        .where((tool) => toolName(tool) != spawnSubagentToolName)
        .toList(growable: false);
    final deduped = ToolResultPromptBuilder.dedupeToolsByName(filtered);
    if (!ToolDefinitionSearchService.shouldEnableToolSearch(deduped)) {
      return deduped;
    }
    return ToolDefinitionSearchService.buildInitialSelection(
      deduped,
    ).toolDefinitions;
  }

  /// Extracts the function name from an OpenAI-style tool definition.
  static String toolName(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is Map<String, dynamic>) {
      final name = function['name'];
      if (name is String) return name;
    }
    final name = tool['name'];
    return name is String ? name : '';
  }
}
