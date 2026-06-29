class GitExecuteCommandTool {
  const GitExecuteCommandTool._();

  static const String toolName = 'git_execute_command';

  static Map<String, dynamic> get toolDefinition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Execute a git command in a local repository, or initialize one '
          'with git init (desktop only — '
          'macOS, Linux, Windows). Read-only commands (status, log, diff, '
          'show, branch, tag, remote, blame, etc.) run immediately. Write '
          'operations (commit, push, pull, checkout, merge, rebase, reset, '
          'etc.) require user approval before execution. Always use '
          'non-interactive flags (e.g. commit -m "message", not bare commit).',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description':
                'Git subcommand and arguments (without the leading "git"), '
                'exactly one git subcommand per call. Do not use shell '
                'operators such as &&, ;, |, or redirection. '
                'e.g. "status", "log --oneline -20", "diff HEAD~1", '
                '"commit -m \\"fix typo\\"".',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory. '
                'Optional when a coding project is currently selected; the '
                'project root can be used as the default.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable explanation shown to the user in the '
                'confirmation dialog (only used for write operations).',
          },
        },
        'required': ['command'],
      },
    },
  };
}
