import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../data/datasources/filesystem_path_resolver.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import 'conversation_plan_execution_guardrails.dart';
import 'file_mutation_evidence_policy.dart';
import 'saved_task_target_scope_input.dart';

export 'saved_task_target_scope_input.dart';

// ChatNotifier decomposition collaborator: saved-task-target-scope-guard

/// Blocks file mutations outside one explicitly supplied saved task.
final class SavedTaskTargetScopeGuard {
  const SavedTaskTargetScopeGuard();

  static const blockedCode = 'saved_task_target_scope_violation';
  static const _fileMutationEvidencePolicy = FileMutationEvidencePolicy();

  McpToolResult? evaluate(SavedTaskTargetScopeInput input) {
    final toolName = input.toolCall.name.trim().toLowerCase();
    if (toolName != 'write_file' && toolName != 'edit_file') return null;

    final task = input.ownerTask;
    if (task == null || task.targetFiles.isEmpty) return null;
    // A completed task no longer scopes anything. `validationTask` picks the
    // first task carrying a validation command without looking at status, so
    // once every task finished, session a0ca65b7 stayed pinned to task 1
    // (`index.html, js/main.js`) and every later mutation the user asked for —
    // 19 of them, against `js/player.js` and `js/cave.js` — was refused for
    // the rest of the thread's life.
    if (task.status == ConversationWorkflowTaskStatus.completed) return null;
    final allowedTargetFiles = allowedTargetFilesForTask(task);
    final path = _fileMutationEvidencePolicy.argumentPath(
      input.toolCall.arguments,
    );
    if (path == null ||
        allowsPath(
          path: path,
          targetFiles: allowedTargetFiles,
          projectRoot: input.ownerProjectRoot,
        )) {
      return null;
    }

    return McpToolResult(
      toolName: input.toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': blockedCode,
        ...ToolResultOrigin.refusal.marker,
        'error':
            'A file mutation was blocked because it targeted a file outside '
            'the active saved task target files.',
        'task_id': task.id,
        'task_title': task.title,
        'attempted_path': path,
        'allowed_target_files': allowedTargetFiles,
        'required_action':
            'Modify only the active saved task target files, or finish the '
            'current saved task before starting work on another file.',
      }),
      isSuccess: false,
      errorMessage: 'File mutation is outside the active saved task targets.',
    );
  }

  List<String> allowedTargetFilesForTask(ConversationWorkflowTask task) {
    return List<String>.unmodifiable({
      ...task.targetFiles,
      ...ConversationPlanExecutionGuardrails.validationExecutablePathsForTask(
        task,
      ),
    });
  }

  bool allowsPath({
    required String path,
    required Iterable<String> targetFiles,
    required String? projectRoot,
  }) {
    final normalizedPath = normalizePath(path, projectRoot: projectRoot);
    if (normalizedPath == null) return true;

    for (final targetFile in targetFiles) {
      final target = targetFile.trim();
      if (target.isEmpty) continue;
      final normalizedTarget = normalizePath(target, projectRoot: projectRoot)!;
      if (normalizedPath == normalizedTarget) return true;
      if ((target.endsWith('/') || target.endsWith('\\')) &&
          normalizedPath.startsWith('$normalizedTarget/')) {
        return true;
      }
    }
    return false;
  }

  String? normalizePath(String path, {required String? projectRoot}) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final resolved = FilesystemPathResolver.resolve(
      trimmed,
      defaultRoot: projectRoot,
    );
    var normalized = (resolved ?? trimmed).replaceAll('\\', '/').trim();
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }
}
