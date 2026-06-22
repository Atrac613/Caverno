part of 'mcp_tool_service.dart';

/// Fallback `web_search` tool definition for SearXNG.
Map<String, dynamic> get _mcpToolWebSearchToolFallback => {
  'type': 'function',
  'function': {
    'name': 'web_search',
    'description':
        'Perform a web search on the Internet. Use this to look up the latest information, news, weather, etc.',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Search query'},
      },
      'required': ['query'],
    },
  },
};

/// Built-in local datetime tool definition.
Map<String, dynamic> get _mcpToolCurrentDatetimeTool => {
  'type': 'function',
  'function': {
    'name': 'get_current_datetime',
    'description':
        'Returns the current local date/time and reference date ranges for interpreting relative expressions such as today/this week/recent.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
};

Map<String, dynamic> get _mcpToolAskUserQuestionTool => {
  'type': 'function',
  'function': {
    'name': 'ask_user_question',
    'description':
        'Ask the user a focused choice question before continuing. Use this when a requirement is ambiguous, multiple implementation directions are reasonable, or the user should compare previews before deciding.',
    'parameters': {
      'type': 'object',
      'properties': {
        'question': {
          'type': 'string',
          'description': 'The concise question to show to the user.',
        },
        'help': {
          'type': 'string',
          'description': 'Optional context explaining why the choice matters.',
        },
        'options': {
          'type': 'array',
          'description':
              'Choice options. Include preview when side-by-side comparison would help.',
          'items': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'string',
                'description': 'Stable machine-readable option identifier.',
              },
              'label': {
                'type': 'string',
                'description': 'Short user-facing option label.',
              },
              'description': {
                'type': 'string',
                'description': 'One or two sentences about the tradeoff.',
              },
              'preview': {
                'type': 'string',
                'description':
                    'Optional concrete preview, snippet, or before/after summary.',
              },
            },
            'required': ['label'],
          },
        },
        'allow_multiple': {
          'type': 'boolean',
          'description': 'Allow selecting more than one option.',
        },
        'allow_other': {
          'type': 'boolean',
          'description': 'Allow free-form Other input.',
        },
        'other_placeholder': {
          'type': 'string',
          'description': 'Placeholder for the Other input.',
        },
      },
      'required': ['question'],
    },
  },
};
