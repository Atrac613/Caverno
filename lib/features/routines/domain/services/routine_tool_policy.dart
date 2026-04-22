import 'dart:convert';

import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/services/tool_result_prompt_builder.dart';

class RoutineToolPolicy {
  RoutineToolPolicy._();

  static const Set<String> _allowedToolNames = {
    'get_current_datetime',
    'search_past_conversations',
    'recall_memory',
    'ping',
    'ping6',
    'arp',
    'ndp',
    'route_lookup',
    'interface_info',
    'whois_lookup',
    'dns_lookup',
    'dns_query',
    'port_check',
    'ssl_certificate',
    'http_status',
    'http_get',
    'http_head',
    'traceroute',
    'path_mtu',
    'mdns_browse',
    'web_search',
    'searxng_web_search',
    'web_url_read',
    'list_directory',
    'read_file',
    'find_files',
    'search_files',
    'wifi_scan',
    'wifi_get_scan_results',
    'wifi_get_connection_info',
    'lan_scan',
    'lan_get_scan_results',
  };

  static bool isAllowedToolName(String toolName) {
    return _allowedToolNames.contains(toolName);
  }

  static List<Map<String, dynamic>> filterAllowedToolDefinitions(
    List<Map<String, dynamic>> definitions,
  ) {
    final filtered = definitions
        .where((tool) {
          final name = (tool['function'] as Map?)?['name'] as String?;
          return name != null && isAllowedToolName(name);
        })
        .toList(growable: false);

    return ToolResultPromptBuilder.dedupeToolsByName(filtered);
  }

  static McpToolResult buildDeniedResult(ToolCallInfo toolCall) {
    final payload = jsonEncode({
      'error':
          'Routine execution allows only read-only tools. This tool is not '
          'available in routines.',
      'code': 'permission_denied',
      'reason': 'routine_requires_read_only_tools',
      'tool': toolCall.name,
    });

    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Routine blocked non-read-only tool execution',
    );
  }

  static McpToolResult buildUnavailableResult(ToolCallInfo toolCall) {
    final payload = jsonEncode({
      'error':
          'Tools are currently unavailable. Enable MCP/search support and try '
          'again later.',
      'code': 'tool_unavailable',
      'reason': 'routine_tool_service_unavailable',
      'tool': toolCall.name,
    });

    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Routine tool service is unavailable',
    );
  }
}
