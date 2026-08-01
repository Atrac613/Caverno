import 'dart:convert';

import '../../data/datasources/filesystem_path_resolver.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'conversation_plan_execution_guardrails.dart';
import 'file_mutation_evidence_policy.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: saved-task-target-scope-guard

/// Immutable owner snapshots used for one saved-task target-scope decision.
final class SavedTaskTargetScopeInput {
  SavedTaskTargetScopeInput({
    required this.owner,
    required ToolCallInfo toolCall,
    required ConversationWorkflowTask? ownerTask,
    required this.ownerProjectRoot,
  }) : toolCall = _freezeToolCall(toolCall),
       ownerTask = _freezeTask(ownerTask);

  final ChatTurnOwner owner;
  final ToolCallInfo toolCall;
  final ConversationWorkflowTask? ownerTask;
  final String? ownerProjectRoot;
}

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

ToolCallInfo _freezeToolCall(ToolCallInfo source) {
  return ToolCallInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  );
}

ConversationWorkflowTask? _freezeTask(ConversationWorkflowTask? source) {
  if (source == null) return null;
  return source.copyWith(
    targetFiles: List<String>.unmodifiable(source.targetFiles),
  );
}
