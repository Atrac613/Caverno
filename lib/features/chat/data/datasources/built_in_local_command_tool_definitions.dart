/// Static OpenAI tool definitions for the built-in local command surface.
///
/// Split out of `BuiltInLocalCommandToolHandler` so the handler holds only
/// dispatch and execution: these are inert JSON schemas, and keeping ~250
/// lines of them alongside the execution paths made the file's real behavior
/// hard to find. Mirrors `mcp_tool_service_builtin_tool_definitions.dart`.
abstract final class BuiltInLocalCommandToolDefinitions {
  static Map<String, dynamic> get localExecuteCommandTool => {
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

  static Map<String, dynamic> get processStartTool => {
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

  static Map<String, dynamic> get processStatusTool => {
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

  static Map<String, dynamic> get processTailTool => {
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

  static Map<String, dynamic> get processWaitTool => {
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

  static Map<String, dynamic> get processCancelTool => {
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

  static Map<String, dynamic> get processListTool => {
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

  static Map<String, dynamic> get runTestsTool => {
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
