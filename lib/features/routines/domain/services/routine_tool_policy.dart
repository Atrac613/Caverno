import 'dart:convert';

import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/services/tool_result_prompt_builder.dart';

class RoutineToolPolicy {
  RoutineToolPolicy._();

  static const String routineToolDefinitionKey = 'x-caverno-routine-tool';

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
    'explain_network_slowdown_context',
    'get_latest_summary',
    'compare_recent_windows',
    'get_capture_health',
    'get_dns_health',
    'get_conn_overview',
    'get_weird_events',
    'get_notice_events',
  };

  static const Set<String> _workspaceWriteToolNames = {
    'write_file',
    'edit_file',
  };

  static const Set<String> _workspaceReadToolNames = {
    'list_directory',
    'read_file',
    'find_files',
    'search_files',
  };

  static bool isAllowedToolName(String toolName) {
    if (_allowedToolNames.contains(toolName)) {
      return true;
    }
    if (MacosComputerUseToolPolicy.isAllowedInPlanning(toolName)) {
      return true;
    }

    final namespaceIndex = toolName.indexOf('__');
    if (namespaceIndex <= 0) {
      return false;
    }
    return _allowedToolNames.contains(toolName.substring(0, namespaceIndex));
  }

  static bool isComputerUseObservationToolName(String toolName) {
    return MacosComputerUseToolPolicy.isAllowedInPlanning(toolName);
  }

  static bool isComputerUseActionToolName(String toolName) {
    return MacosComputerUseToolPolicy.isComputerUseTool(toolName) &&
        MacosComputerUseToolPolicy.requiresUserApproval(toolName);
  }

  static bool isWorkspaceWriteToolName(String toolName) {
    return _workspaceWriteToolNames.contains(toolName);
  }

  static bool isWorkspaceReadToolName(String toolName) {
    return _workspaceReadToolNames.contains(toolName);
  }

  static bool isWorkspacePathToolName(String toolName) {
    return isWorkspaceReadToolName(toolName) ||
        isWorkspaceWriteToolName(toolName);
  }

  static List<Map<String, dynamic>> filterAllowedToolDefinitions(
    List<Map<String, dynamic>> definitions, {
    bool allowWorkspaceWrites = false,
    Set<String> allowedComputerUseActionToolNames = const <String>{},
    List<Map<String, dynamic>> extraDefinitions = const [],
  }) {
    final filtered = [...definitions, ...extraDefinitions]
        .where((tool) {
          final name = (tool['function'] as Map?)?['name'] as String?;
          return name != null &&
              (isExternalMcpToolDefinition(tool) ||
                  isRoutineToolDefinition(tool) ||
                  isAllowedToolName(name) ||
                  allowedComputerUseActionToolNames.contains(name) ||
                  (allowWorkspaceWrites && isWorkspaceWriteToolName(name)));
        })
        .toList(growable: false);

    return ToolResultPromptBuilder.dedupeToolsByName(filtered);
  }

  static bool isExternalMcpToolDefinition(Map<String, dynamic> tool) {
    return tool[McpToolEntity.openAiExternalToolKey] == true;
  }

  static bool isRoutineToolDefinition(Map<String, dynamic> tool) {
    return tool[routineToolDefinitionKey] == true;
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

  static McpToolResult buildComputerUseActionDeniedResult(
    ToolCallInfo toolCall,
  ) {
    final payload = jsonEncode({
      'error':
          'Routine execution allows Computer Use action tools only when a '
          'matching routine allowlist entry exists. Pointer, keyboard, focus, '
          'audio, and public-action tools require interactive user approval '
          'unless they are explicitly allowlisted for unattended routines.',
      'code': 'permission_denied',
      'reason': 'routine_computer_use_action_denied',
      'tool': toolCall.name,
    });

    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Routine blocked a Computer Use action tool',
    );
  }

  static McpToolResult buildWorkspaceWriteDeniedResult(
    ToolCallInfo toolCall, {
    required String workspaceDirectory,
    String? attemptedPath,
  }) {
    final payload = jsonEncode({
      'error':
          'Routine write tools can only write inside the configured workspace '
          'directory.',
      'code': 'permission_denied',
      'reason': 'routine_workspace_write_denied',
      'tool': toolCall.name,
      'workspace_directory': workspaceDirectory,
      if (attemptedPath != null && attemptedPath.isNotEmpty)
        'attempted_path': attemptedPath,
    });

    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Routine blocked a write outside the workspace directory',
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
