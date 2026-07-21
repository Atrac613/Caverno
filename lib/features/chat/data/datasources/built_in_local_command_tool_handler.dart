import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'background_process_monitor_service.dart';
import 'background_process_tools.dart';
import 'built_in_local_command_tool_definitions.dart';
import 'command_payload_facts.dart';
import 'local_shell_tools.dart';
import 'mcp_tool_result_normalizer.dart';

typedef BuiltInLocalCommandRunner =
    Future<String> Function({
      required String command,
      required String workingDirectory,
    });

/// Owns the built-in local command definitions and direct execution contract.
class BuiltInLocalCommandToolHandler {
  BuiltInLocalCommandToolHandler({
    BackgroundProcessTools? backgroundProcessTools,
    BackgroundProcessMonitorService? backgroundProcessMonitorService,
    BuiltInLocalCommandRunner? foregroundCommandRunner,
    DateTime Function()? clock,
  }) : _backgroundProcessTools = backgroundProcessTools,
       _backgroundProcessMonitorService = backgroundProcessMonitorService,
       _foregroundCommandRunner =
           foregroundCommandRunner ?? LocalShellTools.execute,
       _clock = clock ?? DateTime.now;

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

  final BackgroundProcessTools? _backgroundProcessTools;
  final BackgroundProcessMonitorService? _backgroundProcessMonitorService;
  final BuiltInLocalCommandRunner _foregroundCommandRunner;
  final DateTime Function() _clock;

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
      _backgroundProcessTools?.isSupported ?? false;

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown local command tool');
    }

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
        final gitWriteBlockedResult =
            LocalShellTools.gitWriteCommandBlockedResult(
              command: command,
              workingDirectory: workingDirectory,
            );
        if (gitWriteBlockedResult != null) {
          return _gitWriteFailure(name, gitWriteBlockedResult);
        }
        if (_asBool(arguments['background'])) {
          final tools = _backgroundProcessTools;
          if (tools == null || !tools.isSupported) {
            return McpToolResultNormalizer.structuredFailure(
              toolName: name,
              payload: const {
                'ok': false,
                'code': 'background_process_tools_unavailable',
                'error': 'Background process tools are not available',
              },
              errorMessage: 'Background process tools are not available',
            );
          }
          final result = await tools.start(
            command: command,
            workingDirectory: workingDirectory,
            label: (arguments['label'] as String?)?.trim(),
          );
          return McpToolResultNormalizer.success(
            toolName: name,
            result: result,
          );
        }
        final result = await _foregroundCommandRunner(
          command: command,
          workingDirectory: workingDirectory,
        );
        // A non-zero exit is the command's outcome, not a tool failure, so the
        // result stays successful and only carries the reported exit status.
        return McpToolResultNormalizer.success(
          toolName: name,
          result: result,
          outcome: CommandPayloadFacts.tryParse(result)?.toOutcome(),
        );
      case 'process_start':
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
        final gitWriteBlockedResult =
            LocalShellTools.gitWriteCommandBlockedResult(
              command: command,
              workingDirectory: workingDirectory,
            );
        if (gitWriteBlockedResult != null) {
          return _gitWriteFailure(name, gitWriteBlockedResult);
        }
        final tools = _backgroundProcessTools;
        if (tools == null || !tools.isSupported) {
          return McpToolResultNormalizer.failure(
            toolName: name,
            errorMessage: 'Background process tools are not available',
          );
        }
        final result = await tools.start(
          command: command,
          workingDirectory: workingDirectory,
          label: (arguments['label'] as String?)?.trim(),
        );
        return McpToolResultNormalizer.success(toolName: name, result: result);
      case 'process_status':
        final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
        if (jobId.isEmpty) {
          return _validationFailure(name, 'job_id is required');
        }
        final result = await _backgroundProcessTools?.status(
          jobId: jobId,
          tailChars: (arguments['tail_chars'] as num?)?.toInt(),
        );
        return _nullableProviderResult(name, result);
      case 'process_tail':
        final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
        if (jobId.isEmpty) {
          return _validationFailure(name, 'job_id is required');
        }
        final result = await _backgroundProcessTools?.tail(
          jobId: jobId,
          maxChars: (arguments['max_chars'] as num?)?.toInt(),
        );
        return _nullableProviderResult(name, result);
      case 'process_wait':
        final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
        if (jobId.isEmpty) {
          return _validationFailure(name, 'job_id is required');
        }
        final result = await _backgroundProcessTools?.wait(
          jobId: jobId,
          waitMs: (arguments['wait_ms'] as num?)?.toInt(),
        );
        return _nullableProviderResult(name, result);
      case 'process_cancel':
        final jobId = (arguments['job_id'] as String?)?.trim() ?? '';
        if (jobId.isEmpty) {
          return _validationFailure(name, 'job_id is required');
        }
        final result = await _backgroundProcessTools?.cancel(jobId: jobId);
        return _nullableProviderResult(name, result);
      case 'process_list':
        return _executeProcessList(name, arguments);
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

  Future<McpToolResult> _executeProcessList(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final monitor = _backgroundProcessMonitorService;
    if (monitor == null) {
      return McpToolResultNormalizer.structuredFailure(
        toolName: name,
        payload: const {
          'ok': false,
          'code': 'background_process_monitor_unavailable',
          'error': 'Background process monitor is not available',
        },
        errorMessage: 'Background process monitor is not available',
      );
    }

    final jobIdsArgument = arguments['job_ids'];
    late final List<String> jobIds;
    if (jobIdsArgument == null) {
      jobIds = const <String>[];
    } else if (jobIdsArgument is List<dynamic>) {
      jobIds = jobIdsArgument
          .whereType<String>()
          .map((jobId) => jobId.trim())
          .where((jobId) => jobId.isNotEmpty)
          .toList(growable: false);
    } else {
      return McpToolResultNormalizer.structuredFailure(
        toolName: name,
        payload: const {
          'ok': false,
          'code': 'invalid_job_ids',
          'error': 'job_ids must be an array of strings',
        },
        errorMessage: 'job_ids must be an array of strings',
      );
    }

    final includeFinished = arguments['include_finished'] is bool
        ? arguments['include_finished'] as bool
        : true;
    final refresh = arguments['refresh'] is bool
        ? arguments['refresh'] as bool
        : false;
    final requestedLimit = (arguments['limit'] as num?)?.toInt();
    if (refresh) {
      if (jobIds.isEmpty) {
        await monitor.refreshActiveJobs();
      } else {
        await monitor.refreshJobs(jobIds);
      }
    }

    final snapshots = monitor.listJobs(
      jobIds: jobIds,
      includeFinished: includeFinished,
      limit: requestedLimit,
    );
    return McpToolResultNormalizer.success(
      toolName: name,
      result: jsonEncode({
        'ok': true,
        'generated_at': _clock().toIso8601String(),
        'job_count': snapshots.length,
        'jobs': snapshots
            .map((snapshot) => snapshot.toJson())
            .toList(growable: false),
        'active_count': monitor.activeSnapshots.length,
        'finished_count': snapshots
            .where((snapshot) => !snapshot.isRunning)
            .length,
      }),
    );
  }

  McpToolResult _validationFailure(String name, String message) {
    return McpToolResultNormalizer.failure(
      toolName: name,
      errorMessage: message,
    );
  }

  McpToolResult _gitWriteFailure(String name, String result) {
    return McpToolResultNormalizer.failure(
      toolName: name,
      result: result,
      errorMessage: 'Use git_execute_command for git write commands',
    );
  }

  McpToolResult _nullableProviderResult(String name, String? result) {
    if (result != null) {
      return McpToolResultNormalizer.success(toolName: name, result: result);
    }
    return McpToolResultNormalizer.structuredFailure(
      toolName: name,
      payload: const {
        'ok': false,
        'code': 'background_process_tools_unavailable',
        'error': 'Background process tools are not available',
      },
      errorMessage: 'Background process tools are not available',
    );
  }

  bool _asBool(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }
}
