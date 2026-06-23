import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

class ParticipantToolPolicy {
  const ParticipantToolPolicy();

  static const Set<String> allowedToolNames = {
    'web_search',
    'searxng_web_search',
    'get_current_datetime',
    'search_past_conversations',
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
  };

  List<Map<String, dynamic>> filterDefinitions(
    List<Map<String, dynamic>> definitions,
  ) {
    final seen = <String>{};
    final filtered = <Map<String, dynamic>>[];
    for (final definition in definitions) {
      final name = toolNameFromDefinition(definition);
      if (name == null || !isAllowedToolName(name) || !seen.add(name)) {
        continue;
      }
      filtered.add(definition);
    }
    return filtered;
  }

  McpToolResult? enforce(ToolCallInfo toolCall) {
    if (isAllowedToolName(toolCall.name)) {
      return null;
    }
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'error':
            'Participant tool calls are limited to search, datetime, past '
            'conversation search, and read-only inspection tools.',
        'code': 'permission_denied',
        'reason': 'participant_tools_require_read_only_allowlist',
        'tool': toolCall.name,
      }),
      isSuccess: false,
      errorMessage: 'Participant tools do not allow ${toolCall.name}.',
    );
  }

  bool isAllowedToolName(String name) {
    return allowedToolNames.contains(name.trim().toLowerCase());
  }

  static String? toolNameFromDefinition(Map<String, dynamic> definition) {
    final function = definition['function'];
    if (function is! Map) return null;
    final name = function['name'];
    if (name is! String) return null;
    final trimmed = name.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
