import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'background_process_list_tool.dart';
import 'background_process_monitor_service.dart';
import 'background_process_result_normalizer.dart';
import 'background_process_tools.dart';
import 'local_shell_tools.dart';
import 'mcp_tool_result_normalizer.dart';

/// Executes the owner-scoped background-process tool family.
final class BackgroundProcessToolExecutor {
  BackgroundProcessToolExecutor({
    BackgroundProcessTools? tools,
    BackgroundProcessMonitorService? monitor,
    DateTime Function()? clock,
  }) : _tools = tools,
       _monitor = monitor,
       _clock = clock ?? DateTime.now;

  final BackgroundProcessTools? _tools;
  final BackgroundProcessMonitorService? _monitor;
  final DateTime Function() _clock;
  bool get isSupported => _tools?.isSupported ?? false;

  Future<McpToolResult> start({
    required ChatTurnOwner owner,
    required String name,
    required String command,
    required String workingDirectory,
    String? label,
    bool structuredUnavailable = false,
  }) async {
    final gitWriteBlockedResult = LocalShellTools.gitWriteCommandBlockedResult(
      command: command,
      workingDirectory: workingDirectory,
    );
    if (gitWriteBlockedResult != null) {
      return McpToolResultNormalizer.failure(
        toolName: name,
        result: gitWriteBlockedResult,
        errorMessage: 'Use git_execute_command for git write commands',
      );
    }
    final tools = _tools;
    if (tools == null || !tools.isSupported) {
      const message = 'Background process tools are not available';
      return structuredUnavailable
          ? McpToolResultNormalizer.structuredFailure(
              toolName: name,
              payload: const {
                'ok': false,
                'code': 'background_process_tools_unavailable',
                'error': message,
              },
              errorMessage: message,
            )
          : McpToolResultNormalizer.failure(
              toolName: name,
              errorMessage: message,
            );
    }
    final result = await tools.startExecution(
      owner: owner,
      command: command,
      workingDirectory: workingDirectory,
      label: label,
    );
    return normalizeProcessResult(name, result);
  }

  Future<McpToolResult> execute({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name == 'process_start') {
      final command = LocalShellTools.normalizeCommand(
        (arguments['command'] as String?)?.trim() ?? '',
      );
      final workingDirectory =
          (arguments['working_directory'] as String?)?.trim() ?? '';
      if (command.isEmpty || workingDirectory.isEmpty) {
        return _failure(name, 'command and working_directory are required');
      }
      return start(
        owner: owner,
        name: name,
        command: command,
        workingDirectory: workingDirectory,
        label: (arguments['label'] as String?)?.trim(),
      );
    }
    if (name == 'process_list') {
      return executeBackgroundProcessList(
        monitor: _monitor,
        owner: owner,
        toolName: name,
        arguments: arguments,
        clock: _clock,
      );
    }

    final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
    if (jobId.isEmpty) {
      return _failure(name, 'job_id is required');
    }
    final result = switch (name) {
      'process_status' => await _tools?.statusExecution(
        owner: owner,
        jobId: jobId,
        tailChars: (arguments['tail_chars'] as num?)?.toInt(),
      ),
      'process_tail' => await _tools?.tailExecution(
        owner: owner,
        jobId: jobId,
        maxChars: (arguments['max_chars'] as num?)?.toInt(),
      ),
      'process_wait' => await _tools?.waitExecution(
        owner: owner,
        jobId: jobId,
        waitMs: (arguments['wait_ms'] as num?)?.toInt(),
      ),
      'process_cancel' => await _tools?.cancelExecution(
        owner: owner,
        jobId: jobId,
      ),
      _ => throw ArgumentError.value(name, 'name', 'Unknown process tool'),
    };
    return result == null
        ? _unavailable(name)
        : normalizeProcessResult(name, result);
  }

  McpToolResult _failure(String name, String message) =>
      McpToolResultNormalizer.failure(toolName: name, errorMessage: message);

  McpToolResult _unavailable(String name) =>
      McpToolResultNormalizer.structuredFailure(
        toolName: name,
        payload: const {
          'ok': false,
          'code': 'background_process_tools_unavailable',
          'error': 'Background process tools are not available',
        },
        errorMessage: 'Background process tools are not available',
      );
}
