import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'project_read_path_fence.dart';
import 'project_scoped_read_runtime_contract.dart';

final class ProjectReadToolAuthorization {
  const ProjectReadToolAuthorization._({this.arguments, this.deniedResult});

  factory ProjectReadToolAuthorization.allowed(
    Map<String, dynamic> arguments,
  ) => ProjectReadToolAuthorization._(
    arguments: Map<String, dynamic>.unmodifiable(arguments),
  );

  factory ProjectReadToolAuthorization.denied(McpToolResult result) =>
      ProjectReadToolAuthorization._(deniedResult: result);

  final Map<String, dynamic>? arguments;
  final McpToolResult? deniedResult;

  bool get isAllowed => deniedResult == null;
}

/// Applies the shared canonical path fence to built-in project read tools.
final class ProjectReadToolAuthorizer {
  const ProjectReadToolAuthorizer({
    ProjectReadPathFence pathFence = const ProjectReadPathFence(),
  }) : _pathFence = pathFence;

  final ProjectReadPathFence _pathFence;

  Future<ProjectReadToolAuthorization> authorize({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String? projectRoot,
  }) async {
    if (!projectScopedLocalReadToolNames.contains(toolName)) {
      return ProjectReadToolAuthorization.allowed(arguments);
    }
    final rawPath = (arguments['path'] as String?)?.trim() ?? '';
    final authorization = await _pathFence.authorize(
      projectRoot: projectRoot,
      rawPath: rawPath,
    );
    if (!authorization.isAllowed) {
      final denial = authorization.denial!;
      const message = 'The read target is outside the authorized project.';
      return ProjectReadToolAuthorization.denied(
        McpToolResult(
          toolName: toolName,
          result: jsonEncode({
            'ok': false,
            'code': denial.code,
            'error': message,
          }),
          isSuccess: false,
          errorMessage: message,
        ),
      );
    }
    return ProjectReadToolAuthorization.allowed({
      ...arguments,
      'path': authorization.canonicalPath!,
    });
  }
}
