import 'dart:convert';

import '../entities/tool_call_info.dart';

/// Classifies file-mutation evidence without relying on notifier state.
final class FileMutationEvidencePolicy {
  const FileMutationEvidencePolicy();

  bool isMutationToolName(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'write_file':
      case 'edit_file' || 'delete_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
  }

  bool isSuccessfulResult(ToolResultInfo toolResult) {
    final normalized = toolResult.result.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.startsWith('error:') ||
        normalized.startsWith('auto-review denied')) {
      return false;
    }
    try {
      final decoded = jsonDecode(toolResult.result);
      if (decoded is! Map<String, dynamic>) return true;
      if (decoded['error'] != null) return false;
      if (decoded['already_applied'] == true) return false;
      final code = decoded['code']?.toString().trim().toLowerCase();
      if (code == 'permission_denied' ||
          code == 'bookmark_restore_failed' ||
          code == 'tool_execution_failed') {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  String? resultPayloadPath(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        final path = decoded['path'];
        if (path is String && path.trim().isNotEmpty) return path.trim();
      }
    } catch (_) {}
    return null;
  }

  String? argumentPath(Object? arguments) {
    if (arguments is! Map) return null;
    final rawPath = arguments['path'];
    if (rawPath is! String) return null;
    final path = rawPath.trim();
    return path.isEmpty ? null : path;
  }

  String? pathForResult(ToolResultInfo toolResult) =>
      resultPayloadPath(toolResult.result) ??
      argumentPath(toolResult.arguments);
}
