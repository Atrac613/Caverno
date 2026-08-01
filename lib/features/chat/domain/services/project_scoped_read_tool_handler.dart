import 'dart:convert';

import '../../data/datasources/project_scoped_tool_argument_resolver.dart';
import '../entities/mcp_tool_entity.dart';
import 'project_scoped_read_tool_contract.dart';

export 'project_scoped_read_tool_contract.dart';

// ChatNotifier decomposition collaborator: project-scoped-read-tool-handler

/// Resolves and executes read-only tools for one exact immutable call.
final class ProjectScopedReadToolHandler {
  ProjectScopedReadToolHandler({
    required McpToolExecutionPort executionPort,
    required ProjectScopedReadLifecyclePort lifecyclePort,
    required Set<String> supportedToolNames,
  }) : _executionPort = executionPort,
       _lifecyclePort = lifecyclePort,
       supportedToolNames = Set<String>.unmodifiable(supportedToolNames) {
    for (final name in this.supportedToolNames) {
      requireCanonicalProjectScopedReadToolName(name);
    }
  }

  final McpToolExecutionPort _executionPort;
  final ProjectScopedReadLifecyclePort _lifecyclePort;
  final Set<String> supportedToolNames;

  Future<McpToolResult> handle(ProjectScopedReadToolRequest request) async {
    if (!supportedToolNames.contains(request.toolName)) {
      throw ArgumentError.value(
        request.toolName,
        'toolName',
        'Unsupported project-scoped read tool',
      );
    }
    if (!_lifecyclePort.isCurrent(request.identity)) {
      return _expired(request);
    }

    final resolvedArguments = freezeProjectScopedReadArguments(
      ProjectScopedToolArgumentResolver.resolve(
        toolName: request.toolName,
        arguments: request.arguments,
        loadProjectRoot: () => request.ownerProjectRoot,
      ),
    );
    if (!_lifecyclePort.isCurrent(request.identity)) {
      return _expired(request);
    }

    late final ProjectScopedReadCompletion completion;
    try {
      completion = await _executionPort.execute(
        request.identity,
        resolvedArguments,
      );
    } catch (_) {
      if (!_lifecyclePort.isCurrent(request.identity)) {
        return _expired(request);
      }
      rethrow;
    }
    if (completion.identity != request.identity ||
        completion.result.toolName != request.toolName ||
        !_lifecyclePort.isCurrent(request.identity)) {
      return _expired(request);
    }
    return completion.result;
  }

  McpToolResult _expired(ProjectScopedReadToolRequest request) {
    final processObservation = _isProcessObservation(request.toolName);
    final message = processObservation
        ? 'The background process observation may belong to an expired or '
              'different tool call'
        : 'The turn owner expired before the read completed';
    return McpToolResult(
      toolName: request.toolName,
      result: jsonEncode({
        'ok': false,
        'code': processObservation
            ? 'background_process_observation_uncertain'
            : 'turn_owner_expired',
        'error': '$message.',
        'next_action': processObservation
            ? 'Repeat the observation with the exact job_id before relying '
                  'on process status or output.'
            : 'Repeat the read in the current turn.',
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }

  bool _isProcessObservation(String toolName) => const {
    'process_status',
    'process_tail',
    'process_wait',
    'process_list',
  }.contains(toolName);
}
