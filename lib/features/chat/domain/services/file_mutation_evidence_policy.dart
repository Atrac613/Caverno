import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_path_resolver.dart';

/// Classifies file-mutation evidence without relying on notifier state.
final class FileMutationEvidencePolicy {
  const FileMutationEvidencePolicy();

  static const _mutationToolNames = {
    'write_file',
    'edit_file',
    'delete_file',
    'rollback_last_file_change',
  };

  bool isMutationToolName(String toolName) =>
      _mutationToolNames.contains(toolName.trim().toLowerCase());

  bool isSuccessfulResult(ToolResultInfo toolResult) {
    if (toolResult.outcome?.fileMutations.isNotEmpty == true) {
      return true;
    }
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

  String? resultPayloadPath(String result) =>
      FileMutationEvidencePathResolver.resultPayloadPath(result);

  String? argumentPath(Object? arguments) =>
      FileMutationEvidencePathResolver.argumentPath(arguments);

  String? pathForResult(ToolResultInfo result) =>
      FileMutationEvidencePathResolver.pathForResult(result);
}
