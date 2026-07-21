import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'file_rollback_checkpoint_store.dart';
import 'built_in_filesystem_tool_definitions.dart';
import 'command_payload_facts.dart';
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
        BuiltInFilesystemToolDefinitions.listDirectoryTool,
        BuiltInFilesystemToolDefinitions.readFileTool,
        BuiltInFilesystemToolDefinitions.inspectFileTool,
        BuiltInFilesystemToolDefinitions.findFilesTool,
        BuiltInFilesystemToolDefinitions.searchFilesTool,
      ];

  List<Map<String, dynamic>> get mutationDefinitions => <Map<String, dynamic>>[
    BuiltInFilesystemToolDefinitions.writeFileTool,
    BuiltInFilesystemToolDefinitions.editFileTool,
    BuiltInFilesystemToolDefinitions.deleteFileTool,
    BuiltInFilesystemToolDefinitions.rollbackLastFileChangeTool,
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
      // A successful mutation that changed nothing is the fact worth carrying;
      // a failed one has no effect to describe.
      outcome: payloadSuccess
          ? CommandPayloadFacts.mutationOutcome(result)
          : null,
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
}
