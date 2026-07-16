import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'file_rollback_checkpoint_store.dart';
import 'filesystem_tools.dart';

typedef BuiltInFilesystemOperationRunner =
    Future<String> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

typedef BuiltInFilesystemSnapshotReader =
    Future<TextFileSnapshot> Function(String path);

/// Owns the built-in filesystem tool definitions, execution, and checkpoints.
class BuiltInFilesystemToolHandler {
  BuiltInFilesystemToolHandler({
    BuiltInFilesystemOperationRunner? operationRunner,
    BuiltInFilesystemSnapshotReader? snapshotReader,
    FileRollbackCheckpointStore? checkpointStore,
  }) : _operationRunner = operationRunner ?? _runFilesystemOperation,
       _snapshotReader = snapshotReader ?? FilesystemTools.captureTextSnapshot,
       _checkpointStore = checkpointStore ?? FileRollbackCheckpointStore();

  static const List<String> inspectionToolNames = <String>[
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
  ];

  static const List<String> mutationToolNames = <String>[
    'write_file',
    'edit_file',
    'delete_file',
    'rollback_last_file_change',
  ];

  static const List<String> toolNames = <String>[
    ...inspectionToolNames,
    ...mutationToolNames,
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final BuiltInFilesystemOperationRunner _operationRunner;
  final BuiltInFilesystemSnapshotReader _snapshotReader;
  final FileRollbackCheckpointStore _checkpointStore;

  List<Map<String, dynamic>> get inspectionDefinitions =>
      <Map<String, dynamic>>[
        _listDirectoryTool,
        _readFileTool,
        _inspectFileTool,
        _findFilesTool,
        _searchFilesTool,
      ];

  List<Map<String, dynamic>> get mutationDefinitions => <Map<String, dynamic>>[
    _writeFileTool,
    _editFileTool,
    _deleteFileTool,
    _rollbackLastFileChangeTool,
  ];

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown filesystem tool');
    }

