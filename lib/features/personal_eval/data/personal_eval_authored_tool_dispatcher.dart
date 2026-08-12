import 'dart:convert';
import 'dart:io';

import '../../chat/data/datasources/filesystem_tools.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/tool_call_info.dart';
import '../domain/services/personal_eval_verification_runner.dart';

/// A deliberately small tool surface for an authored personal-eval fixture.
///
/// Reads stay inside the disposable fixture, mutations stay inside `src/`, and
/// command execution is limited to the case's exact verification command at
/// the fixture root. This prevents a candidate from editing the verifier or
/// using the eval harness as a general local shell.
class PersonalEvalAuthoredToolDispatcher {
  PersonalEvalAuthoredToolDispatcher({
    required Directory root,
    required String verificationCommand,
    required PersonalEvalVerificationRunner verificationRunner,
  }) : _root = root.absolute,
       _verificationCommand = verificationCommand.trim(),
       _verificationRunner = verificationRunner;

  final Directory _root;
  final String _verificationCommand;
  final PersonalEvalVerificationRunner _verificationRunner;

  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    _toolDefinition(
      name: 'list_directory',
      description: 'List files inside the isolated evaluation fixture.',
      properties: {
        'path': {'type': 'string'},
        'recursive': {'type': 'boolean'},
        'max_entries': {'type': 'integer'},
      },
    ),
    _toolDefinition(
      name: 'read_file',
      description: 'Read a UTF-8 file inside the isolated evaluation fixture.',
      properties: {
        'path': {'type': 'string'},
        'offset': {'type': 'integer'},
        'limit': {'type': 'integer'},
      },
      required: const ['path'],
    ),
    _toolDefinition(
      name: 'edit_file',
      description: 'Replace exact text in a source file under src/.',
      properties: {
        'path': {'type': 'string'},
        'old_text': {'type': 'string'},
        'new_text': {'type': 'string'},
        'replace_all': {'type': 'boolean'},
        'reason': {'type': 'string'},
      },
      required: const ['path', 'old_text', 'new_text'],
    ),
    _toolDefinition(
      name: 'write_file',
      description: 'Write a complete source file under src/.',
      properties: {
        'path': {'type': 'string'},
        'content': {'type': 'string'},
        'create_parents': {'type': 'boolean'},
        'reason': {'type': 'string'},
      },
      required: const ['path', 'content'],
    ),
    _toolDefinition(
      name: 'local_execute_command',
      description:
          'Run the fixture verification command at the fixture root. The only '
          'accepted command is: $_verificationCommand',
      properties: {
        'command': {'type': 'string'},
        'working_directory': {'type': 'string'},
        'reason': {'type': 'string'},
      },
      required: const ['command'],
    ),
  ];

  Future<McpToolResult> dispatch(ToolCallInfo toolCall) =>
      executeTool(name: toolCall.name, arguments: toolCall.arguments);

  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    switch (name) {
      case 'list_directory':
        final path = _resolveReadPath(
          arguments['path'] as String?,
          allowEmpty: true,
          directory: true,
        );
        if (path.error != null) return _error(name, path.error!);
        return _fromFilesystemResult(
          name,
          await FilesystemTools.listDirectory(
            path: path.value!,
            recursive: arguments['recursive'] as bool? ?? false,
            maxEntries: ((arguments['max_entries'] as num?)?.toInt() ?? 200)
                .clamp(1, 500),
          ),
        );
      case 'read_file':
        final path = _resolveReadPath(arguments['path'] as String?);
        if (path.error != null) return _error(name, path.error!);
        return _fromFilesystemResult(
          name,
          await FilesystemTools.readFile(
            path: path.value!,
            offset: ((arguments['offset'] as num?)?.toInt() ?? 1).clamp(
              1,
              1000000,
            ),
            limit: (arguments['limit'] as num?)?.toInt(),
          ),
        );
      case 'edit_file':
        final path = _resolveMutationPath(arguments['path'] as String?);
        if (path.error != null) return _error(name, path.error!);
        return _fromFilesystemResult(
          name,
          await FilesystemTools.editFile(
            path: path.value!,
            oldText: arguments['old_text'] as String? ?? '',
            newText: arguments['new_text'] as String? ?? '',
            replaceAll: arguments['replace_all'] as bool? ?? false,
          ),
        );
      case 'write_file':
        final path = _resolveMutationPath(arguments['path'] as String?);
        if (path.error != null) return _error(name, path.error!);
        return _fromFilesystemResult(
          name,
          await FilesystemTools.writeFile(
            path: path.value!,
            content: arguments['content'] as String? ?? '',
            createParents: arguments['create_parents'] as bool? ?? true,
          ),
        );
      case 'local_execute_command':
        return _executeVerification(name, arguments);
      default:
        return _error(name, 'Unsupported authored evaluation tool: $name');
    }
  }

  Future<McpToolResult> _executeVerification(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = (arguments['command'] as String?)?.trim() ?? '';
    if (command != _verificationCommand || command.isEmpty) {
      return _error(
        name,
        'Only the authored case verification command is allowed.',
      );
    }
    final directory = _resolveReadPath(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (directory.error != null) return _error(name, directory.error!);
    if (directory.value != _root.path) {
      return _error(name, 'working_directory must be the fixture root.');
    }

    final outcome = await _verificationRunner.run(
      command: command,
      workingDirectory: _root.path,
    );
    final payload = jsonEncode({
      'command': command,
      'working_directory': _root.path,
      'exit_code': outcome.exitCode,
      'stdout': outcome.stdout,
      'stderr': outcome.stderr,
      'timed_out': outcome.timedOut,
      if (outcome.error != null) 'error': outcome.error,
    });
    final success = outcome.exitCode == 0 && outcome.error == null;
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: success,
      errorMessage: success
          ? null
          : outcome.error ?? 'Command exited with code ${outcome.exitCode}',
    );
  }

  _ResolvedEvalPath _resolveReadPath(
    String? rawPath, {
    bool allowEmpty = false,
    bool directory = false,
  }) => _resolvePath(
    rawPath,
    allowedRoot: _root,
    allowEmpty: allowEmpty,
    directory: directory,
  );

  _ResolvedEvalPath _resolveMutationPath(String? rawPath) => _resolvePath(
    rawPath,
    allowedRoot: Directory('${_root.path}${Platform.pathSeparator}src'),
  );

  _ResolvedEvalPath _resolvePath(
    String? rawPath, {
    required Directory allowedRoot,
    bool allowEmpty = false,
    bool directory = false,
  }) {
    final trimmed = rawPath?.trim();
    final effective = (trimmed == null || trimmed.isEmpty) && allowEmpty
        ? ''
        : trimmed;
    final resolved = FilesystemTools.resolvePath(
      effective,
      defaultRoot: _root.path,
    );
    if (resolved == null || resolved.trim().isEmpty) {
      return const _ResolvedEvalPath(error: 'path is required');
    }
    final target = directory
        ? Directory(resolved).absolute.path
        : File(resolved).absolute.path;
    final boundary = allowedRoot.absolute.path;
    if (target != boundary &&
        !target.startsWith('$boundary${Platform.pathSeparator}')) {
      return _ResolvedEvalPath(
        error: 'Path must stay inside ${allowedRoot.path}.',
      );
    }
    if (!_canonicalAncestorStaysInside(target, boundary)) {
      return _ResolvedEvalPath(
        error: 'Path must not traverse a link outside ${allowedRoot.path}.',
      );
    }
    return _ResolvedEvalPath(value: target);
  }

  bool _canonicalAncestorStaysInside(String target, String boundary) {
    String canonicalBoundary;
    try {
      canonicalBoundary = _canonicalPath(boundary);
    } on FileSystemException {
      return false;
    }

    var probe = target;
    while (FileSystemEntity.typeSync(probe, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = File(probe).parent.path;
      if (parent == probe) return false;
      probe = parent;
    }
    try {
      final canonicalProbe = _canonicalPath(probe);
      return canonicalProbe == canonicalBoundary ||
          canonicalProbe.startsWith(
            '$canonicalBoundary${Platform.pathSeparator}',
          );
    } on FileSystemException {
      return false;
    }
  }

  String _canonicalPath(String path) => File(path).resolveSymbolicLinksSync();

  static Map<String, dynamic> _toolDefinition({
    required String name,
    required String description,
    required Map<String, dynamic> properties,
    List<String> required = const [],
  }) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
      },
    },
  };

  McpToolResult _fromFilesystemResult(String name, String result) {
    String? error;
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) error = decoded['error'] as String?;
    } on FormatException {
      error = 'Tool returned invalid JSON.';
    }
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: error == null || error.isEmpty,
      errorMessage: error,
    );
  }

  McpToolResult _error(String name, String error) => McpToolResult(
    toolName: name,
    result: jsonEncode({'error': error}),
    isSuccess: false,
    errorMessage: error,
  );
}

class _ResolvedEvalPath {
  const _ResolvedEvalPath({this.value, this.error});

  final String? value;
  final String? error;
}
