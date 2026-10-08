/// Shared schema for delegation and result lookup.
abstract final class SubagentToolDefinitions {
  static Map<String, dynamic> get spawn => {
    'type': 'function',
    'function': {
      'name': 'spawn_subagent',
      'description':
          'Delegate a focused, self-contained sub-task to a child agent that '
          'runs its own tool-calling loop and returns a concise summary. Use '
          'this to keep the main conversation focused: offload large file or '
          'code exploration, independent research, or a parallelizable step. '
          'The child inherits your tools except spawn_subagent itself (no '
          'nested delegation) and cannot see the main conversation, so the '
          'prompt must be complete on its own.',
      'parameters': {
        'type': 'object',
        'properties': {
          'description': {
            'type': 'string',
            'description':
                'Short label for the sub-task, shown in the UI and logs.',
          },
          'prompt': {
            'type': 'string',
            'description':
                'Full self-contained instructions for the subagent. Include '
                'all context it needs; it cannot see the main conversation.',
          },
          'workflow_task_id': {
            'type': 'string',
            'description':
                'Required for Anabasis with a saved plan: an exact ready task ID.',
          },
          'background': {
            'type': 'boolean',
            'description':
                'Run asynchronously and return a task id immediately instead '
                'of waiting for the result. Defaults to false.',
          },
          'runner': {
            'type': 'string',
            'enum': ['subagent', 'worktree'],
            'description':
                'Where the child runs. "subagent" shares this workspace and '
                'returns a summary. "worktree" runs on its own git branch in an '
                'isolated checkout and returns changed files and the result of '
                'the saved validation command, which is the evidence an '
                'acceptance can rest on; it requires a saved plan task and a '
                'coding project, and returns a task id to poll. Defaults to '
                '"subagent".',
          },
        },
        'required': ['description', 'prompt'],
      },
    },
  };

  /// The parent's route to recording a judgement it has already made.
  ///
  /// Deliberately not a way to *decide* acceptance. The derivable levels are
  /// checked before this writes anything, so a confident rationale cannot stand
  /// in for a test that did not pass or files nobody can see.
  static Map<String, dynamic> get acceptTask => {
    'type': 'function',
    'function': {
      'name': 'accept_task',
      'description':
          'Record that you accept a delegated saved task as satisfying the '
          'goal, with your reason. Only for Anabasis, and only after you have '
          'verified the result: a child reporting success means it produced '
          'something, never that the work is accepted. Refused while the '
          'mechanical or evidence level is still outstanding, so verify first '
          'and say what the evidence was.',
      'parameters': {
        'type': 'object',
        'properties': {
          'workflow_task_id': {
            'type': 'string',
            'description':
                'The saved task you are accepting, as delegated to a child.',
          },
          'rationale': {
            'type': 'string',
            'description':
                'Why this satisfies the goal, in your own words. Recorded as '
                'written and never parsed.',
          },
        },
        'required': ['workflow_task_id', 'rationale'],
      },
    },
  };

  static Map<String, dynamic> get result => {
    'type': 'function',
    'function': {
      'name': 'get_subagent_result',
      'description':
          'Retrieve the status and result of a background subagent started '
          'with spawn_subagent(background: true). Pass the task_id returned '
          'when the subagent was started. Returns the summary once completed, '
          'or a running status if it is still working.',
      'parameters': {
        'type': 'object',
        'properties': {
          'task_id': {
            'type': 'string',
            'description': 'The task id returned by spawn_subagent.',
          },
        },
        'required': ['task_id'],
      },
    },
  };
}
