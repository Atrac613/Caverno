import 'dart:io';

/// Runs a `git` invocation in the project and returns its stdout.
typedef GitCommandRunner = Future<String> Function(List<String> args);

/// Reports the files a Best-of-N candidate changed by reading
/// `git status --porcelain`. Git is the authoritative source of truth: it
/// catches every edit regardless of which tool made it, which is what
/// verification needs to know what to test.
class GitChangedPathsService {
  GitChangedPathsService({required this.projectRoot, GitCommandRunner? runner})
    : _runner = runner ?? _defaultRunner(projectRoot);

  final String projectRoot;
  final GitCommandRunner _runner;

  /// Returns the project-relative paths that differ from HEAD (staged,
  /// unstaged, or untracked). Returns an empty list when git is unavailable so
  /// a non-git project degrades gracefully.
  Future<List<String>> changedPaths() async {
    try {
      final output = await _runner(const ['status', '--porcelain']);
      return parsePorcelain(output);
    } on Object {
      return const [];
    }
  }

  /// Parses `git status --porcelain` (v1) output into a list of paths. The
  /// first two columns are the status code, the path starts at column 3, and a
  /// rename is reported as `old -> new` (the new path is kept). Quoted paths
  /// (those with special characters) are unquoted.
  static List<String> parsePorcelain(String output) {
    final paths = <String>[];
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;
      final body = line.length > 3 ? line.substring(3).trim() : line.trim();
      if (body.isEmpty) continue;
      final path = body.contains(' -> ') ? body.split(' -> ').last : body;
      final normalized = _unquote(path.trim());
      if (normalized.isNotEmpty) paths.add(normalized);
    }
    return paths;
  }

  static String _unquote(String path) {
    if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
      return path.substring(1, path.length - 1);
    }
    return path;
  }

  static GitCommandRunner _defaultRunner(String projectRoot) {
    return (args) async {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: projectRoot,
      );
      return '${result.stdout}';
    };
  }
}
