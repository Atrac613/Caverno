import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/project_scoped_read_tool_handler.dart';
import 'project_scoped_read_runtime_contract.dart';

export 'project_scoped_read_runtime_contract.dart';

/// Exact callback bridge for local project-scoped inspection tools.
final class ProjectScopedReadToolRuntimeAdapter {
  ProjectScopedReadToolRuntimeAdapter({
    required ProjectScopedReadRootCallback resolveProjectRoot,
    required ProjectScopedReadLifecycleCallback acknowledgeLifecycle,
    required ProjectScopedReadExecutionCallback execute,
    Set<String> supportedToolNames = projectScopedLocalReadToolNames,
  }) : _resolveProjectRoot = resolveProjectRoot,
       _acknowledgeLifecycle = acknowledgeLifecycle,
       _execute = execute,
       _supportedToolNames = Set<String>.unmodifiable(supportedToolNames) {
    for (final name in _supportedToolNames) {
      requireCanonicalProjectScopedReadToolName(name);
    }
  }

  final ProjectScopedReadRootCallback _resolveProjectRoot;
  final ProjectScopedReadLifecycleCallback _acknowledgeLifecycle;
  final ProjectScopedReadExecutionCallback _execute;
  final Set<String> _supportedToolNames;

  Future<ProjectScopedReadRuntimeCompletion> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) async {
    final input = ProjectScopedReadRuntimeInput(
      owner: owner,
      toolCall: toolCall,
    );
    final rootAcknowledgement = _initialRoot(input.identity);
    final toolRequest = input.toToolRequest(
      rootAcknowledgement.rootIdentity.projectRoot,
    );
    final runtimeIdentity = ProjectScopedReadRuntimeIdentity(
      invocation: input.identity,
      root: rootAcknowledgement.rootIdentity,
      toolRequestIdentity: toolRequest.identity,
    );

    final initialDisposition = _initialDisposition(
      input.identity,
      rootAcknowledgement,
    );
    if (initialDisposition != null) {
      return ProjectScopedReadRuntimeCompletion(
        identity: runtimeIdentity,
        disposition: initialDisposition,
        result: _failureForDisposition(
          input.identity.toolName,
          initialDisposition,
          'The project root could not be resolved for the exact tool call.',
        ),
      );
    }
    if (!_supportedToolNames.contains(input.identity.toolName)) {
      return ProjectScopedReadRuntimeCompletion(
        identity: runtimeIdentity,
        disposition: ProjectScopedReadRuntimeDisposition.rejected,
        result: _failure(
          input.identity.toolName,
          'project_scoped_read_rejected',
          'The local project-scoped read tool is not supported.',
        ),
      );
    }

    final bridge = _ProjectScopedReadRuntimeBridge(
      runtimeIdentity: runtimeIdentity,
      resolveProjectRoot: _resolveProjectRoot,
      acknowledgeLifecycle: _acknowledgeLifecycle,
      execute: _execute,
    );
    final handler = ProjectScopedReadToolHandler(
      executionPort: bridge,
      lifecyclePort: bridge,
      supportedToolNames: _supportedToolNames,
    );
    McpToolResult result;
    try {
      result = await handler.handle(toolRequest);
    } catch (error) {
      bridge.markEffectUncertain();
      result = _failure(
        input.identity.toolName,
        'project_scoped_read_effect_uncertain',
        'The local read completion could not be verified: $error',
      );
    }
    return ProjectScopedReadRuntimeCompletion(
      identity: runtimeIdentity,
      disposition: bridge.classify(result),
      result: result,
    );
  }

  ProjectScopedReadRootAcknowledgement _initialRoot(
    ProjectScopedReadInvocationIdentity identity,
  ) {
    try {
      return _resolveProjectRoot(identity);
    } catch (_) {
      return ProjectScopedReadRootAcknowledgement(
        identity: identity,
        projectRoot: null,
        disposition: ProjectScopedReadRootDisposition.effectUncertain,
      );
    }
  }

  ProjectScopedReadRuntimeDisposition? _initialDisposition(
    ProjectScopedReadInvocationIdentity expected,
    ProjectScopedReadRootAcknowledgement acknowledgement,
  ) {
    if (acknowledgement.identity != expected) {
      return ProjectScopedReadRuntimeDisposition.boundaryMismatch;
    }
    return switch (acknowledgement.disposition) {
      ProjectScopedReadRootDisposition.resolved => null,
      ProjectScopedReadRootDisposition.rejected =>
        ProjectScopedReadRuntimeDisposition.rejected,
      ProjectScopedReadRootDisposition.effectUncertain =>
        ProjectScopedReadRuntimeDisposition.effectUncertain,
    };
  }
}

