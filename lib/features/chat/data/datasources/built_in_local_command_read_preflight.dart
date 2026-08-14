import '../../domain/entities/mcp_tool_entity.dart';
import 'local_shell_tools.dart';
import 'mcp_tool_result_normalizer.dart';

Future<McpToolResult?> authorizeBuiltInLocalCommandRead({
  required String toolName,
  required Map<String, dynamic> arguments,
}) async {
  if (toolName != 'local_execute_command' && toolName != 'process_start') {
    return null;
  }
  final command = LocalShellTools.normalizeCommand(
    (arguments['command'] as String?)?.trim() ?? '',
  );
  final workingDirectory =
      (arguments['working_directory'] as String?)?.trim() ?? '';
  if (command.isEmpty ||
      workingDirectory.isEmpty ||
      !LocalShellTools.isReadOnly(command)) {
    return null;
  }
  final denial = await LocalShellTools.projectReadDenial(
    command: command,
    workingDirectory: workingDirectory,
    projectRoot: arguments['allowed_read_root'] as String?,
  );
  if (denial == null) return null;
  const message = 'The command reads outside the authorized project.';
  return McpToolResultNormalizer.structuredFailure(
    toolName: toolName,
    payload: {'ok': false, 'code': denial.code, 'error': message},
    errorMessage: message,
  );
}
