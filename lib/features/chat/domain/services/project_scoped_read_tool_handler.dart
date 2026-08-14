import '../../data/datasources/project_scoped_tool_argument_resolver.dart';
import '../../data/datasources/project_read_tool_authorizer.dart';
import '../entities/mcp_tool_entity.dart';
import 'project_scoped_read_expiry_result.dart';
import 'project_scoped_read_tool_contract.dart';

export 'project_scoped_read_tool_contract.dart';

// ChatNotifier decomposition collaborator: project-scoped-read-tool-handler

typedef ProjectScopedReadAuthorizer =
    Future<ProjectReadToolAuthorization> Function({
      required String toolName,
      required Map<String, dynamic> arguments,
      required String? projectRoot,
    });

/// Resolves and executes read-only tools for one exact immutable call.
final class ProjectScopedReadToolHandler {
  ProjectScopedReadToolHandler({
    required McpToolExecutionPort executionPort,
    required ProjectScopedReadLifecyclePort lifecyclePort,
    required Set<String> supportedToolNames,
    ProjectScopedReadAuthorizer? authorizeRead,
  }) : _executionPort = executionPort,
       _lifecyclePort = lifecyclePort,
       _authorizeRead =
           authorizeRead ?? const ProjectReadToolAuthorizer().authorize,
       supportedToolNames = Set<String>.unmodifiable(supportedToolNames) {
    for (final name in this.supportedToolNames) {
      requireCanonicalProjectScopedReadToolName(name);
    }
  }

  final McpToolExecutionPort _executionPort;
  final ProjectScopedReadLifecyclePort _lifecyclePort;
  final ProjectScopedReadAuthorizer _authorizeRead;
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
      return projectScopedReadExpiryResult(request);
    }

    var resolvedArguments = freezeProjectScopedReadArguments(
      ProjectScopedToolArgumentResolver.resolve(
        toolName: request.toolName,
        arguments: request.arguments,
        loadProjectRoot: () => request.ownerProjectRoot,
      ),
    );
    final authorization = await _authorizeRead(
      toolName: request.toolName,
      arguments: resolvedArguments,
      projectRoot: request.ownerProjectRoot,
    );
    if (!authorization.isAllowed) {
      return authorization.deniedResult!;
    }
    resolvedArguments = freezeProjectScopedReadArguments(
      authorization.arguments!,
    );
    if (!_lifecyclePort.isCurrent(request.identity)) {
      return projectScopedReadExpiryResult(request);
    }

    late final ProjectScopedReadCompletion completion;
    try {
      completion = await _executionPort.execute(
        request.identity,
        resolvedArguments,
      );
    } catch (_) {
      if (!_lifecyclePort.isCurrent(request.identity)) {
        return projectScopedReadExpiryResult(request);
      }
      rethrow;
    }
    if (completion.identity != request.identity ||
        completion.result.toolName != request.toolName ||
        !_lifecyclePort.isCurrent(request.identity)) {
      return projectScopedReadExpiryResult(request);
    }
    return completion.result;
  }
}
