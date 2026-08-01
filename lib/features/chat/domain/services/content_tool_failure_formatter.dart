import 'dart:convert';

// ChatNotifier decomposition collaborator: content-tool-failure-formatter
final class ContentToolFailureFormatter {
  const ContentToolFailureFormatter();

  String format(String toolName, String? errorMessage) {
    final error = (errorMessage ?? 'Tool execution failed').trim();
    return jsonEncode({
      'toolName': toolName,
      'error': error,
      'code': _failureCode(error),
    });
  }

  String _failureCode(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    if (normalized.contains('no matching tool available')) {
      return 'tool_not_available';
    }
    if (normalized.contains('old_text was not found in the target file')) {
      return 'edit_mismatch';
    }
    if (normalized.contains('permission_denied')) {
      return 'permission_denied';
    }
    if (normalized.contains('timeout')) {
      return 'timeout';
    }
    return 'tool_execution_failed';
  }
}
