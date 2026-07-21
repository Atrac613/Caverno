/// Static OpenAI tool definitions for the goal and routine built-ins.
///
/// Split out of `McpToolService` so its file holds dispatch, not inert JSON
/// schemas — the same boundary the LL34 tool-definition extractions drew.
/// These are pure `Map` literals with no service state. See LL35 in
/// `docs/local_llm_agent_roadmap.md`.
abstract final class McpGoalRoutineToolDefinitions {
  static Map<String, dynamic> get createRoutineTool => {
    'type': 'function',
    'function': {
      'name': 'create_routine',
      'description':
          'Schedule a recurring routine (an autonomous agent run) from the '
          'conversation. Use this when the user describes a repeating task on a '
          'schedule (e.g. "ping a host hourly and report the result"). The user '
          'must approve every routine; the approval previews the schedule, '
          'enabled tools, and delivery channels. The routine then runs '
          'unattended on its schedule.',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Short routine name (e.g. "Ping 192.168.0.1").',
          },
          'prompt': {
            'type': 'string',
            'description':
                'The instruction the routine runs each time (e.g. "Ping '
                '192.168.0.1 and report whether it is reachable").',
          },
          'schedule_mode': {
            'type': 'string',
            'enum': ['interval', 'daily'],
            'description':
                'interval = every N minutes/hours/days; daily = once per day '
                'at a fixed time. Defaults to interval.',
          },
          'interval_value': {
            'type': 'integer',
            'description': 'For interval mode: how many units between runs.',
            'minimum': 1,
          },
          'interval_unit': {
            'type': 'string',
            'enum': ['minutes', 'hours', 'days'],
            'description': 'For interval mode: the unit. Defaults to hours.',
          },
          'time_of_day': {
            'type': 'string',
            'description':
                'For daily mode: 24h "HH:MM" local time to run (e.g. "08:00").',
          },
          'tools_enabled': {
            'type': 'boolean',
            'description':
                'Allow the routine to use tools (required for tasks like ping). '
                'Defaults to false.',
          },
          'notify_on_completion': {
            'type': 'boolean',
            'description':
                'Show a local notification when the run completes. Defaults to '
                'true.',
          },
          'completion_action': {
            'type': 'string',
            'enum': ['none', 'google_chat', 'prompt_google_chat'],
            'description':
                'External delivery of the result. google_chat posts to the '
                'configured Google Chat webhook. Defaults to none.',
          },
          'google_chat_rule': {
            'type': 'string',
            'enum': ['on_success', 'on_failure', 'always'],
            'description':
                'When to post to Google Chat (if completion_action uses it). '
                'Defaults to on_failure.',
          },
          'workspace_directory': {
            'type': 'string',
            'description': 'Optional working directory for the routine run.',
          },
          'allow_workspace_writes': {
            'type': 'boolean',
            'description':
                'Allow the routine to write in the workspace directory. '
                'Defaults to false.',
          },
        },
        'required': ['name', 'prompt'],
      },
    },
  };

  static Map<String, dynamic> get updateGoalTool => {
    'type': 'function',
    'function': {
      'name': 'update_goal',
      'description':
          'Report progress on the active goal. Call with completed: true ONLY '
          'when the goal is fully achieved — the harness checks it against the '
          'run\'s tool results and replies whether the completion was accepted '
          'or which concrete items remain, so a claim that is contradicted by '
          'the evidence is rejected rather than silently believed. Use message '
          'to log progress, or blocked_reason only when genuinely stuck. Do '
          'not restate completion in prose instead of calling this — prose is '
          'not how the goal is finished.',
      'parameters': {
        'type': 'object',
        'properties': {
          'completed': {
            'type': 'boolean',
            'description':
                'Set true ONLY when the goal is fully achieved. The harness '
                'verifies against tool results and may reject the claim.',
          },
          'message': {
            'type': 'string',
            'description':
                'Optional short progress note (e.g. "wrote the parser, tests '
                'next").',
          },
          'blocked_reason': {
            'type': 'string',
            'description':
                'Set only when truly stuck after multiple attempts. Never put '
                'success text here.',
          },
        },
      },
    },
  };
}
