import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'background_process_monitor_service.dart';
import 'background_process_tools.dart';
import 'local_shell_tools.dart';

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
      _localExecuteCommandTool;

  List<Map<String, dynamic>> get processDefinitions => <Map<String, dynamic>>[
    _processStartTool,
    _processStatusTool,
    _processTailTool,
    _processWaitTool,
    _processCancelTool,
    _processListTool,
  ];

  Map<String, dynamic> get runTestsDefinition => _runTestsTool;

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
            return McpToolResult(
              toolName: name,
              result: _backgroundProcessUnavailableResult(),
              isSuccess: false,
              errorMessage: 'Background process tools are not available',
            );
          }
          final result = await tools.start(
            command: command,
            workingDirectory: workingDirectory,
            label: (arguments['label'] as String?)?.trim(),
          );
          return McpToolResult(toolName: name, result: result, isSuccess: true);
        }
        final result = await _foregroundCommandRunner(
          command: command,
          workingDirectory: workingDirectory,
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
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
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Background process tools are not available',
          );
        }
        final result = await tools.start(
          command: command,
          workingDirectory: workingDirectory,
          label: (arguments['label'] as String?)?.trim(),
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
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
        return McpToolResult(
          toolName: name,
          result: jsonEncode({
            'error':
                'run_tests must be executed through the chat command approval flow.',
            'code': 'approval_required',
          }),
          isSuccess: false,
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
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'ok': false,
          'code': 'background_process_monitor_unavailable',
          'error': 'Background process monitor is not available',
        }),
        isSuccess: false,
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
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'ok': false,
          'code': 'invalid_job_ids',
          'error': 'job_ids must be an array of strings',
        }),
        isSuccess: false,
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
    return McpToolResult(
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
      isSuccess: true,
    );
  }

  McpToolResult _validationFailure(String name, String message) {
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }

  McpToolResult _gitWriteFailure(String name, String result) {
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: false,
      errorMessage: 'Use git_execute_command for git write commands',
    );
  }

  McpToolResult _nullableProviderResult(String name, String? result) {
    return McpToolResult(
      toolName: name,
      result: result ?? _backgroundProcessUnavailableResult(),
      isSuccess: result != null,
      errorMessage: result == null
          ? 'Background process tools are not available'
          : null,
    );
  }

  String _backgroundProcessUnavailableResult() {
    return jsonEncode({
      'ok': false,
      'code': 'background_process_tools_unavailable',
      'error': 'Background process tools are not available',
    });
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

  static Map<String, dynamic> get _localExecuteCommandTool => {
    'type': 'function',
    'function': {
      'name': 'local_execute_command',
      'description':
          'Execute an exact shell command or multiline shell script inside the current project. Batch related commands such as format, analyze, and test into one call, using && between independent commands when portable early exit is required. On POSIX, unhandled failures in newline-separated foreground scripts also stop execution. Read-only commands may run immediately; commands that can modify files or state require user approval. Use git_execute_command for git write operations such as add, commit, checkout, merge, rebase, branch changes, worktree changes, tag creation, or reset. Prefer file tools for file discovery and reading; prefer absolute paths or working_directory over shell-only features such as pipes, redirection, environment variables, or command substitution. Do not use shell commands (cat, stty, screen, xxd, etc.) on serial port devices such as /dev/tty.*, /dev/cu.*, or COM ports — they block on serial I/O and are platform-fragile; use the dedicated serial_* tools (serial_list_ports, serial_open, serial_read, serial_decode, serial_write, serial_close) instead.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description':
                'Exact native-shell command or multiline script. Use && between independent commands for portable early exit; foreground POSIX newline scripts also stop at the first unhandled failure.',
          },
          'background': {
            'type': 'boolean',
            'description':
                'Run the command in the background and return a job id without '
                'waiting for completion.',
          },
          'label': {
            'type': 'string',
            'description':
                'Optional short label for background runs (required when '
                'background=true).',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Absolute or project-relative working directory. Optional when a coding project is selected.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog for non-read-only commands.',
          },
        },
        'required': ['command'],
      },
    },
  };

  static Map<String, dynamic> get _processStartTool => {
    'type': 'function',
    'function': {
      'name': 'process_start',
      'description':
          'Start a long-running local shell command as a background process and return a job_id immediately. Use this instead of local_execute_command for builds, releases, deploys, uploads, long tests, or commands expected to run longer than about one minute. Use git_execute_command, not process_start, for git write operations. Pair this with process_list/process_status/process_tail/process_wait to observe completion. Starting a process may modify files or external state and requires the same approval as local_execute_command.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Exact shell command to start.',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Absolute or project-relative working directory. Optional when a coding project is selected.',
          },
          'label': {
            'type': 'string',
            'description':
                'Short label for the background job, such as "iOS release".',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['command'],
      },
    },
  };

  static Map<String, dynamic> get _processStatusTool => {
    'type': 'function',
    'function': {
      'name': 'process_status',
      'description':
          'Check the status of a background process started with process_start or background local_execute_command. This is read-only and returns running/exited state, PID, exit code when available, elapsed time, and recent output tails.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
          'tail_chars': {
            'type': 'integer',
            'description':
                'Optional number of stdout/stderr tail characters to include.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processTailTool => {
    'type': 'function',
    'function': {
      'name': 'process_tail',
      'description':
          'Read stdout/stderr tails for a background process started with '
          'process_start or background local_execute_command. This is read-only.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
          'max_chars': {
            'type': 'integer',
            'description': 'Maximum tail characters per stream.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processWaitTool => {
    'type': 'function',
    'function': {
      'name': 'process_wait',
      'description':
          'Wait briefly for a background process and return its current status. Keep '
          'wait_ms short and call process_status/process_tail again as needed '
          'instead of starting the command again. Use the returned status and '
          'output tails to report concise progress before continuing to wait.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
          'wait_ms': {
            'type': 'integer',
            'description': 'Milliseconds to wait, capped by the app.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processCancelTool => {
    'type': 'function',
    'function': {
      'name': 'process_cancel',
      'description':
          'Request cancellation of a running background process by job_id. This can '
          'stop a local command and may require user approval depending on '
          'context.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description':
                'The job_id returned by process_start or background '
                'local_execute_command.',
          },
        },
        'required': ['job_id'],
      },
    },
  };

  static Map<String, dynamic> get _processListTool => {
    'type': 'function',
    'function': {
      'name': 'process_list',
      'description':
          'List monitored background processes started with process_start or '
          'background local_execute_command and return current status snapshots, '
          'including optional completed jobs.',
      'parameters': {
        'type': 'object',
        'properties': {
          'job_ids': {
            'type': 'array',
            'description': 'Optional list of job IDs to filter results.',
            'items': {'type': 'string'},
          },
          'include_finished': {
            'type': 'boolean',
            'description':
                'Whether to include exited/finished jobs. Defaults to true.',
          },
          'refresh': {
            'type': 'boolean',
            'description':
                'Refresh statuses before listing. Defaults to false.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of jobs to return.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _runTestsTool => {
    'type': 'function',
    'function': {
      'name': 'run_tests',
      'description':
          'Run scoped Dart or Flutter tests in the selected coding project. Use this only with a specific test file or directory. For full suites such as flutter test, fvm flutter test, dart test, or fvm dart test with no specific test path, use process_start or local_execute_command with background=true so the app can monitor the long-running command.',
      'parameters': {
        'type': 'object',
        'properties': {
          'test_path': {
            'type': 'string',
            'description':
                'Optional test file or directory to run. Paths may be project-relative, working-directory-relative, or absolute, but must stay inside the selected project.',
          },
          'runner': {
            'type': 'string',
            'enum': ['auto', 'flutter', 'dart'],
            'description':
                'Test runner to use. auto uses Flutter and prefixes fvm when the project has FVM metadata.',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Optional absolute or project-relative package directory. Defaults to the selected project root.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog when approval is required.',
          },
        },
      },
    },
  };
}
