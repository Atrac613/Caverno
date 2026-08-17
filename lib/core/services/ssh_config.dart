import 'dart:io';

/// What `ssh(1)` would use for one host, read from the OpenSSH client config.
///
/// Only the parameters that decide how to reach an already-named host are
/// carried: the user to log in as, the port, and which keys to offer.
/// `HostName` is deliberately absent — it replaces *which* host is contacted,
/// and substituting a different destination behind an approval granted for the
/// named one is the thing the SSH approval guard exists to prevent.
final class SshConfigHostSettings {
  const SshConfigHostSettings({
    this.user,
    this.port,
    this.identityFiles = const [],
  });

  static const empty = SshConfigHostSettings();

  final String? user;
  final int? port;
  final List<String> identityFiles;

  bool get isEmpty => user == null && port == null && identityFiles.isEmpty;
}

/// Reads `~/.ssh/config` the way `ssh(1)` reads it, for a single host.
///
/// A host that "already connects without a password" almost always does so
/// because of this file: a `Host` block naming the user and an `IdentityFile`.
/// Offering the generic `~/.ssh/id_ed25519` instead is how a working
/// passwordless setup turns into "All authentication methods failed".
final class SshConfigReader {
  const SshConfigReader._();

  /// OpenSSH stops following includes well before this; the cap only stops a
  /// cycle from becoming an infinite read.
  static const _maxIncludeDepth = 8;

  /// Resolves the settings that apply to [host].
  ///
  /// [configPath] and [homeDirectory] exist so the search is testable;
  /// production callers omit both.
  static SshConfigHostSettings resolve(
    String host, {
    String? configPath,
    String? homeDirectory,
  }) {
    final home = homeDirectory ?? _homeDirectory();
    if (home == null) return SshConfigHostSettings.empty;
    final path = configPath ?? '$home${Platform.pathSeparator}.ssh'
        '${Platform.pathSeparator}config';
    final accumulator = _Accumulator(host: host, home: home);
    try {
      accumulator.readFile(File(path), depth: 0);
    } catch (_) {
      // An unreadable config simply contributes nothing; the dialog still
      // opens with whatever the caller already knew.
      return SshConfigHostSettings.empty;
    }
    return accumulator.settings;
  }

  static String? _homeDirectory() =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
}

/// Applies ssh_config's first-obtained-value-wins rule across `Host` blocks.
final class _Accumulator {
  _Accumulator({required this.host, required this.home});

  final String host;
  final String home;
  final Set<String> _visited = {};
  final List<String> _identityFiles = [];
  String? _user;
  int? _port;

  /// Whether the block being read applies to [host].
  ///
  /// A `Match` block is treated as not applying: its conditions can depend on
  /// the final user, the original host, or an external command, and applying a
  /// value that `ssh(1)` would not apply is worse than offering none.
  bool _applies = false;

  SshConfigHostSettings get settings => SshConfigHostSettings(
    user: _user,
    port: _port,
    identityFiles: List.unmodifiable(_identityFiles),
  );

  void readFile(File file, {required int depth}) {
    if (depth > SshConfigReader._maxIncludeDepth) return;
    final resolved = file.absolute.path;
    if (!_visited.add(resolved) || !file.existsSync()) return;
    for (final line in file.readAsLinesSync()) {
      _readLine(line, depth: depth);
    }
  }

  void _readLine(String line, {required int depth}) {
    final (keyword, value) = _split(line);
    if (keyword == null) return;
    switch (keyword) {
      case 'host':
        _applies = _matchesAnyPattern(value);
      case 'match':
        _applies = false;
      case 'include':
        // Includes are read wherever they appear, since the block they sit in
        // decides whether their contents apply.
        for (final path in _expandIncludes(value)) {
          readFile(File(path), depth: depth + 1);
        }
      case 'user' when _applies:
        _user ??= _values(value).firstOrNull;
      case 'port' when _applies:
        _port ??= int.tryParse(_values(value).firstOrNull ?? '');
      case 'identityfile' when _applies:
        _identityFiles.addAll(_values(value).map(_expandHome));
    }
  }

  /// Splits `keyword value` on whitespace or `=`, dropping comments.
  (String?, String) _split(String line) {
    final withoutComment = line.split('#').first.trim();
    if (withoutComment.isEmpty) return (null, '');
    final match = RegExp(r'^(\S+?)\s*(?:=|\s)\s*(.*)$').firstMatch(
      withoutComment,
    );
    if (match == null) return (null, '');
    return (match.group(1)!.toLowerCase(), match.group(2)!.trim());
  }

  /// Whitespace-separated values, honoring double quotes.
  List<String> _values(String raw) => RegExp(r'"([^"]*)"|(\S+)')
      .allMatches(raw)
      .map((m) => m.group(1) ?? m.group(2)!)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  bool _matchesAnyPattern(String raw) {
    var matched = false;
    for (final pattern in _values(raw)) {
      if (pattern.startsWith('!')) {
        if (_matches(pattern.substring(1))) return false;
      } else if (_matches(pattern)) {
        matched = true;
      }
    }
    return matched;
  }

  bool _matches(String pattern) {
    final expression = pattern.split('').map((char) {
      return switch (char) {
        '*' => '.*',
        '?' => '.',
        _ => RegExp.escape(char),
      };
    }).join();
    return RegExp('^$expression\$').hasMatch(host);
  }

  List<String> _expandIncludes(String raw) {
    final paths = <String>[];
    for (final value in _values(raw)) {
      final expanded = _expandHome(value);
      // A relative include resolves against ~/.ssh, per ssh_config(5).
      final absolute = expanded.startsWith(Platform.pathSeparator)
          ? expanded
          : '$home${Platform.pathSeparator}.ssh'
                '${Platform.pathSeparator}$expanded';
      paths.addAll(_expandGlob(absolute));
    }
    return paths;
  }

  List<String> _expandGlob(String path) {
    if (!path.contains('*') && !path.contains('?')) return [path];
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    if (index < 0) return const [];
    final directory = Directory(path.substring(0, index));
    if (!directory.existsSync()) return const [];
    final pattern = path.substring(index + 1);
    final expression = RegExp(
      '^${pattern.split('').map((c) => switch (c) {
        '*' => '[^$separator]*',
        '?' => '.',
        _ => RegExp.escape(c),
      }).join()}\$',
    );
    return directory
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .where((file) => expression.hasMatch(file.substring(index + 1)))
        .toList(growable: false)
      ..sort();
  }

  String _expandHome(String path) => path.startsWith('~/')
      ? '$home${Platform.pathSeparator}${path.substring(2)}'
      : path;
}
