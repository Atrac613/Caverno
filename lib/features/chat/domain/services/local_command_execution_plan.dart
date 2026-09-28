import '../../../settings/domain/services/local_command_permission_service.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../../data/datasources/python_workspace_containment.dart';
import 'local_command_tool_contract.dart';
import 'out_of_root_command_paths.dart';

/// Freezes the execution route and its matching approval scope together.
abstract final class LocalCommandExecutionPlan {
  static ({
    LocalCommandExecutionRequest execution,
    LocalCommandApprovalScope approvalScope,
  })
  create({
    required LocalCommandToolRequest request,
    required String command,
    required String workingDirectory,
  }) {
    final background = argumentIsTruthy(request.arguments['background']);
    final containedPython =
        !background &&
        PythonWorkspaceContainment.eligible(
          command: command,
          root: request.allowedWorkingDirectoryRoot,
        ) &&
        const OutOfRootCommandPaths()
            .scan(
              command: command,
              projectRoot: request.allowedWorkingDirectoryRoot,
            )
            .isEmpty;
    final execution = LocalCommandExecutionRequest(
      toolCallId: request.toolCallId,
      toolName: request.toolName,
      command: command,
      workingDirectory: workingDirectory,
      arguments: {
        ...request.arguments,
        'command': command,
        'working_directory': workingDirectory,
        'allowed_read_root': request.allowedWorkingDirectoryRoot,
        'workspace_python_containment': containedPython,
      },
    );
    final approvalScope = LocalCommandApprovalScope.of(
      command: command,
      projectRoot: request.allowedWorkingDirectoryRoot,
      reachesNativeShell: background || !LocalShellTools.isReadOnly(command),
      hostWriteContained: containedPython,
      commandShapeRequiresApproval:
          LocalCommandPermissionService.requiresExplicitApproval,
    );
    return (execution: execution, approvalScope: approvalScope);
  }
}
