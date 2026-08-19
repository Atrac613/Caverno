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

  /// Stands in for the project root. Not path-shaped, so the token lookbehind
  /// skips whatever follows it.
  static const String _rootSentinel = 'ROOT';

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

    // Blank the project root out of the text before looking for paths at all.
    // Every in-project path then reads as `ROOT/lib/main.dart`, whose `/lib`
    // the token lookbehind already skips, so an in-project target cannot
    // produce a token no matter how it was written. That is what the old
    // truncated-prefix rule was reaching for: the token regex stops at spaces,
    // and roots on this machine contain them (`3D Sea Qwen`), which once had
    // the scan report `/Users/.../Web/3D` -- a directory that does not exist.
    // Masking removes the case instead of classifying it afterwards.
    final masked = command.replaceAll(_rootBoundary(root), _rootSentinel);

    final outside = <String>[];
    void consider(String raw) {
      final token = _normalize(raw);
      if (token.isEmpty || outside.contains(token)) return;
      if (_isDeviceFile(token)) return;
      // A quoted path keeps its spaces; the raw pass re-finds its head and
      // stops at the first one. Dropping that head keeps a location that does
      // not exist out of the hints handed to the reviewer.
      if (outside.any((seen) => _isSpaceTruncatedPrefixOf(token, seen))) return;
      outside.add(token);
    }

    // Quoted contents first: a quote carries the shell's own boundaries and is
    // the only way an outside path containing spaces survives whole. Quote
    // types are scanned independently so an inner `'...'` inside a `"..."`
    // argument (or the reverse) is still seen.
    void collectQuoted(RegExp pattern) {
      for (final match in pattern.allMatches(masked)) {
        final content = match.group(1) ?? '';
        if (_looksLikeAbsolutePath(content)) consider(content);
      }
    }

    collectQuoted(_doubleQuoted);
    collectQuoted(_singleQuoted);

    // Then the raw text, quoted regions included. Blanking them out first
    // looked tidier and was the bug: `'([^']*)'` pairs the apostrophes in
    // `echo "it's"` and `echo "that's"`, and blanking that span erased an
    // unquoted `cat /etc/passwd` between them, so the scan returned nothing
    // and the command skipped approval. Scanning the raw text as well means a
    // token can only ever be added, never vanish.
    for (final match in _pathToken.allMatches(masked)) {
      consider(match.group(0)!);
    }
    return List<String>.unmodifiable(outside);
  }

  bool referencesOutsidePath({
    required String command,
    required String? projectRoot,
  }) => scan(command: command, projectRoot: projectRoot).isNotEmpty;

  /// Matches [root] only where it ends a path, so a sibling that merely starts
  /// with the same characters keeps its identity.
  ///
  /// Masking `/Users/dev/project` blindly would turn
  /// `/Users/dev/project-secrets/x` into `ROOT-secrets/x` and hide it, which
  /// is the class of bug this file keeps producing. The lookahead requires the
  /// next character to open a child path or leave the token entirely; `-`
  /// continues it, so that sibling is left alone.
  ///
  /// A `~` path is never masked and stays outside without being expanded:
  /// expansion would need the environment, and a home-relative path that lands
  /// inside the project is rare enough to be worth one approval prompt.
  RegExp _rootBoundary(String root) =>
      RegExp('${RegExp.escape(root)}(?=/|[^A-Za-z0-9._~-]|\$)');

  /// Whether [path] is [full] cut short at a space -- the head the token regex
  /// produces for any path containing one.
  bool _isSpaceTruncatedPrefixOf(String path, String full) {
    if (path.startsWith('~')) return false;
    if (path.length >= full.length) return false;
    if (!full.startsWith(path)) return false;
    return full[path.length] == ' ';
  }

  bool _isDeviceFile(String path) =>
      _deviceFiles.contains(path) || path.startsWith('/dev/fd/');

  bool _looksLikeAbsolutePath(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('/') || trimmed.startsWith('~/');
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
  /// Deliberately says only that the command *may* reach outside, and names no
  /// token: the tokens are why the ask fired, not a claim that those locations
  /// exist -- a regex that stopped at spaces once named a directory that did
  /// not. The command itself is the evidence, and the approval sheet already
  /// renders it in its own block; repeating it here duplicated the text and
  /// pushed an uncapped copy into the audit log's `rationale`, which is
  /// written verbatim while `arguments` is truncated at 240 characters.
  static ToolApprovalGateDecision? outsideProjectApproval(
    List<String> outOfRootPaths,
  ) => outOfRootPaths.isEmpty
      ? null
      : ToolApprovalGateDecision.manualApprovalRequired(
          title: 'This command may reach outside the project',
          rationale:
              'It may touch a path outside the open project. Nothing else '
              'checks these paths before the shell runs. Read the command '
              'below before approving.',
        );
}
