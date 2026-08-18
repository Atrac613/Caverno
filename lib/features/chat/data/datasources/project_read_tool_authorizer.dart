import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'project_read_path_fence.dart';
import 'project_scoped_read_runtime_contract.dart';

final class ProjectReadToolAuthorization {
  const ProjectReadToolAuthorization._({
    this.arguments,
    this.deniedResult,
    this.denial,
    this.canonicalPath,
  });

  factory ProjectReadToolAuthorization.allowed(
    Map<String, dynamic> arguments,
  ) => ProjectReadToolAuthorization._(
    arguments: Map<String, dynamic>.unmodifiable(arguments),
  );

  factory ProjectReadToolAuthorization.denied(
    McpToolResult result, {
    ProjectReadPathDenial? denial,
    String? canonicalPath,
  }) => ProjectReadToolAuthorization._(
    deniedResult: result,
    denial: denial,
    canonicalPath: canonicalPath,
  );

  final Map<String, dynamic>? arguments;
  final McpToolResult? deniedResult;

  /// Why the read was refused, so a caller can tell an approvable refusal from
  /// a hopeless one. Only [ProjectReadPathDenial.outsideProject] is a decision
  /// a person can overrule; a missing file or a traversal path is not.
  final ProjectReadPathDenial? denial;

  /// The resolved target of an out-of-root denial: what an approval would
  /// actually release, and the identity any grant is keyed on.
  final String? canonicalPath;

  bool get isAllowed => deniedResult == null;

  /// Whether a person could authorize this specific read.
  bool get isApprovable =>
      denial == ProjectReadPathDenial.outsideProject &&
      (canonicalPath?.isNotEmpty ?? false);
}

/// Applies the shared canonical path fence to built-in project read tools.
final class ProjectReadToolAuthorizer {
  const ProjectReadToolAuthorizer({
    ProjectReadPathFence pathFence = const ProjectReadPathFence(),
  }) : _pathFence = pathFence;

  final ProjectReadPathFence _pathFence;

  /// Authorizes one read.
  ///
  /// [approvedOutsideRootPaths] holds canonical paths a person has explicitly
  /// authorized for this conversation. A grant is per resolved file, never a
  /// directory or a prefix, so approving one log does not open the folder it
  /// sits in. Callers that have no way to ask a person -- routines, worktree
  /// agents, participant turns -- simply pass nothing and keep the fence
  /// absolute.
  Future<ProjectReadToolAuthorization> authorize({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String? projectRoot,
    Set<String> approvedOutsideRootPaths = const {},
  }) async {
    if (!projectScopedLocalReadToolNames.contains(toolName)) {
      return ProjectReadToolAuthorization.allowed(arguments);
    }
    final rawPath = (arguments['path'] as String?)?.trim() ?? '';
    final authorization = await _pathFence.authorize(
      projectRoot: projectRoot,
      rawPath: rawPath,
    );
    final resolvedPath = authorization.canonicalPath;
    if (authorization.denial == ProjectReadPathDenial.outsideProject &&
        resolvedPath != null &&
        approvedOutsideRootPaths.contains(resolvedPath)) {
      return ProjectReadToolAuthorization.allowed({
        ...arguments,
        'path': resolvedPath,
      });
    }
    if (!authorization.isAllowed) {
      final denial = authorization.denial!;
      final message = denialMessage(denial, authorization.canonicalRoot);
      return ProjectReadToolAuthorization.denied(
        McpToolResult(
          toolName: toolName,
          result: jsonEncode({
            'ok': false,
            'code': denial.code,
            'error': message,
            if (authorization.canonicalRoot case final root?
                when root.isNotEmpty)
              'project_root': root,
          }),
          isSuccess: false,
          errorMessage: message,
        ),
        denial: denial,
        canonicalPath: authorization.canonicalPath,
      );
    }
    return ProjectReadToolAuthorization.allowed({
      ...arguments,
      'path': authorization.canonicalPath!,
    });
  }

  /// The human-readable reason for [denial], naming [projectRoot] when known.
  ///
  /// One hardcoded sentence used to serve all four denial codes, which made
  /// the message wrong for three of them: a file that does not exist reported
  /// as "outside the authorized project", and a session with no project open
  /// reported the same. Worse, none of the wordings said where the boundary
  /// was or what to do about it, so the caller could only guess -- session
  /// 12b739d6 burned eight LLM calls and 122k tokens guessing, cycling
  /// `tool_search` for an escape hatch that does not exist. A refusal has to
  /// carry the next action, not just the verdict.
  static String denialMessage(
    ProjectReadPathDenial denial,
    String? projectRoot,
  ) {
    final root = projectRoot?.trim() ?? '';
    final rootClause = root.isEmpty
        ? ''
        : ' The authorized project root is $root.';
    return switch (denial) {
      ProjectReadPathDenial.projectRootRequired =>
        'No coding project is selected, so local file reads are unavailable. '
            'Ask the user to open a project before reading local files.',
      ProjectReadPathDenial.traversalNotAllowed =>
        'The path uses "~" or "..", which local read tools do not accept.'
            '$rootClause '
            'Retry with an absolute path, or one relative to that root.',
      ProjectReadPathDenial.pathUnavailable =>
        'The read target does not exist or cannot be opened. This is not an '
            'authorization problem, so retrying with a different read tool '
            'will not help: check the path with the user.',
      ProjectReadPathDenial.outsideProject =>
        'The read target is outside the authorized project root, and every '
            'local read tool is bound to that same root -- no other tool can '
            'reach it, so do not search for one.'
            '$rootClause '
            'Report the path as unreadable and ask the user to paste the '
            'contents or copy the file into the project.',
    };
  }
}
