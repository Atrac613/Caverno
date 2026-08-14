import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import 'project_scoped_read_tool_contract.dart';

McpToolResult projectScopedReadExpiryResult(
  ProjectScopedReadToolRequest request,
) {
  final processObservation = const {
    'process_status',
    'process_tail',
    'process_wait',
    'process_list',
  }.contains(request.toolName);
  final message = processObservation
      ? 'The background process observation may belong to an expired or '
            'different tool call'
      : 'The turn owner expired before the read completed';
  return McpToolResult(
    toolName: request.toolName,
    result: jsonEncode({
      'ok': false,
      'code': processObservation
          ? 'background_process_observation_uncertain'
          : 'turn_owner_expired',
      'error': '$message.',
      'next_action': processObservation
          ? 'Repeat the observation with the exact job_id before relying '
                'on process status or output.'
          : 'Repeat the read in the current turn.',
    }),
    isSuccess: false,
    errorMessage: message,
  );
}
