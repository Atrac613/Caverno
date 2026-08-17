import '../../domain/entities/mcp_tool_entity.dart';
import 'local_shell_tools.dart';
import 'mcp_tool_result_normalizer.dart';

/// Rejects git write commands smuggled into `local_execute_command`.
///
/// Direct git writes bypass the repository safety preflights that
/// `git_execute_command` runs, so the shell layer refuses them outright. The
/// approval path consults this guard too: asking the user (or auto-review) to
/// authorize a call that can never execute spends a round trip on a decision
/// that is already made.
abstract final class LocalShellGitWriteGuard {
  static const String errorMessage =
      'Use git_execute_command for git write commands';

  /// Returns a failure result when [arguments] embed a direct git write.
  ///
  /// Returns null when the call carries no git write, or when it is missing
  /// the fields needed to tell — validation of those belongs to the caller.
  static McpToolResult? evaluate({
    required String toolName,
    required Map<String, dynamic> arguments,
  }) {
    final command = LocalShellTools.normalizeCommand(
      (arguments['command'] as String?)?.trim() ?? '',
    );
    final workingDirectory =
        (arguments['working_directory'] as String?)?.trim() ?? '';
    if (command.isEmpty || workingDirectory.isEmpty) {
      return null;
    }
    return resultFor(
      toolName: toolName,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  /// Same decision as [evaluate] for callers that already parsed the command.
  static McpToolResult? resultFor({
    required String toolName,
    required String command,
    required String workingDirectory,
  }) {
    final blocked = LocalShellTools.gitWriteCommandBlockedResult(
      command: command,
      workingDirectory: workingDirectory,
    );
    if (blocked == null) {
      return null;
    }
    return McpToolResultNormalizer.failure(
      toolName: toolName,
      result: blocked,
      errorMessage: errorMessage,
    );
  }
}
