/// Static OpenAI tool definitions for the built-in filesystem surface.
///
/// Split out of `BuiltInFilesystemToolHandler` so the handler holds only
/// dispatch, mutation, and checkpoint logic: these are inert JSON schemas, and
/// keeping ~270 lines of them alongside the execution paths made the file's
/// real behavior hard to find. Mirrors
/// `built_in_local_command_tool_definitions.dart`.
abstract final class BuiltInFilesystemToolDefinitions {
  static Map<String, dynamic> get listDirectoryTool => {
    'type': 'function',
    'function': {
      'name': 'list_directory',
      'description':
          'List files and directories inside a local directory. Useful for '
          'understanding project structure before reading or editing files.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute or project-relative directory path. Optional when a coding project is selected.',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Whether to include nested files and folders.',
          },
          'max_entries': {
            'type': 'integer',
            'description': 'Maximum number of entries to return.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get readFileTool => {
    'type': 'function',
    'function': {
      'name': 'read_file',
      'description':
          'Read a UTF-8 text file from the local project. Use offset and limit '
          'to inspect a specific line range in large files. For very large '
          'files (logs, exports), call inspect_file first, then read only the '
          'ranges you need — never try to read the whole file at once.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'max_chars': {
            'type': 'integer',
            'description': 'Maximum number of characters to return.',
          },
          'offset': {
            'type': 'integer',
            'description': '1-based start line for range reads.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of lines to return.',
          },
        },
        'required': ['path'],
      },
    },
  };

  static Map<String, dynamic> get inspectFileTool => {
    'type': 'function',
    'function': {
      'name': 'inspect_file',
      'description':
          'Inspect a local text file WITHOUT loading it fully into memory. '
          'Returns byte size, total line count, head and tail samples, detected '
          'encoding, and a format hint. Call this FIRST on large or unknown '
          'files (logs, JSONL/CSV exports, multi-MB text) before searching or '
          'range-reading them.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'head_lines': {
            'type': 'integer',
            'description': 'Number of leading lines to sample (1-100).',
          },
          'tail_lines': {
            'type': 'integer',
            'description': 'Number of trailing lines to sample (0-50).',
          },
        },
        'required': ['path'],
      },
    },
  };

  static Map<String, dynamic> get findFilesTool => {
    'type': 'function',
    'function': {
      'name': 'find_files',
      'description':
          'Find files in the local project by wildcard pattern such as "*.dart" or "*test*".',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute or project-relative directory path. Optional when a coding project is selected.',
          },
          'pattern': {
            'type': 'string',
            'description': 'Wildcard filename or path pattern.',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Whether to search subdirectories.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of matches to return.',
          },
        },
        'required': ['pattern'],
      },
    },
  };

  static Map<String, dynamic> get searchFilesTool => {
    'type': 'function',
    'function': {
      'name': 'search_files',
      'description':
          'Search text across local project files (streamed line by line, so '
          'large logs are supported) and return matching lines with file paths '
          'and line numbers.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute or project-relative directory path. Optional when a coding project is selected.',
          },
          'query': {'type': 'string', 'description': 'Text to search for.'},
          'file_pattern': {
            'type': 'string',
            'description': 'Optional wildcard filter such as "*.dart".',
          },
          'case_sensitive': {
            'type': 'boolean',
            'description': 'Whether the search should be case-sensitive.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of matching lines to return.',
          },
          'offset': {
            'type': 'integer',
            'description':
                'Number of matching lines to skip before returning results.',
          },
          'max_line_length': {
            'type': 'integer',
            'description':
                'Truncate each matched line to this many characters (40-1000).',
          },
          'max_bytes_scanned': {
            'type': 'integer',
            'description':
                'Optional ceiling on total bytes scanned across all files.',
          },
        },
        'required': ['query'],
      },
    },
  };

  static Map<String, dynamic> get writeFileTool => {
    'type': 'function',
    'function': {
      'name': 'write_file',
      'description':
          'Write a full UTF-8 text file in the local project. This can create or overwrite files and requires user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'content': {
            'type': 'string',
            'description': 'Complete file content to write.',
          },
          'create_parents': {
            'type': 'boolean',
            'description': 'Create parent directories when needed.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['path', 'content'],
      },
    },
  };

  static Map<String, dynamic> get editFileTool => {
    'type': 'function',
    'function': {
      'name': 'edit_file',
      'description':
          'Replace text inside a local UTF-8 file. This is useful for targeted edits and requires user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'old_text': {
            'type': 'string',
            'description': 'Exact text to replace.',
          },
          'new_text': {'type': 'string', 'description': 'Replacement text.'},
          'replace_all': {
            'type': 'boolean',
            'description': 'Replace all matches instead of only the first.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['path', 'old_text', 'new_text'],
      },
    },
  };

  static Map<String, dynamic> get deleteFileTool => {
    'type': 'function',
    'function': {
      'name': 'delete_file',
      'description':
          'Delete one unnecessary UTF-8 text file from the local project. Directories and symbolic links are rejected. This requires user approval and can be rolled back.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or project-relative file path.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
        'required': ['path'],
      },
    },
  };

  static Map<String, dynamic> get rollbackLastFileChangeTool => {
    'type': 'function',
    'function': {
      'name': 'rollback_last_file_change',
      'description':
          'Revert the most recent successful local file change performed '
          'through write_file or edit_file. This requires user approval and '
          'restores the previous UTF-8 contents, or deletes the file if it '
          'was newly created.',
      'parameters': {
        'type': 'object',
        'properties': {
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown in the approval dialog.',
          },
        },
      },
    },
  };
}
