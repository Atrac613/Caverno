import '../../domain/entities/mcp_tool_entity.dart';
import 'local_command_mutation_guard.dart';
import 'local_shell_tools.dart';

final class BuiltInLocalCommandMutationPreflight {
  const BuiltInLocalCommandMutationPreflight({
    this.deniedResult,
    required this.arguments,
  });

  final McpToolResult? deniedResult;
  final Map<String, dynamic> arguments;
}

Future<BuiltInLocalCommandMutationPreflight>
authorizeBuiltInLocalCommandMutation({
  required String toolName,
  required Map<String, dynamic> arguments,
}) async {
  if (toolName != 'local_execute_command' && toolName != 'process_start') {
    return BuiltInLocalCommandMutationPreflight(arguments: arguments);
  }
  final command = LocalShellTools.normalizeCommand(
    (arguments['command'] as String?)?.trim() ?? '',
  );
  final workingDirectory =
      (arguments['working_directory'] as String?)?.trim() ?? '';
  final projectRoot = LocalCommandMutationGuard.authorizedProjectRoot(
    arguments['allowed_read_root'] as String?,
  );
  if (command.isEmpty || workingDirectory.isEmpty || projectRoot == null) {
    return BuiltInLocalCommandMutationPreflight(arguments: arguments);
  }

  final cwdAuth = await LocalCommandMutationGuard.authorizeWorkingDirectory(
    toolName: toolName,
    projectRoot: projectRoot,
    workingDirectory: workingDirectory,
  );
  if (!cwdAuth.isAllowed) {
    return BuiltInLocalCommandMutationPreflight(
      deniedResult: cwdAuth.deniedResult,
      arguments: arguments,
    );
  }
  final canonicalWorkingDirectory = cwdAuth.canonicalPath!;
  if (!LocalShellTools.isReadOnly(command)) {
    final writeAuth = await LocalCommandMutationGuard.authorizeWritePaths(
      toolName: toolName,
      projectRoot: projectRoot,
      command: command,
      workingDirectory: canonicalWorkingDirectory,
    );
    if (writeAuth != null && !writeAuth.isAllowed) {
      return BuiltInLocalCommandMutationPreflight(
        deniedResult: writeAuth.deniedResult,
        arguments: arguments,
      );
    }
  }

  return BuiltInLocalCommandMutationPreflight(
    arguments: {...arguments, 'working_directory': canonicalWorkingDirectory},
  );
}
