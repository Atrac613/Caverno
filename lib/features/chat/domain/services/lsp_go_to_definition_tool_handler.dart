import 'dart:convert';

import '../../data/datasources/project_scoped_tool_argument_resolver.dart';
import '../entities/mcp_tool_entity.dart';
import 'dart_project_tooling.dart';
import 'lsp_go_to_definition_tool_contract.dart';

export 'lsp_go_to_definition_tool_contract.dart';

// ChatNotifier decomposition collaborator: lsp-go-to-definition-tool-handler

/// Validates and maps the `lsp_go_to_definition` tool contract.
final class LspGoToDefinitionToolHandler {
  const LspGoToDefinitionToolHandler({
    required LspDefinitionPort port,
    required LspDefinitionLifecyclePort lifecyclePort,
  }) : _port = port,
       _lifecyclePort = lifecyclePort;

  final LspDefinitionPort _port;
  final LspDefinitionLifecyclePort _lifecyclePort;

  Future<McpToolResult> handle(LspGoToDefinitionToolInput input) async {
    final projectRoot = input.ownerProjectRoot;
    if (projectRoot == null || projectRoot.trim().isEmpty) {
      return McpToolResult(
        toolName: input.toolName,
        result: jsonEncode({
          'ok': false,
          'code': 'active_coding_project_required',
          'error':
              'An active coding project is required for LSP go-to-definition.',
        }),
        isSuccess: false,
        errorMessage: 'An active coding project is required',
      );
    }

    final resolvedArguments = ProjectScopedToolArgumentResolver.resolve(
      toolName: input.toolName,
      arguments: input.arguments,
      loadProjectRoot: () => projectRoot,
    );
    final path = (resolvedArguments['path'] as String?)?.trim() ?? '';
    final line = _oneBasedPositionValue(resolvedArguments['line']);
    final column = _oneBasedPositionValue(resolvedArguments['column']);
    if (path.isEmpty || line == null || column == null) {
      return McpToolResult(
        toolName: input.toolName,
        result: jsonEncode({
          'ok': false,
          'code': 'invalid_arguments',
          'error': 'path, line, and column are required.',
        }),
        isSuccess: false,
        errorMessage: 'path, line, and column are required',
      );
    }

    final request = LspDefinitionLookupRequest(
      identity: input.identity,
      projectRoot: projectRoot,
      path: path,
      line: line - 1,
      character: column - 1,
    );
    final beforeDispatch = _acknowledgeOwner(input.identity);
    if (beforeDispatch == null ||
        beforeDispatch.disposition !=
            LspDefinitionOwnerAcknowledgementDisposition.current) {
      return _ownerExpired(input.toolName, path);
    }

    late final LspDefinitionLookupResult completion;
    try {
      completion = await _port.goToDefinition(request);
    } catch (_) {
      return _effectUncertain(input.toolName, path);
    }
    if (completion.identity != input.identity) {
      return _effectUncertain(input.toolName, path);
    }

    final afterDispatch = _acknowledgeOwner(input.identity);
    if (afterDispatch == null) {
      return _effectUncertain(input.toolName, path);
    }
    if (completion.kind == LspDefinitionLookupResultKind.effectUncertain ||
        completion.sessionEffect == LspDefinitionSessionEffect.uncertain) {
      return _effectUncertain(input.toolName, path);
    }
    if (completion.kind == LspDefinitionLookupResultKind.ownerExpired ||
        afterDispatch.disposition ==
            LspDefinitionOwnerAcknowledgementDisposition.ownerExpired) {
      return _mayHaveStartedPersistentSession(completion.sessionEffect)
          ? _effectUncertain(input.toolName, path)
          : _ownerExpired(input.toolName, path);
    }
    if (completion.kind == LspDefinitionLookupResultKind.failed) {
      return _lookupFailed(
        input.toolName,
        path,
        completion.errorMessage ?? 'LSP definition lookup failed',
      );
    }

    final definitions = completion.definitions;
    if (definitions == null) {
      return McpToolResult(
        toolName: input.toolName,
        result: jsonEncode({
          'ok': false,
          'code': 'language_server_unavailable',
          'error':
              'No supported language server session is available for this file.',
          'path': path,
        }),
        isSuccess: false,
        errorMessage: 'No supported language server session is available',
      );
    }

    return McpToolResult(
      toolName: input.toolName,
      result: jsonEncode({
        'ok': true,
        'provider': 'lsp_json_rpc',
        'path': path,
        'line': line,
        'column': column,
        'definition_count': definitions.length,
        'definitions': definitions
            .map(
              (definition) =>
                  _lspDefinitionToJson(definition, projectRoot: projectRoot),
            )
            .toList(growable: false),
      }),
      isSuccess: true,
    );
  }

  LspDefinitionOwnerAcknowledgement? _acknowledgeOwner(
    LspDefinitionOperationIdentity identity,
  ) {
    try {
      final acknowledgement = _lifecyclePort.acknowledgeOwner(identity);
      return acknowledgement.identity == identity ? acknowledgement : null;
    } catch (_) {
      return null;
    }
  }

  bool _mayHaveStartedPersistentSession(LspDefinitionSessionEffect effect) {
    return effect == LspDefinitionSessionEffect.started ||
        effect == LspDefinitionSessionEffect.uncertain;
  }

  McpToolResult _lookupFailed(String toolName, String path, String error) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'lsp_go_to_definition_failed',
        'error': error,
        'path': path,
      }),
      isSuccess: false,
      errorMessage: error,
    );
  }

  McpToolResult _effectUncertain(String toolName, String path) {
    const message =
        'The LSP definition lookup process outcome is uncertain; inspect '
        'possible process side effects before retrying';
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'lsp_session_outcome_uncertain',
        'error': '$message.',
        'path': path,
        'next_action':
            'Inspect active language server processes before retrying the '
            'lookup.',
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }

  McpToolResult _ownerExpired(String toolName, String path) {
    const message =
        'The turn owner expired before LSP go-to-definition completed';
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'turn_owner_expired',
        'error': '$message.',
        'path': path,
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }

  int? _oneBasedPositionValue(Object? value) {
    final rawValue = switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (rawValue == null || rawValue < 1) {
      return null;
    }
    return rawValue;
  }

  Map<String, dynamic> _lspDefinitionToJson(
    LspDefinitionLocation definition, {
    required String projectRoot,
  }) {
    final absolutePath = _pathFromLspUri(definition.uri);
    final insideProject =
        absolutePath != null &&
        DartProjectPath.isInsideRoot(absolutePath, projectRoot);
    return {
      'uri': definition.uri,
      'path': ?absolutePath,
      if (insideProject)
        'relative_path': DartProjectPath.relativePath(
          absolutePath,
          projectRoot,
        ).replaceAll('\\', '/'),
      'line': definition.startLine + 1,
      'column': definition.startCharacter + 1,
      if (definition.endLine != null) 'end_line': definition.endLine! + 1,
      if (definition.endCharacter != null)
        'end_column': definition.endCharacter! + 1,
    };
  }

  String? _pathFromLspUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.scheme == 'file') {
        return parsed.toFilePath();
      }
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
    return null;
  }
}
