import 'dart:convert';

import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'tool_definition_search_service.dart';

typedef PlanningToolArgumentResolver =
    Map<String, dynamic> Function(
      String toolName,
      Map<String, dynamic> arguments,
    );

class PlanningToolPolicy {
  const PlanningToolPolicy();

  McpToolResult? enforce(
    ToolCallInfo toolCall, {
    required bool isPlanningSession,
    required PlanningToolArgumentResolver resolveArguments,
  }) {
    if (!isPlanningSession) {
      return null;
    }

    if (MacosComputerUseToolPolicy.isComputerUseTool(toolCall.name)) {
      return MacosComputerUseToolPolicy.isAllowedInPlanning(toolCall.name)
          ? null
          : _buildDeniedResult(
              toolCall,
              detail:
                  'Planning mode allows only macOS computer-use observation tools.',
            );
    }

    switch (toolCall.name) {
      case 'list_directory':
      case 'read_file':
      case 'inspect_file':
      case 'find_files':
      case 'search_files':
      case ToolDefinitionSearchService.toolName:
      case 'get_current_datetime':
      case 'ask_user_question':
      case 'os_get_system_info':
      case 'process_status':
      case 'process_tail':
      case 'process_wait':
      case 'search_past_conversations':
      case 'recall_memory':
      case 'ping':
      case 'whois_lookup':
      case 'dns_lookup':
      case 'port_check':
      case 'ssl_certificate':
      case 'http_status':
      case 'http_get':
      case 'http_head':
      case 'web_search':
      case 'web_url_read':
      case 'wifi_scan':
      case 'wifi_get_scan_results':
      case 'wifi_get_connection_info':
      case 'os_log_read':
      case 'lan_scan':
      case 'lan_get_scan_results':
        return null;
      case 'local_execute_command':
        final command = _localCommand(toolCall, resolveArguments);
        return LocalShellTools.isReadOnly(command)
            ? null
            : _buildDeniedResult(
                toolCall,
                detail: command.isEmpty
                    ? 'Planning mode only allows read-only local commands.'
                    : 'Planning mode blocked local command: $command',
              );
      case 'process_start':
        return _buildDeniedResult(
          toolCall,
          detail: 'Planning mode cannot start background processes.',
        );
      case 'process_cancel':
        return _buildDeniedResult(
          toolCall,
          detail: 'Planning mode cannot cancel background processes.',
        );
      case 'git_execute_command':
        final command = _gitCommand(toolCall, resolveArguments);
        return GitTools.isReadOnly(command)
            ? null
            : _buildDeniedResult(
                toolCall,
                detail: command.isEmpty
                    ? 'Planning mode only allows read-only git commands.'
                    : 'Planning mode blocked git command: git $command',
              );
      case 'git_finish_worktree_session':
        return _buildDeniedResult(
          toolCall,
          detail: 'Planning mode cannot merge or remove git worktree sessions.',
        );
      default:
        return _isDeniedToolName(toolCall.name)
            ? _buildDeniedResult(toolCall)
            : null;
    }
  }

  String _localCommand(
    ToolCallInfo toolCall,
    PlanningToolArgumentResolver resolveArguments,
  ) {
    final resolvedArguments = resolveArguments(
      toolCall.name,
      toolCall.arguments,
    );
    return LocalShellTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
  }

  String _gitCommand(
    ToolCallInfo toolCall,
    PlanningToolArgumentResolver resolveArguments,
  ) {
    final resolvedArguments = resolveArguments(
      toolCall.name,
      toolCall.arguments,
    );
    return GitTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
  }

  bool _isDeniedToolName(String toolName) {
    if (toolName.startsWith('ssh_') || toolName.startsWith('ble_')) {
      return true;
    }
    if (toolName.startsWith('computer_')) {
      return !MacosComputerUseToolPolicy.isAllowedInPlanning(toolName);
    }

    return switch (toolName) {
      'write_file' ||
      'edit_file' ||
      'delete_file' ||
      'rollback_last_file_change' ||
      'run_tests' ||
      'http_post' ||
      'http_put' ||
      'http_patch' ||
      'http_delete' => true,
      _ => false,
    };
  }

  McpToolResult _buildDeniedResult(ToolCallInfo toolCall, {String? detail}) {
    final payload = jsonEncode({
      'error':
          'Planning mode allows only read-only tools. Approve the plan and '
          'start implementation before retrying this action.',
      'code': 'permission_denied',
      'reason': 'planning_mode_requires_read_only_tools',
      'tool': toolCall.name,
      if (detail != null && detail.isNotEmpty) 'detail': detail,
    });

    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage:
          detail ?? 'Planning mode blocks non-read-only tool execution',
    );
  }
}
