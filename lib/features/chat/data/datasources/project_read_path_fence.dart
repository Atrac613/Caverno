import 'dart:io';

import '../../domain/services/dart_project_tooling.dart';

enum ProjectReadPathDenial {
  projectRootRequired('project_read_root_required'),
  traversalNotAllowed('project_read_traversal_not_allowed'),
  pathUnavailable('project_read_path_unavailable'),
  outsideProject('project_read_outside_root');

  const ProjectReadPathDenial(this.code);

  final String code;
}

final class ProjectReadPathAuthorization {
  const ProjectReadPathAuthorization._({
    this.canonicalRoot,
    this.canonicalPath,
    this.denial,
  });

  factory ProjectReadPathAuthorization.allowed({
    required String canonicalRoot,
    required String canonicalPath,
  }) => ProjectReadPathAuthorization._(
    canonicalRoot: canonicalRoot,
    canonicalPath: canonicalPath,
  );

  /// A denial carries [canonicalRoot] whenever the root is known.
  ///
  /// A refusal that does not name the boundary cannot be complied with: in
  /// session 12b739d6 the caller was told only that its target was "outside
  /// the authorized project", could not tell whether the path form or the tool
  /// was at fault, and spent four `tool_search` calls hunting for a way in.
  /// The root is the one fact that makes the refusal actionable, so it travels
  /// with the denial. It is canonical when it could be resolved, and the
  /// configured value otherwise.
  factory ProjectReadPathAuthorization.denied(
    ProjectReadPathDenial denial, {
    String? canonicalRoot,
    String? canonicalPath,
  }) => ProjectReadPathAuthorization._(
    denial: denial,
    canonicalRoot: canonicalRoot,
    canonicalPath: canonicalPath,
  );

  final String? canonicalRoot;
  final String? canonicalPath;
  final ProjectReadPathDenial? denial;

  bool get isAllowed => denial == null;
}

/// Authorizes one existing local read target against a canonical project root.
final class ProjectReadPathFence {
  const ProjectReadPathFence();

  Future<ProjectReadPathAuthorization> authorize({
    required String? projectRoot,
    required String rawPath,
    String? baseDirectory,
  }) async {
    final root = projectRoot?.trim() ?? '';
    if (root.isEmpty) {
      return ProjectReadPathAuthorization.denied(
        ProjectReadPathDenial.projectRootRequired,
      );
    }

    final path = rawPath.trim();
    if (_isHomeRelative(path) || _containsParentTraversal(path)) {
      return ProjectReadPathAuthorization.denied(
        ProjectReadPathDenial.traversalNotAllowed,
        canonicalRoot: root,
      );
    }

    try {
      final canonicalRoot = await Directory(root).resolveSymbolicLinks();
      final canonicalBase = baseDirectory == null
          ? canonicalRoot
          : await Directory(baseDirectory).resolveSymbolicLinks();
      if (!DartProjectPath.isInsideRoot(canonicalBase, canonicalRoot)) {
        return ProjectReadPathAuthorization.denied(
          ProjectReadPathDenial.outsideProject,
          canonicalRoot: canonicalRoot,
        );
      }
      final candidate = DartProjectPath.isAbsolutePath(path)
          ? path
          : File.fromUri(Directory(canonicalBase).uri.resolve(path)).path;
      final canonicalPath = await _resolveExistingPath(candidate);
      if (!DartProjectPath.isInsideRoot(canonicalPath, canonicalRoot)) {
        // Report the resolved target, not the requested one: an approval has
        // to name the file that would actually be read, or a symlink could be
        // repointed between the prompt and the read.
        return ProjectReadPathAuthorization.denied(
          ProjectReadPathDenial.outsideProject,
          canonicalRoot: canonicalRoot,
          canonicalPath: canonicalPath,
        );
      }
      return ProjectReadPathAuthorization.allowed(
        canonicalRoot: canonicalRoot,
        canonicalPath: canonicalPath,
      );
    } on FileSystemException {
      return ProjectReadPathAuthorization.denied(
        ProjectReadPathDenial.pathUnavailable,
        canonicalRoot: root,
      );
    }
  }

  bool _isHomeRelative(String path) =>
      path == '~' || path.startsWith('~/') || path.startsWith(r'~\');

  bool _containsParentTraversal(String path) =>
      path.split(RegExp(r'[/\\]+')).any((component) => component == '..');

  Future<String> _resolveExistingPath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    return switch (type) {
      FileSystemEntityType.directory => Directory(path).resolveSymbolicLinks(),
      FileSystemEntityType.file => File(path).resolveSymbolicLinks(),
      FileSystemEntityType.link => Link(path).resolveSymbolicLinks(),
      _ => throw FileSystemException('Read target is unavailable.'),
    };
  }
}
