part of 'mcp_tool_service.dart';

final Map<String, dynamic> _deleteFileToolDefinition = {
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

extension McpToolServiceDeleteFile on McpToolService {
  Future<McpToolResult> _executeDeleteFileTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final path = (arguments['path'] as String?)?.trim() ?? '';
    if (path.isEmpty) {
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }
    final snapshot = await FilesystemTools.captureTextSnapshot(path);
    final result = await FilesystemTools.deleteFile(path: path);
    final success = _isFilesystemPayloadSuccess(result);
    if (success) {
      _pushFileRollbackEntry(snapshot);
    }
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: success,
      errorMessage: success ? null : 'Failed to delete file',
    );
  }
}