    switch (name) {
      case 'list_directory':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        final result = await _operationRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'recursive': arguments['recursive'] as bool? ?? false,
            'max_entries': ((arguments['max_entries'] as num?)?.toInt() ?? 200)
                .clamp(1, 1000),
          },
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      case 'read_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        final rawLimit = (arguments['limit'] as num?)?.toInt();
        final result = await _operationRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'max_chars': ((arguments['max_chars'] as num?)?.toInt() ?? 120000)
                .clamp(100, 500000),
            'offset': ((arguments['offset'] as num?)?.toInt() ?? 1)
                .clamp(1, 1000000000)
                .toInt(),
            'limit': rawLimit?.clamp(1, 20000).toInt(),
          },
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      case 'inspect_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        final result = await _operationRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'head_lines': ((arguments['head_lines'] as num?)?.toInt() ?? 50)
                .clamp(1, 100)
                .toInt(),
            'tail_lines': ((arguments['tail_lines'] as num?)?.toInt() ?? 20)
                .clamp(0, 50)
                .toInt(),
          },
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      case 'find_files':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        final pattern = (arguments['pattern'] as String?)?.trim() ?? '';
        if (path.isEmpty || pattern.isEmpty) {
          return _validationFailure(name, 'path and pattern are required');
        }
        final result = await _operationRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'pattern': pattern,
            'recursive': arguments['recursive'] as bool? ?? true,
            'max_results': ((arguments['max_results'] as num?)?.toInt() ?? 200)
                .clamp(1, 1000),
          },
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      case 'search_files':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        final query = (arguments['query'] as String?)?.trim() ?? '';
        if (path.isEmpty || query.isEmpty) {
          return _validationFailure(name, 'path and query are required');
        }
        final result = await _operationRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'query': query,
            'file_pattern': (arguments['file_pattern'] as String?)?.trim(),
            'case_sensitive': arguments['case_sensitive'] as bool? ?? false,
            'max_results': ((arguments['max_results'] as num?)?.toInt() ?? 200)
                .clamp(1, 1000),
            'offset': ((arguments['offset'] as num?)?.toInt() ?? 0)
                .clamp(0, 1000000)
                .toInt(),
            'max_line_length':
                ((arguments['max_line_length'] as num?)?.toInt() ?? 500)
                    .clamp(40, 1000)
                    .toInt(),
            'max_bytes_scanned': (arguments['max_bytes_scanned'] as num?)
                ?.toInt(),
          },
        );
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      case 'write_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        return _executeMutation(
          name: name,
          path: path,
          arguments: <String, dynamic>{
            'path': path,
            'content': arguments['content'] as String? ?? '',
            'create_parents': arguments['create_parents'] as bool? ?? true,
          },
          deriveSuccessFromPayload: false,
        );
      case 'edit_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        return _executeMutation(
          name: name,
          path: path,
          arguments: <String, dynamic>{
            'path': path,
            'old_text': arguments['old_text'] as String? ?? '',
            'new_text': arguments['new_text'] as String? ?? '',
            'replace_all': arguments['replace_all'] as bool? ?? false,
          },
          deriveSuccessFromPayload: false,
        );
      case 'delete_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        return _executeMutation(
          name: name,
          path: path,
          arguments: <String, dynamic>{'path': path},
          deriveSuccessFromPayload: true,
        );
      case 'rollback_last_file_change':
        return _checkpointStore.rollbackLastFileChange(toolName: name);
    }

    throw StateError('Unhandled filesystem tool: $name');
  }

  Future<FileRollbackPreview?> previewLastFileRollbackChange() {
    return _checkpointStore.previewLastFileRollbackChange();
  }

  void beginFileTurnCheckpoint(String turnId) {
    _checkpointStore.beginFileTurnCheckpoint(turnId);
  }

  void endFileTurnCheckpoint() {
    _checkpointStore.endFileTurnCheckpoint();
  }

  Future<FileTurnRollbackPreview?> previewLastFileTurnCheckpoint() {
    return _checkpointStore.previewLastFileTurnCheckpoint();
  }

  Future<McpToolResult> rollbackLastFileTurnCheckpoint() {
    return _checkpointStore.rollbackLastFileTurnCheckpoint();
  }

  Future<McpToolResult> _executeMutation({
    required String name,
    required String path,
    required Map<String, dynamic> arguments,
    required bool deriveSuccessFromPayload,
  }) async {
    final snapshot = await _snapshotReader(path);
    final result = await _operationRunner(name: name, arguments: arguments);
    final payloadSuccess = _isFilesystemPayloadSuccess(result);
    if (payloadSuccess) {
      _checkpointStore.push(snapshot);
    }
    final success = deriveSuccessFromPayload ? payloadSuccess : true;
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: success,
      errorMessage: success ? null : 'Failed to delete file',
    );
  }

  static McpToolResult _validationFailure(String name, String message) {
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }

  static bool _isFilesystemPayloadSuccess(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is! Map<String, dynamic> ||
          (decoded['error'] == null && decoded['already_applied'] != true);
    } catch (_) {
      return true;
    }
  }

  static Future<String> _runFilesystemOperation({
    required String name,
    required Map<String, dynamic> arguments,
  }) => switch (name) {
    'list_directory' => FilesystemTools.listDirectory(
      path: arguments['path'] as String,
      recursive: arguments['recursive'] as bool,
      maxEntries: arguments['max_entries'] as int,
    ),
    'read_file' => FilesystemTools.readFile(
      path: arguments['path'] as String,
      maxChars: arguments['max_chars'] as int,
      offset: arguments['offset'] as int,
      limit: arguments['limit'] as int?,
    ),
    'inspect_file' => FilesystemTools.inspectFile(
      path: arguments['path'] as String,
      headLines: arguments['head_lines'] as int,
      tailLines: arguments['tail_lines'] as int,
    ),
    'find_files' => FilesystemTools.findFiles(
      path: arguments['path'] as String,
      pattern: arguments['pattern'] as String,
      recursive: arguments['recursive'] as bool,
      maxResults: arguments['max_results'] as int,
    ),
    'search_files' => FilesystemTools.searchFiles(
      path: arguments['path'] as String,
      query: arguments['query'] as String,
      filePattern: arguments['file_pattern'] as String?,
      caseSensitive: arguments['case_sensitive'] as bool,
      maxResults: arguments['max_results'] as int,
      offset: arguments['offset'] as int,
      maxLineLength: arguments['max_line_length'] as int,
      maxBytesScanned: arguments['max_bytes_scanned'] as int?,
    ),
    'write_file' => FilesystemTools.writeFile(
      path: arguments['path'] as String,
      content: arguments['content'] as String,
      createParents: arguments['create_parents'] as bool,
    ),
    'edit_file' => FilesystemTools.editFile(
      path: arguments['path'] as String,
      oldText: arguments['old_text'] as String,
      newText: arguments['new_text'] as String,
      replaceAll: arguments['replace_all'] as bool,
    ),
    'delete_file' => FilesystemTools.deleteFile(
      path: arguments['path'] as String,
    ),
    _ => throw StateError('Unknown filesystem operation: $name'),
  };

  static Map<String, dynamic> get _listDirectoryTool => {
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

  static Map<String, dynamic> get _readFileTool => {
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

  static Map<String, dynamic> get _inspectFileTool => {
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

  static Map<String, dynamic> get _findFilesTool => {
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

  static Map<String, dynamic> get _searchFilesTool => {
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

  static Map<String, dynamic> get _writeFileTool => {
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

  static Map<String, dynamic> get _editFileTool => {
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

  static Map<String, dynamic> get _deleteFileTool => {
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

  static Map<String, dynamic> get _rollbackLastFileChangeTool => {
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
