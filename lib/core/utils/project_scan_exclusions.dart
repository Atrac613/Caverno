import 'dart:io';

import 'package:path/path.dart' as p;

/// Subtrees a project-scoped scan must not descend into.
///
/// `search_files` and `find_files` walked everything under the project root,
/// and this repository keeps agent sandbox worktrees *inside* it: measured
/// 2026-09-17, `.claude/worktrees/` held 72 full checkouts, so the tree carried
/// **105** `pubspec.yaml` files. A model asking the ordinary question -- what
/// version is this project on -- got 100 `version:` matches from sibling
/// checkouts and could not tell which was the project it was working in.
/// Session a40d48a8 then fell back to `read_file pubspec.yaml` 20 times,
/// `load_skill` 33 times and `git status` 13 times in one session.
///
/// The exclusion applies while *descending*. A caller that roots its scan
/// inside one of these directories has already passed the check and still sees
/// everything, which is what keeps a worktree child readable by path.
abstract final class ProjectScanExclusions {
  /// Directory names skipped wherever they appear.
  ///
  /// Kept in step with `RepoMapService`, which prunes the same set for the
  /// same reason.
  static const Set<String> directoryNames = {
    '.dart_tool',
    '.fvm',
    '.git',
    '.idea',
    '.symlinks',
    '.vscode',
    'DerivedData',
    'Pods',
    'build',
    'node_modules',
  };

  /// Subtrees skipped only at these positions, relative to the scan root.
  ///
  /// Scoped rather than excluding `.claude` and `.codex` whole, because their
  /// other contents -- `settings.json`, `agents/`, `launch.json` -- are
  /// ordinary project files an agent is expected to find.
  static const Set<String> relativeDirectoryPaths = {
    '.claude/worktrees',
    '.codex/worktrees',
  };

  /// Whether a directory at [relativePath] below the scan root is excluded.
  static bool excludesDirectory(String relativePath) {
    final normalized = _normalize(relativePath);
    if (normalized.isEmpty) return false;
    if (relativeDirectoryPaths.contains(normalized)) return true;
    return directoryNames.contains(normalized.split('/').last);
  }

  /// Whether a file at [relativePath] below the scan root sits in an excluded
  /// subtree.
  ///
  /// For callers that already hold a flat listing and cannot prune.
  static bool excludesPath(String relativePath) {
    final normalized = _normalize(relativePath);
    if (normalized.isEmpty) return false;
    final segments = normalized.split('/');
    for (var end = 1; end < segments.length; end += 1) {
      if (excludesDirectory(segments.take(end).join('/'))) return true;
    }
    return false;
  }

  /// Streams the files under [root], pruning excluded subtrees instead of
  /// listing and then discarding them.
  ///
  /// Pruning rather than filtering is the point: 72 nested checkouts is a walk
  /// large enough that listing it is itself the cost.
  static Stream<File> files(
    Directory root, {
    bool recursive = true,
  }) async* {
    final rootPath = root.absolute.path;
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      final List<FileSystemEntity> entries;
      try {
        entries = await directory.list(followLinks: false).toList();
      } on FileSystemException {
        // An unreadable directory is skipped, exactly as the flat walk did.
        continue;
      }
      for (final entity in entries) {
        if (entity is File) {
          yield entity;
        } else if (entity is Directory && recursive) {
          final relative = p.relative(entity.absolute.path, from: rootPath);
          if (excludesDirectory(relative)) continue;
          pending.add(entity);
        }
      }
    }
  }

  static String _normalize(String path) =>
      path.replaceAll(r'\', '/').replaceAll(RegExp(r'^\./'), '').replaceAll(
        RegExp(r'/+$'),
        '',
      );
}
