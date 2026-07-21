import 'dart:io';

/// Resolves and screens the paths filesystem tools operate on.
///
/// Split out of `FilesystemTools` so that file reads, writes, searches, and
/// diffs are not interleaved with the rules for turning a model-supplied
/// string into an absolute path. Pure path logic with no tool semantics, which
/// also makes it testable without touching the filesystem tool surface.
abstract final class FilesystemPathResolver {
  static final RegExp _windowsDriveLetterPath = RegExp(r'^[A-Za-z]:[\\/]');

  /// Device files that read paths must never open: reading them blocks
  /// forever, returns unbounded data, or consumes another process's input.
  static const Set<String> blockedReadPaths = {
    '/dev/null',
    '/dev/random',
    '/dev/stdin',
    '/dev/stdout',
    '/dev/stderr',
    '/dev/urandom',
    '/dev/zero',
  };

  /// Resolves a caller-supplied path to an absolute one, or null when it
  /// cannot be resolved.
  ///
  /// A relative path needs [defaultRoot] to resolve against; without one the
  /// result would depend on the process working directory, which is not the
  /// caller's project.
  static String? resolve(String? rawPath, {String? defaultRoot}) {
    final trimmed = rawPath?.trim() ?? '';
    final normalizedDefaultRoot = defaultRoot?.trim();

    if (trimmed.isEmpty) {
      if (normalizedDefaultRoot == null || normalizedDefaultRoot.isEmpty) {
        return null;
      }
      return Directory(normalizedDefaultRoot).absolute.path;
    }

    final expandedPath = expandHomeRelativePath(trimmed);
    if (expandedPath == null) {
      return null;
    }

    if (isAbsolutePath(expandedPath)) {
      return File(expandedPath).absolute.path;
    }

    if (normalizedDefaultRoot == null || normalizedDefaultRoot.isEmpty) {
      return null;
    }

    return File.fromUri(
      Directory(normalizedDefaultRoot).uri.resolve(expandedPath),
    ).absolute.path;
  }

  /// Expands a leading `~`, or returns null when the home directory is
  /// unknown. Windows paths pass through: `~` is not a home shorthand there.
  static String? expandHomeRelativePath(String path) {
    if (Platform.isWindows || (path != '~' && !path.startsWith('~/'))) {
      return path;
    }

    final home = Platform.environment['HOME']?.trim();
    if (home == null || home.isEmpty) {
      return null;
    }

    if (path == '~') {
      return Directory(home).absolute.path;
    }

    return File.fromUri(
      Directory(home).uri.resolve(path.substring(2)),
    ).absolute.path;
  }

  static bool isBlockedReadPath(String path) {
    if (Platform.isWindows) return false;
    return blockedReadPaths.contains(path);
  }

  static bool isAbsolutePath(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\\') ||
        _windowsDriveLetterPath.hasMatch(path);
  }
}
