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
        },
        'required': ['description', 'prompt'],
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
