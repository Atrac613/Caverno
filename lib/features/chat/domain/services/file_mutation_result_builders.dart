import 'dart:convert';

import '../entities/mcp_tool_entity.dart';

McpToolResult fileMutationFailure(String toolName, String message) {
  return McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

McpToolResult fileMutationAutoReviewDenied(String toolName, String rationale) {
  return McpToolResult(
    toolName: toolName,
    result: 'Auto-review denied this action. Rationale: $rationale',
    isSuccess: false,
    errorMessage: 'Auto-review denied: $rationale',
  );
}

McpToolResult fileMutationDeleteNotRegularFile(String toolName, String path) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': 'delete_target_not_regular_file',
      'error': 'delete_file supports existing regular files only.',
      'path': path,
    }),
    isSuccess: false,
    errorMessage: 'Delete target must be a regular file',
  );
}

McpToolResult fileMutationDeleteSnapshotUnavailable(
  String toolName,
  String path,
) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': 'delete_snapshot_unavailable',
      'error':
          'The file cannot be deleted because a rollback snapshot could not be captured.',
      'path': path,
    }),
    isSuccess: false,
    errorMessage: 'A rollback snapshot is required before deletion',
  );
}

McpToolResult fileMutationChangedSinceApproval({
  required String toolName,
  required String path,
}) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': 'file_changed_since_approval',
      'error':
          'The target file changed after the approval preview was prepared. Re-read the file and submit a fresh mutation.',
      'path': path,
    }),
    isSuccess: false,
    errorMessage: 'The target file changed after approval',
  );
}

bool isSuccessfulFileMutationResult(McpToolResult result) {
  if (!result.isSuccess) {
    return false;
  }
  try {
    final decoded = jsonDecode(result.result);
    return decoded is! Map<String, dynamic> ||
        (decoded['error'] == null && decoded['already_applied'] != true);
  } catch (_) {
    return true;
  }
}
