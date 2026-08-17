import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/local_command_tool_contract.dart';
import 'background_process_monitor_service.dart';
import 'background_process_tool_executor.dart';
import 'background_process_tools.dart';
import 'built_in_local_command_read_preflight.dart';
import 'built_in_local_command_runner.dart';
import 'built_in_local_command_tool_definitions.dart';
import 'local_shell_git_write_guard.dart';
import 'local_shell_tools.dart';
import 'mcp_tool_result_normalizer.dart';

export 'built_in_local_command_runner.dart'
    show BuiltInLocalCommandResultRunner, BuiltInLocalCommandRunner;

/// Owns the built-in local command definitions and direct execution contract.
class BuiltInLocalCommandToolHandler {
  BuiltInLocalCommandToolHandler({
    BackgroundProcessTools? backgroundProcessTools,
    BackgroundProcessMonitorService? backgroundProcessMonitorService,
    BuiltInLocalCommandRunner? foregroundCommandRunner,
    BuiltInLocalCommandResultRunner? foregroundCommandResultRunner,
    DateTime Function()? clock,
  }) : _backgroundProcessExecutor = BackgroundProcessToolExecutor(
         tools: backgroundProcessTools,
         monitor: backgroundProcessMonitorService,
         clock: clock,
       ),
       _foregroundCommandResultRunner = resolveBuiltInLocalCommandResultRunner(
         legacyRunner: foregroundCommandRunner,
         resultRunner: foregroundCommandResultRunner,
       );

  static const List<String> toolNames = <String>[
    'local_execute_command',
    'process_start',
    'process_status',
    'process_tail',
    'process_wait',
    'process_cancel',
    'process_list',
    'run_tests',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final BackgroundProcessToolExecutor _backgroundProcessExecutor;
  final BuiltInLocalCommandResultRunner _foregroundCommandResultRunner;

  Map<String, dynamic> get localExecuteCommandDefinition =>
      BuiltInLocalCommandToolDefinitions.localExecuteCommandTool;

  List<Map<String, dynamic>> get processDefinitions => <Map<String, dynamic>>[
    BuiltInLocalCommandToolDefinitions.processStartTool,
    BuiltInLocalCommandToolDefinitions.processStatusTool,
    BuiltInLocalCommandToolDefinitions.processTailTool,
    BuiltInLocalCommandToolDefinitions.processWaitTool,
    BuiltInLocalCommandToolDefinitions.processCancelTool,
    BuiltInLocalCommandToolDefinitions.processListTool,
  ];

  Map<String, dynamic> get runTestsDefinition =>
      BuiltInLocalCommandToolDefinitions.runTestsTool;

  bool get supportsBackgroundProcesses =>
      _backgroundProcessExecutor.isSupported;

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    ChatTurnOwner? owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown local command tool');
    }
    if ((name.startsWith('process_') ||
            (name == 'local_execute_command' &&
                argumentIsTruthy(arguments['background']))) &&
        owner == null) {
      return McpToolResultNormalizer.structuredFailure(
        toolName: name,
        payload: const {
          'ok': false,
          'code': 'chat_turn_owner_required',
          'error': 'An active chat turn owner is required',
        },
        errorMessage: 'An active chat turn owner is required',
      );
    }

    final readDenial = await authorizeBuiltInLocalCommandRead(
      toolName: name,
      arguments: arguments,
    );
    if (readDenial != null) return readDenial;

    switch (name) {
      case 'local_execute_command':
        final command = LocalShellTools.normalizeCommand(
          (arguments['command'] as String?)?.trim() ?? '',
        );
        final workingDirectory =
            (arguments['working_directory'] as String?)?.trim() ?? '';
        if (command.isEmpty || workingDirectory.isEmpty) {
          return _validationFailure(
            name,
            'command and working_directory are required',
          );
        }
        final gitWriteBlocked = LocalShellGitWriteGuard.resultFor(
          toolName: name,
          command: command,
          workingDirectory: workingDirectory,
        );
        if (gitWriteBlocked != null) {
          return gitWriteBlocked;
        }
        if (argumentIsTruthy(arguments['background'])) {
          return _backgroundProcessExecutor.start(
            owner: owner!,
            name: name,
            command: command,
            workingDirectory: workingDirectory,
            label: (arguments['label'] as String?)?.trim(),
            structuredUnavailable: true,
          );
        }
        final execution = await _foregroundCommandResultRunner(
          command: command,
          workingDirectory: workingDirectory,
        );
        // A non-zero exit is the command's outcome, not a tool failure, so the
        // result stays successful and only carries the reported exit status.
        return McpToolResultNormalizer.success(
          toolName: name,
          result: execution.result,
          outcome: execution.outcome,
        );
      case 'process_start':
      case 'process_status':
      case 'process_tail':
      case 'process_wait':
      case 'process_cancel':
      case 'process_list':
        return _backgroundProcessExecutor.execute(
          owner: owner!,
          name: name,
          arguments: arguments,
        );
      case 'run_tests':
        return McpToolResultNormalizer.structuredFailure(
          toolName: name,
          payload: const {
            'error':
                'run_tests must be executed through the chat command approval flow.',
            'code': 'approval_required',
          },
          errorMessage:
              'run_tests must be executed through the chat command approval flow',
        );
    }

    throw StateError('Unhandled local command tool: $name');
  }

  McpToolResult _validationFailure(String name, String message) {
    return McpToolResultNormalizer.failure(
      toolName: name,
      errorMessage: message,
    );
  }
}