final class _ProjectScopedReadRuntimeBridge
    implements ProjectScopedReadLifecyclePort, McpToolExecutionPort {
  _ProjectScopedReadRuntimeBridge({
    required this.runtimeIdentity,
    required ProjectScopedReadRootCallback resolveProjectRoot,
    required ProjectScopedReadLifecycleCallback acknowledgeLifecycle,
    required ProjectScopedReadExecutionCallback execute,
  }) : _resolveProjectRoot = resolveProjectRoot,
       _acknowledgeLifecycle = acknowledgeLifecycle,
       _execute = execute;

  final ProjectScopedReadRuntimeIdentity runtimeIdentity;
  final ProjectScopedReadRootCallback _resolveProjectRoot;
  final ProjectScopedReadLifecycleCallback _acknowledgeLifecycle;
  final ProjectScopedReadExecutionCallback _execute;
  ProjectScopedReadRuntimeDisposition? _observedDisposition;
  bool _executionStarted = false;

  @override
  bool isCurrent(ProjectScopedReadOperationIdentity identity) {
    if (identity != runtimeIdentity.toolRequestIdentity) {
      _observe(ProjectScopedReadRuntimeDisposition.boundaryMismatch);
      return false;
    }
    final ProjectScopedReadLifecycleAcknowledgement acknowledgement;
    try {
      acknowledgement = _acknowledgeLifecycle(runtimeIdentity);
    } catch (_) {
      markEffectUncertain();
      return false;
    }
    if (acknowledgement.identity != runtimeIdentity) {
      _observe(ProjectScopedReadRuntimeDisposition.boundaryMismatch);
      return false;
    }
    switch (acknowledgement.disposition) {
      case ProjectScopedReadLifecycleDisposition.current:
        break;
      case ProjectScopedReadLifecycleDisposition.rejected:
        _observe(ProjectScopedReadRuntimeDisposition.rejected);
        return false;
      case ProjectScopedReadLifecycleDisposition.ownerExpired:
        _observe(ProjectScopedReadRuntimeDisposition.ownerExpired);
        return false;
      case ProjectScopedReadLifecycleDisposition.effectUncertain:
        markEffectUncertain();
        return false;
    }
    if (!_rootIsCurrent()) {
      _observe(
        _executionStarted
            ? ProjectScopedReadRuntimeDisposition.effectUncertain
            : ProjectScopedReadRuntimeDisposition.rejected,
      );
      return false;
    }
    return true;
  }

  @override
  Future<ProjectScopedReadCompletion> execute(
    ProjectScopedReadOperationIdentity identity,
    Map<String, dynamic> resolvedArguments,
  ) async {
    if (identity != runtimeIdentity.toolRequestIdentity) {
      _observe(ProjectScopedReadRuntimeDisposition.boundaryMismatch);
      return _uncertainCompletion(
        identity,
        'Read operation identity mismatch.',
      );
    }
    final Map<String, dynamic> arguments;
    try {
      arguments = freezeStrictProjectScopedReadArguments(resolvedArguments);
    } catch (error) {
      _observe(ProjectScopedReadRuntimeDisposition.rejected);
      return ProjectScopedReadCompletion(
        identity: identity,
        result: _failure(
          identity.toolName,
          'project_scoped_read_rejected',
          'Resolved read arguments are not strict JSON: $error',
        ),
      );
    }
    final executionIdentity = ProjectScopedReadExecutionIdentity(
      runtime: runtimeIdentity,
      resolvedArgumentDigest: projectScopedReadArgumentDigest(arguments),
    );
    final request = ProjectScopedReadExecutionRequest(
      identity: executionIdentity,
      arguments: arguments,
    );
    _executionStarted = true;
    final ProjectScopedReadExecutionAcknowledgement acknowledgement;
    try {
      acknowledgement = await _execute(request);
    } catch (error) {
      markEffectUncertain();
      return _uncertainCompletion(
        identity,
        'The local read callback failed after dispatch: $error',
      );
    }
    if (acknowledgement.identity != executionIdentity) {
      _observe(ProjectScopedReadRuntimeDisposition.boundaryMismatch);
      return _uncertainCompletion(
        identity,
        'Read execution acknowledgement identity mismatch.',
      );
    }
    if (!_rootIsCurrent()) {
      markEffectUncertain();
      return _uncertainCompletion(
        identity,
        'The project root changed while the local read was running.',
      );
    }
    return _mapAcknowledgement(identity, acknowledgement);
  }

  ProjectScopedReadCompletion _mapAcknowledgement(
    ProjectScopedReadOperationIdentity identity,
    ProjectScopedReadExecutionAcknowledgement acknowledgement,
  ) {
    final result = acknowledgement.result;
    switch (acknowledgement.disposition) {
      case ProjectScopedReadExecutionDisposition.completed:
        if (result == null || result.toolName != identity.toolName) {
          _observe(ProjectScopedReadRuntimeDisposition.boundaryMismatch);
          return _uncertainCompletion(
            identity,
            'Read result tool identity mismatch.',
          );
        }
        return ProjectScopedReadCompletion(identity: identity, result: result);
      case ProjectScopedReadExecutionDisposition.rejected:
        _observe(ProjectScopedReadRuntimeDisposition.rejected);
        return ProjectScopedReadCompletion(
          identity: identity,
          result: _validFailure(result, identity.toolName)
              ? result!
              : _failure(
                  identity.toolName,
                  'project_scoped_read_rejected',
                  acknowledgement.message ?? 'The local read was rejected.',
                ),
        );
      case ProjectScopedReadExecutionDisposition.ownerExpired:
        _observe(ProjectScopedReadRuntimeDisposition.ownerExpired);
        return ProjectScopedReadCompletion(
          identity: identity,
          result: _failure(
            identity.toolName,
            'turn_owner_expired',
            acknowledgement.message ?? 'The read owner expired.',
          ),
        );
      case ProjectScopedReadExecutionDisposition.effectUncertain:
        markEffectUncertain();
        return _uncertainCompletion(
          identity,
          acknowledgement.message ?? 'The local read result is uncertain.',
        );
    }
  }

  bool _rootIsCurrent() {
    try {
      final acknowledgement = _resolveProjectRoot(runtimeIdentity.invocation);
      return acknowledgement.identity == runtimeIdentity.invocation &&
          acknowledgement.disposition ==
              ProjectScopedReadRootDisposition.resolved &&
          acknowledgement.rootIdentity == runtimeIdentity.root;
    } catch (_) {
      return false;
    }
  }

  ProjectScopedReadCompletion _uncertainCompletion(
    ProjectScopedReadOperationIdentity identity,
    String message,
  ) {
    markEffectUncertain();
    return ProjectScopedReadCompletion(
      identity: identity,
      result: _failure(
        identity.toolName,
        'project_scoped_read_effect_uncertain',
        message,
      ),
    );
  }

  ProjectScopedReadRuntimeDisposition classify(McpToolResult result) {
    if (_observedDisposition != null) return _observedDisposition!;
    return result.isSuccess
        ? ProjectScopedReadRuntimeDisposition.completed
        : ProjectScopedReadRuntimeDisposition.rejected;
  }

  void markEffectUncertain() {
    _observe(ProjectScopedReadRuntimeDisposition.effectUncertain);
  }

  void _observe(ProjectScopedReadRuntimeDisposition disposition) {
    final current = _observedDisposition;
    if (current == ProjectScopedReadRuntimeDisposition.effectUncertain) return;
    if (disposition == ProjectScopedReadRuntimeDisposition.effectUncertain ||
        current == null ||
        disposition == ProjectScopedReadRuntimeDisposition.boundaryMismatch) {
      _observedDisposition = disposition;
    }
  }
}

bool _validFailure(McpToolResult? result, String toolName) =>
    result != null && !result.isSuccess && result.toolName == toolName;

McpToolResult _failureForDisposition(
  String toolName,
  ProjectScopedReadRuntimeDisposition disposition,
  String message,
) {
  final code = switch (disposition) {
    ProjectScopedReadRuntimeDisposition.rejected =>
      'project_scoped_read_rejected',
    ProjectScopedReadRuntimeDisposition.ownerExpired => 'turn_owner_expired',
    ProjectScopedReadRuntimeDisposition.effectUncertain ||
    ProjectScopedReadRuntimeDisposition.boundaryMismatch =>
      'project_scoped_read_effect_uncertain',
    ProjectScopedReadRuntimeDisposition.completed => throw StateError(
      'Completed reads do not use failure results.',
    ),
  };
  return _failure(toolName, code, message);
}

McpToolResult _failure(String toolName, String code, String message) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': code,
      'error': message,
      'next_action': 'Repeat the read in the current turn.',
    }),
    isSuccess: false,
    errorMessage: message,
  );
}
