import 'dart:convert';

import '../entities/mcp_tool_entity.dart';

final class BackgroundProcessToolResults {
  const BackgroundProcessToolResults();

  McpToolResult missingProcessId(String toolName) => _result(
    toolName,
    '{"ok":false,"code":"job_id_required","error":"job_id is required"}',
    errorMessage: 'job_id is required',
  );

  McpToolResult processNotFound(String toolName, String processId) {
    final error = 'No background process job exists for job_id: $processId';
    return _result(
      toolName,
      '{"ok":false,"code":"job_not_found","job_id":'
      '${jsonEncode(processId)},"error":${jsonEncode(error)}}',
      isSuccess: true,
    );
  }

  McpToolResult outsideProject(String toolName) => _result(
    toolName,
    '{"code":"working_directory_outside_project",'
    '"error":"working_directory must resolve inside the selected coding project"}',
    errorMessage:
        'working_directory must resolve inside the selected coding project',
  );

  McpToolResult autoReviewDenied(String toolName, String rationale) => _result(
    toolName,
    'Auto-review denied this action. Rationale: $rationale',
    errorMessage: 'Auto-review denied: $rationale',
  );

  McpToolResult expired(String toolName) =>
      failure(toolName, 'The approval turn expired before execution');

  McpToolResult effectUncertain(String toolName) => failure(
    toolName,
    'The background process action may have completed after its owner '
    'expired; inspect the process and possible side effects before retrying',
  );

  McpToolResult requireToolName(McpToolResult result, String toolName) {
    if (result.toolName != toolName) {
      throw StateError('Background process result tool name mismatch.');
    }
    return result;
  }

  McpToolResult failure(String toolName, String message) =>
      _result(toolName, '', errorMessage: message);

  McpToolResult _result(
    String toolName,
    String result, {
    bool isSuccess = false,
    String? errorMessage,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: result,
      isSuccess: isSuccess,
      errorMessage: errorMessage,
    );
  }
}
