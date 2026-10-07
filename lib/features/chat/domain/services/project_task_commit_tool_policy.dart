import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../project_farm/domain/entities/project_task_commit_scope.dart';
import '../../data/datasources/git_tools.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

/// Limits commit-phase tools to the accepted task scope and phase.
final class ProjectTaskCommitToolPolicy {
  const ProjectTaskCommitToolPolicy();
  static Set<String> toolNames({required bool preparing}) {
    return {
      'read_file',
      'inspect_file',
      'list_directory',
      'find_files',
      'search_files',
      'git_execute_command',
      if (preparing) ...{'write_file', 'edit_file'},
    };
  }

  static McpToolResult failure(String name, String reason) => McpToolResult(
    toolName: name,
    isSuccess: false,
    result: jsonEncode({
      'ok': false,
      'code': 'project_task_commit_precondition_failed',
      ...ToolResultOrigin.refusal.marker,
      'error': reason,
    }),
    errorMessage: reason,
  );

  McpToolResult? enforce(
    ToolCallInfo call, {
    required ProjectTaskCommitScope? scope,
    required String? conversationId,
    required String? root,
    required bool preparing,
    required Set<String> allowedNames,
  }) {
    if (scope == null ||
        root == null ||
        scope.conversationId != conversationId ||
        scope.resolve(root) != scope.projectRoot) {
      return failure(
        call.name,
        'Native task commit scope is unavailable for this owner.',
      );
    }
    if (!allowedNames.contains(call.name)) {
      return failure(
        call.name,
        'This tool cannot run in task commit preparation or execution.',
      );
    }
    if (call.name == 'write_file' || call.name == 'edit_file') {
      final raw = call.arguments['path'] ?? call.arguments['file_path'];
      if (!preparing ||
          raw is! String ||
          scope.resolve(raw) != scope.roadmapPath) {
        return failure(
          call.name,
          'Only the cited roadmap may be edited during commit preparation.',
        );
      }
    }
    if (call.name != 'git_execute_command') return null;
    final rawCommand = call.arguments['command'];
    final command = rawCommand is String ? rawCommand : '';
    final args = GitTools.splitArgs(GitTools.normalizeCommand(command));
    final workingDirectory = call.arguments['working_directory'] ?? '.';
    if (workingDirectory is! String ||
        scope.resolve(workingDirectory) != scope.projectRoot ||
        args.isEmpty ||
        GitTools.firstShellControlOperator(command) != null) {
      return failure(
        call.name,
        'The Git command must use this task repository without shell operators.',
      );
    }
    if (GitTools.isReadOnly(command)) return null;
    final stageOnly =
        preparing &&
        args.length > 2 &&
        args[0] == 'add' &&
        args[1] == '--' &&
        args.skip(2).every((file) => scope.paths.contains(scope.resolve(file)));
    final commitOnly =
        !preparing &&
        scope.prepared != null &&
        args.length >= 5 &&
        args.first == 'commit' &&
        args.length.isOdd &&
        [
          for (var i = 1; i < args.length; i += 2) args[i],
        ].every((flag) => flag == '-m');
    return stageOnly || commitOnly
        ? null
        : failure(
            call.name,
            preparing
                ? 'Prepare the roadmap and named task files first; commits are forbidden in this turn.'
                : 'Only a new commit of the accepted index is permitted; edits, staging and history changes are forbidden.',
          );
  }
}
