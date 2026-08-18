import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// Absolute path tokens a shell command names that look to fall outside the
/// open project.
///
/// The project read fence only inspects paths for the handful of commands
/// Caverno runs internally (`cat`, `ls`, `head`, ...), and only when the
/// command carries no shell syntax. Anything else -- a `python3` heredoc, an
/// `awk` script, a piped `jq` -- reaches the real shell with no path check at
/// all. Session db878d3a read a file under `~/.caverno` that way seconds after
/// the same file went through the fence's approval prompt, so the narrow
/// tool-level gate and the unbounded shell sat side by side.
///
/// Closing that by parsing arbitrary shell is not on offer. This answers a
/// cheaper question: does the command *mention* an absolute path that is not
/// inside the project? A yes is a trigger, not proof the command reads that
/// path, and the prompt must show the command rather than assert the tokens:
/// a regex that stops at spaces once named a directory that did not exist.
final class OutOfRootCommandPaths {
  const OutOfRootCommandPaths();

  /// Matches an unquoted absolute or home-relative path token.
  ///
  /// The lookbehind keeps it off word-internal slashes (`and/or`) and off URL
  /// separators: in `https://host/x` the first slash follows `:` and the
  /// second follows `/`, so neither starts a match. Spaces are not part of
  /// the token; quoted strings are collected first, because they carry the
  /// shell's own path boundaries.
  static final RegExp _pathToken = RegExp(
    r'(?<![\w.:/\\])~?/[A-Za-z0-9._~\-]+(?:/[A-Za-z0-9._~\-]+)*',
  );

  static final RegExp _doubleQuoted = RegExp(r'"([^"]*)"');
  static final RegExp _singleQuoted = RegExp(r"'([^']*)'");

  static const Set<String> _deviceFiles = {
    '/dev/null',
    '/dev/zero',
    '/dev/random',
    '/dev/urandom',
    '/dev/stdin',
    '/dev/stdout',
    '/dev/stderr',
    '/dev/tty',
    '/dev/console',
  };

  /// Path tokens in [command] that fall outside [projectRoot], in order of
  /// appearance and without duplicates.
  ///
  /// Returns empty when [projectRoot] is missing: with no boundary to compare
  /// against there is nothing this can honestly report, and the caller's own
  /// missing-root handling is the right place to refuse.
  List<String> scan({required String command, required String? projectRoot}) {
    final root = _normalize(projectRoot ?? '');
    if (root.isEmpty) return const [];

    final outside = <String>[];
    void consider(String raw) {
      final token = _normalize(raw);
      if (token.isEmpty || outside.contains(token)) return;
      if (_isDeviceFile(token)) return;
      if (_isInside(token, root)) return;
      if (_isTruncatedRootPrefix(token, root)) return;
      outside.add(token);
    }

    final quotedSpans = <({int start, int end})>[];
    void collectQuoted(RegExp pattern) {
      for (final match in pattern.allMatches(command)) {
        quotedSpans.add((start: match.start, end: match.end));
        final content = match.group(1) ?? '';
        if (_looksLikeAbsolutePath(content)) consider(content);
      }
    }

    // Quote types are scanned independently so an inner `'...'` inside a
    // `"..."` argument (or the reverse) is still a path, not swallowed by the
    // outer span.
    collectQuoted(_doubleQuoted);
    collectQuoted(_singleQuoted);

    final unquoted = _blankQuotedRegions(command, quotedSpans);
    for (final match in _pathToken.allMatches(unquoted)) {
      consider(match.group(0)!);
    }
    return List<String>.unmodifiable(outside);
  }

  bool referencesOutsidePath({
    required String command,
    required String? projectRoot,
  }) => scan(command: command, projectRoot: projectRoot).isNotEmpty;

  /// A `~` path is treated as outside without expanding it.
  ///
  /// Expansion would need the environment, and a home-relative path that
  /// happens to land inside the project is rare enough that paying for it with
  /// one approval prompt is the better trade.
  bool _isInside(String path, String root) {
    if (path.startsWith('~')) return false;
    return path == root || path.startsWith('$root/');
  }

  /// A token that is a prefix of [root] at a non-separator is a truncated
  /// in-project path, not evidence of an outside one.
  ///
  /// `/Users/.../Web/3D` is a prefix of `/Users/.../Web/3D Sea Qwen` because
  /// the unquoted token regex stops at spaces. A parent directory
  /// (`/Users/dev` vs `/Users/dev/project`) continues at `/` and stays
  /// outside.
  bool _isTruncatedRootPrefix(String path, String root) {
    if (path.startsWith('~')) return false;
    if (path.length >= root.length) return false;
    if (!root.startsWith(path)) return false;
    return root[path.length] != '/';
  }

  bool _isDeviceFile(String path) =>
      _deviceFiles.contains(path) || path.startsWith('/dev/fd/');

  bool _looksLikeAbsolutePath(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('/') || trimmed.startsWith('~/');
  }

  String _blankQuotedRegions(
    String command,
    List<({int start, int end})> spans,
  ) {
    if (spans.isEmpty) return command;
    final marked = List<bool>.filled(command.length, false);
    for (final span in spans) {
      final end = span.end < command.length ? span.end : command.length;
      for (var i = span.start; i < end; i++) {
        marked[i] = true;
      }
    }
    final buffer = StringBuffer();
    for (var i = 0; i < command.length; i++) {
      buffer.write(marked[i] ? ' ' : command[i]);
    }
    return buffer.toString();
  }

  String _normalize(String value) {
    var trimmed = value.trim();
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}

/// Whether one local command has to be decided by a person.
///
/// Pairs the boundary scan with the existing command-shape rules so callers
/// ask once. A command that names a path outside the project earns explicit
/// approval on that ground alone: the shell fence inspects paths only for the
/// handful of commands Caverno runs internally, so this is the last point at
/// which anyone looks at the path at all.
final class LocalCommandApprovalScope {
  const LocalCommandApprovalScope._({
    required this.outOfRootPaths,
    required this.requiresExplicitApproval,
  });

  factory LocalCommandApprovalScope.of({
    required String command,
    required String? projectRoot,
    required bool Function(String command) commandShapeRequiresApproval,
  }) {
    final paths = const OutOfRootCommandPaths().scan(
      command: command,
      projectRoot: projectRoot,
    );
    return LocalCommandApprovalScope._(
      outOfRootPaths: paths,
      requiresExplicitApproval:
          paths.isNotEmpty || commandShapeRequiresApproval(command),
    );
  }

  final List<String> outOfRootPaths;
  final bool requiresExplicitApproval;

  /// The approval a person must give when [outOfRootPaths] is non-empty, or
  /// null when the command stays inside the project.
  ///
  /// The prompt shows [command], not the extracted tokens. Those tokens are
  /// why the ask fired; they are not a claim that those locations exist.
  /// Recording the reason only in the audit file leaves the reader deciding
  /// blind, which is how a prompt becomes a reflex.
  static ToolApprovalGateDecision? outsideProjectApproval(
    List<String> outOfRootPaths,
    String command,
  ) => outOfRootPaths.isEmpty
      ? null
      : ToolApprovalGateDecision.manualApprovalRequired(
          title: 'This command may reach outside the project',
          rationale:
              'It may touch a path outside the open project. Nothing else '
              'checks these paths before the shell runs.\n\n$command',
        );
}
