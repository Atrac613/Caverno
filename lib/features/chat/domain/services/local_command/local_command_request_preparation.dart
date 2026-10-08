import '../../../data/datasources/local_shell_tools.dart';
import '../../entities/chat_turn_owner.dart';
import '../../entities/mcp_tool_entity.dart';
import 'local_command_execution_plan.dart';
import 'local_command_tool_contract.dart';
import 'local_command_working_directory.dart';
import 'out_of_root_command_paths.dart';

typedef PreparedLocalCommandPlan = ({
  LocalCommandExecutionRequest execution,
  LocalCommandApprovalScope approvalScope,
});

/// Resolves project-relative paths against the owning turn before approval.
final class LocalCommandRequestPreparation {
  const LocalCommandRequestPreparation._({this.plan, this.error});
  final PreparedLocalCommandPlan? plan;
  final String? error;

  McpToolResult? failureResult(String toolName) => error == null
      ? null
      : McpToolResult(
          toolName: toolName,
          result: '',
          isSuccess: false,
          errorMessage: error,
        );

  static LocalCommandRequestPreparation prepare({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required String projectRoot,
    required Map<String, dynamic> arguments,
  }) {
    final request = LocalCommandToolRequest(
      owner: owner,
      toolCallId: toolCallId,
      toolName: toolName,
      allowedWorkingDirectoryRoot: projectRoot,
      defaultWorkingDirectory: projectRoot,
      arguments: arguments,
    );
    final command = LocalShellTools.normalizeCommand(
      (arguments['command'] as String?)?.trim() ?? '',
    );
    final cwd = LocalCommandWorkingDirectory.resolve(request);
    if (command.isEmpty || cwd == null) {
      return const LocalCommandRequestPreparation._(
        error: 'command and working_directory are required',
      );
    }
    if (!LocalCommandWorkingDirectory.isAllowed(cwd, projectRoot)) {
      return const LocalCommandRequestPreparation._(
        error:
            'working_directory must resolve inside the selected coding project',
      );
    }
    return LocalCommandRequestPreparation._(
      plan: LocalCommandExecutionPlan.create(
        request: request,
        command: command,
        workingDirectory: cwd,
      ),
    );
  }
}
