import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/dart_project_tooling.dart';

enum ProjectMutationPathDenial {
  projectRootRequired('project_mutation_root_required'),
  traversalNotAllowed('project_mutation_traversal_not_allowed'),
  pathUnavailable('project_mutation_path_unavailable'),
  outsideProject('project_mutation_outside_root');

  const ProjectMutationPathDenial(this.code);

  final String code;
}

final class ProjectMutationPathAuthorization {
  const ProjectMutationPathAuthorization._({
    this.canonicalRoot,
    this.canonicalPath,
    this.denial,
    this.deniedResult,
  });

  factory ProjectMutationPathAuthorization.allowed({
    required String canonicalRoot,
    required String canonicalPath,
  }) => ProjectMutationPathAuthorization._(
    canonicalRoot: canonicalRoot,
    canonicalPath: canonicalPath,
  );

  factory ProjectMutationPathAuthorization.denied(
    ProjectMutationPathDenial denial, {
    required String toolName,
    String? canonicalRoot,
    String? rawPath,
  }) {
    final path = rawPath?.trim() ?? '';
    final message = _denialMessage(denial, canonicalRoot);
    return ProjectMutationPathAuthorization._(
      denial: denial,
      canonicalRoot: canonicalRoot,
      deniedResult: McpToolResult(
        toolName: toolName,
        result: jsonEncode({
          'ok': false,
          'code': denial.code,
          'error': message,
          if (canonicalRoot != null && canonicalRoot.isNotEmpty)
            'project_root': canonicalRoot,
          if (path.isNotEmpty) 'path': path,
        }),
        isSuccess: false,
        errorMessage: message,
      ),
    );
  }

  final String? canonicalRoot;
  final String? canonicalPath;
  final ProjectMutationPathDenial? denial;
  final McpToolResult? deniedResult;

  bool get isAllowed => denial == null;
}

typedef FileMutationPathAuthorizer =
    Future<ProjectMutationPathAuthorization> Function({
      required String toolName,
      required String? projectRoot,
      required String rawPath,
    });

/// Authorizes one mutation target against a canonical project root.
final class ProjectMutationPathFence {
  const ProjectMutationPathFence();

  static Future<ProjectMutationPathAuthorization> authorizeCall({
    required String toolName,
    required String? projectRoot,
    required String rawPath,
  }) {
    return const ProjectMutationPathFence().authorize(
      toolName: toolName,
      projectRoot: projectRoot,
      rawPath: rawPath,
    );
  }

  Future<ProjectMutationPathAuthorization> authorize({
    required String toolName,
    required String? projectRoot,
    required String rawPath,
  }) async {
    final root = projectRoot?.trim() ?? '';
    if (root.isEmpty) {
      return ProjectMutationPathAuthorization.denied(
        ProjectMutationPathDenial.projectRootRequired,
        toolName: toolName,
      );
    }

    final path = rawPath.trim();
    if (path.isEmpty ||
        _isHomeRelative(path) ||
        _containsParentTraversal(path)) {
      return ProjectMutationPathAuthorization.denied(
        path.isEmpty
            ? ProjectMutationPathDenial.outsideProject
            : ProjectMutationPathDenial.traversalNotAllowed,
        toolName: toolName,
        canonicalRoot: root,
        rawPath: path,
      );
    }

    try {
      final canonicalRoot = await Directory(root).resolveSymbolicLinks();
      final candidate = DartProjectPath.isAbsolutePath(path)
          ? path
          : File.fromUri(Directory(canonicalRoot).uri.resolve(path)).path;
      final canonicalPath = await _resolveMutationTarget(candidate);
      if (!DartProjectPath.isInsideRoot(canonicalPath, canonicalRoot)) {
        return ProjectMutationPathAuthorization.denied(
          ProjectMutationPathDenial.outsideProject,
          toolName: toolName,
          canonicalRoot: canonicalRoot,
          rawPath: path,
        );
      }
      return ProjectMutationPathAuthorization.allowed(
        canonicalRoot: canonicalRoot,
        canonicalPath: canonicalPath,
      );
    } on FileSystemException {
      return ProjectMutationPathAuthorization.denied(
        ProjectMutationPathDenial.pathUnavailable,
        toolName: toolName,
        canonicalRoot: root,
        rawPath: path,
      );
    }
  }

  Future<String> _resolveMutationTarget(String candidate) async {
    final existing = await _nearestExistingPath(candidate);
    final resolvedExisting = await _resolveExistingPath(existing.path);
    var joined = resolvedExisting;
    for (final segment in existing.remaining.reversed) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      joined = p.join(joined, segment);
    }
    return joined;
  }

  Future<({String path, List<String> remaining})> _nearestExistingPath(
    String candidate,
  ) async {
    var current = candidate;
    final remaining = <String>[];
    while (true) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        return (path: current, remaining: remaining);
      }
      final parent = File(current).parent.path;
      if (parent == current) {
        throw const FileSystemException('Mutation target is unavailable.');
      }
      remaining.add(p.basename(current));
      current = parent;
    }
  }

  Future<String> _resolveExistingPath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    return switch (type) {
      FileSystemEntityType.directory => Directory(path).resolveSymbolicLinks(),
      FileSystemEntityType.file => File(path).resolveSymbolicLinks(),
      FileSystemEntityType.link => Link(path).resolveSymbolicLinks(),
      _ => throw const FileSystemException('Mutation target is unavailable.'),
    };
  }

  bool _isHomeRelative(String path) =>
      path == '~' || path.startsWith('~/') || path.startsWith(r'~\');

  bool _containsParentTraversal(String path) =>
      path.split(RegExp(r'[/\\]+')).any((component) => component == '..');
}

String _denialMessage(ProjectMutationPathDenial denial, String? projectRoot) {
  final root = projectRoot?.trim() ?? '';
  final rootClause = root.isEmpty
      ? ''
      : ' The authorized project root is $root.';
  return switch (denial) {
    ProjectMutationPathDenial.projectRootRequired =>
      'No coding project is selected, so local file mutations are unavailable. '
          'Ask the user to open a project before writing, editing, or deleting '
          'local files.',
    ProjectMutationPathDenial.traversalNotAllowed =>
      'The path uses "~" or "..", which local mutation tools do not accept.'
          '$rootClause Retry with an absolute path, or one relative to that root.',
    ProjectMutationPathDenial.pathUnavailable =>
      'The mutation target cannot be resolved from an existing parent path.',
    ProjectMutationPathDenial.outsideProject =>
      'The mutation target is outside the authorized project root.'
          '$rootClause',
  };
}
