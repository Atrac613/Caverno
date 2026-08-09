import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'built_in_filesystem_mutation_effect_boundary.dart';
import 'built_in_filesystem_operation_runner.dart';
import 'built_in_filesystem_tool_definitions.dart';
import 'file_rollback_checkpoint_store.dart';
import 'file_mutation_runtime_contract.dart';
import 'filesystem_tools.dart';
import 'mcp_tool_result_normalizer.dart';

export 'built_in_filesystem_operation_runner.dart'
    show
        BuiltInFilesystemOperationResultRunner,
        BuiltInFilesystemOperationRunner;

part 'built_in_filesystem_mutation_runtime_facade.dart';

typedef BuiltInFilesystemSnapshotReader =
    Future<TextFileSnapshot> Function(String path);

/// Owns the built-in filesystem tool definitions, execution, and checkpoints.
class BuiltInFilesystemToolHandler {
  BuiltInFilesystemToolHandler({
    BuiltInFilesystemOperationRunner? operationRunner,
    BuiltInFilesystemOperationResultRunner? operationResultRunner,
    BuiltInFilesystemSnapshotReader? snapshotReader,
    BuiltInFilesystemMutationSnapshotRestorer? snapshotRestorer,
    FileRollbackCheckpointStore? checkpointStore,
  }) : _operationResultRunner = resolveBuiltInFilesystemOperationRunner(
         legacyRunner: operationRunner,
         resultRunner: operationResultRunner,
       ),
       _snapshotReader = snapshotReader ?? FilesystemTools.captureTextSnapshot,
       _snapshotRestorer = snapshotRestorer,
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

  final BuiltInFilesystemOperationResultRunner _operationResultRunner;
  final BuiltInFilesystemSnapshotReader _snapshotReader;
  final BuiltInFilesystemMutationSnapshotRestorer? _snapshotRestorer;
  final FileRollbackCheckpointStore _checkpointStore;
  late final BuiltInFilesystemMutationEffectBoundary _mutationEffectBoundary =
      BuiltInFilesystemMutationEffectBoundary(
        operationRunner: _operationResultRunner,
        snapshotReader: _snapshotReader,
        snapshotRestorer: _snapshotRestorer,
        checkpointStore: _checkpointStore,
      );

  FileRollbackCheckpointStore get checkpointStore => _checkpointStore;

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
    ChatTurnOwner? owner,
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
        final execution = await _operationResultRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'recursive': arguments['recursive'] as bool? ?? false,
            'max_entries': ((arguments['max_entries'] as num?)?.toInt() ?? 200)
                .clamp(1, 1000),
          },
        );
        return McpToolResult(
          toolName: name,
          result: execution.result,
          isSuccess: true,
          outcome: execution.outcome,
        );
      case 'read_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        final rawLimit = (arguments['limit'] as num?)?.toInt();
        final execution = await _operationResultRunner(
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
        return McpToolResultNormalizer.success(
          toolName: name,
          result: execution.result,
          outcome: execution.outcome,
        );
      case 'inspect_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        final execution = await _operationResultRunner(
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
        return McpToolResult(
          toolName: name,
          result: execution.result,
          isSuccess: true,
          outcome: execution.outcome,
        );
      case 'find_files':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        final pattern = (arguments['pattern'] as String?)?.trim() ?? '';
        if (path.isEmpty || pattern.isEmpty) {
          return _validationFailure(name, 'path and pattern are required');
        }
        final execution = await _operationResultRunner(
          name: name,
          arguments: <String, dynamic>{
            'path': path,
            'pattern': pattern,
            'recursive': arguments['recursive'] as bool? ?? true,
            'max_results': ((arguments['max_results'] as num?)?.toInt() ?? 200)
                .clamp(1, 1000),
          },
        );
        return McpToolResult(
          toolName: name,
          result: execution.result,
          isSuccess: true,
          outcome: execution.outcome,
        );
      case 'search_files':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        final query = (arguments['query'] as String?)?.trim() ?? '';
        if (path.isEmpty || query.isEmpty) {
          return _validationFailure(name, 'path and query are required');
        }
        final execution = await _operationResultRunner(
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
        return McpToolResult(
          toolName: name,
          result: execution.result,
          isSuccess: true,
          outcome: execution.outcome,
        );
      case 'write_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        return _executeMutation(
          owner: owner,
          name: name,
          path: path,
          arguments: <String, dynamic>{
            'path': path,
            'content': arguments['content'] as String? ?? '',
            'create_parents': arguments['create_parents'] as bool? ?? true,
          },
        );
      case 'edit_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        return _executeMutation(
          owner: owner,
          name: name,
          path: path,
          arguments: <String, dynamic>{
            'path': path,
            'old_text': arguments['old_text'] as String? ?? '',
            'new_text': arguments['new_text'] as String? ?? '',
            'replace_all': arguments['replace_all'] as bool? ?? false,
          },
        );
      case 'delete_file':
        final path = (arguments['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          return _validationFailure(name, 'path is required');
        }
        return _executeMutation(
          owner: owner,
          name: name,
          path: path,
          arguments: <String, dynamic>{'path': path},
        );
      case 'rollback_last_file_change':
        return owner == null
            ? _validationFailure(
                name,
                'No recent file change is available to roll back',
              )
            : _checkpointStore.rollbackLastFileChange(
                owner: owner,
                toolName: name,
              );
    }

    throw StateError('Unhandled filesystem tool: $name');
  }

  Future<McpToolResult> _executeMutation({
    required ChatTurnOwner? owner,
    required String name,
    required String path,
    required Map<String, dynamic> arguments,
  }) {
    // Whether a payload decides the result's success is a property of the tool
    // (only delete_file does), resolved inside the effect boundary. A caller
    // flag could only ever restate the name it already passes.
    return _mutationEffectBoundary.executeLegacy(
      owner: owner,
      name: name,
      path: path,
      arguments: arguments,
    );
  }

  static McpToolResult _validationFailure(String name, String message) =>
      McpToolResultNormalizer.failure(toolName: name, errorMessage: message);
}
