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
  /// de-duplicated by name to match the parent loop's tool shaping.
  static List<Map<String, dynamic>> filterInheritedToolDefinitions(
    List<Map<String, dynamic>> parentDefinitions,
  ) {
    final filtered = parentDefinitions
        .where((tool) => toolName(tool) != spawnSubagentToolName)
        .toList(growable: false);
    return ToolResultPromptBuilder.dedupeToolsByName(filtered);
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
