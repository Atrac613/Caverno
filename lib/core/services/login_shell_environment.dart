import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/logger.dart';

/// Resolves and caches the user's *login-shell* environment so that
/// child processes (stdio MCP servers, `git`, shell tool commands, ...) can
/// find binaries by name (`dart`, `npx`, `uvx`, Homebrew tools, ...).
///
/// ### Why this exists
/// GUI-launched apps on macOS (and Linux desktops launched from a file
/// manager) only inherit launchd's minimal PATH — typically
/// `/usr/bin:/bin:/usr/sbin:/sbin`. Tools installed via FVM, asdf, Homebrew,
/// or `~/.zshrc` edits are absent, so `Process.start('dart', ...)` fails with
/// "No such file or directory" even though `dart` works fine in the user's
/// terminal.
///
/// Spawning the user's login shell (`$SHELL -ilc env`) evaluates their profile
/// files and reports the PATH they actually see in a terminal. We capture it
/// once at startup, cache it, and merge it into every child-process
/// environment.
class LoginShellEnvironment {
  LoginShellEnvironment._();

  /// Shared singleton. Resolution is performed lazily and at most once.
  static final LoginShellEnvironment instance = LoginShellEnvironment._();

  /// Marker wrapped around the captured environment so noisy interactive
  /// profile scripts (banners, `echo`, fastfetch, ...) can't corrupt parsing.
  static const _beginMarker = '__CAVERNO_ENV_BEGIN__';
  static const _endMarker = '__CAVERNO_ENV_END__';

  static const _resolveTimeout = Duration(seconds: 5);

  /// The resolved login PATH, or `null` if resolution has not completed or is
  /// unavailable on this platform.
  String? _loginPath;

  /// In-flight / completed resolution. Guarantees the login shell is spawned
  /// at most once even under concurrent callers.
  Future<void>? _resolution;

  /// Whether a login PATH was successfully captured.
  bool get isResolved => _loginPath != null;

  /// Kick off (or await an in-flight) resolution. Idempotent and safe to call
  /// from `main()` as fire-and-forget; call sites that launch processes should
  /// `await` it to guarantee the PATH is ready.
  Future<void> ensureResolved() {
    return _resolution ??= _resolve();
  }

  /// Build a child-process environment with the login PATH merged in.
  ///
  /// Resolves the login shell on first use, then returns
  /// `{...Platform.environment, ...?extra}` with `PATH` augmented by any
  /// directories from the login shell that the current process is missing.
  /// `extra` wins over both (callers may still override PATH explicitly).
  Future<Map<String, String>> environment({
    Map<String, String>? extra,
  }) async {
    await ensureResolved();

    final merged = <String, String>{...Platform.environment, ...?extra};

    // Respect an explicit PATH override from the caller.
    final callerOverridesPath = extra?.keys.any((k) => k == 'PATH') ?? false;
    final loginPath = _loginPath;
    if (loginPath != null && loginPath.isNotEmpty && !callerOverridesPath) {
      merged['PATH'] = _mergePath(merged['PATH'], loginPath);
    }

    return merged;
  }

  /// Merge `current` and `login` PATH strings, preserving order and dropping
  /// duplicates. The current-process entries come first so OS-provided paths
  /// keep priority, with login-only directories appended.
  String _mergePath(String? current, String login) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final segment in [
      ...?current?.split(':'),
      ...login.split(':'),
    ]) {
      if (segment.isEmpty || !seen.add(segment)) continue;
      ordered.add(segment);
    }
    return ordered.join(':');
  }

  Future<void> _resolve() async {
    // Windows GUI apps already inherit the user PATH from the registry; only
    // macOS/Linux suffer the minimal-PATH problem.
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    try {
      final path = await _capturePath(shell);
      if (path != null && path.isNotEmpty) {
        _loginPath = path;
        appLog('[LoginShellEnvironment] Resolved login PATH via $shell');
      } else {
        appLog('[LoginShellEnvironment] Login PATH empty; using process PATH');
      }
    } catch (error) {
      appLog('[LoginShellEnvironment] Failed to resolve login PATH: $error');
    }
  }

  /// Run the login shell and capture the `PATH` it exports.
  ///
  /// Uses `env` (a standalone binary) rather than `echo $PATH` so the output is
  /// shell-agnostic: even non-POSIX shells like `fish` export a colon-joined
  /// `PATH` to child processes, and `env`'s `KEY=value` format is identical
  /// everywhere. Markers delimit the payload so profile-script noise is
  /// discarded.
  Future<String?> _capturePath(String shell) async {
    final script =
        'printf "%s\\n" "$_beginMarker"; env; printf "%s\\n" "$_endMarker"';

    // `-i` (interactive) is required because many users set PATH in ~/.zshrc,
    // which non-interactive shells skip. `-l` loads login profiles.
    final process = await Process.start(shell, ['-ilc', script]);

    // Close stdin so an interactive shell doesn't block waiting for input.
    unawaited(process.stdin.close().catchError((_) {}));

    final stdoutFuture =
        process.stdout.transform(utf8.decoder).join();
    // Drain stderr to avoid back-pressure deadlocks; ignore its contents.
    unawaited(process.stderr.drain<void>().catchError((_) {}));

    final String output;
    try {
      output = await stdoutFuture.timeout(_resolveTimeout);
    } on TimeoutException {
      process.kill();
      rethrow;
    }
    await process.exitCode.timeout(_resolveTimeout, onTimeout: () {
      process.kill();
      return -1;
    });

    return _extractPath(output);
  }

  /// Pull the `PATH=` value out of the marker-delimited `env` dump.
  String? _extractPath(String output) {
    final begin = output.indexOf(_beginMarker);
    final end = output.indexOf(_endMarker);
    final block = (begin >= 0 && end > begin)
        ? output.substring(begin + _beginMarker.length, end)
        : output;

    String? path;
    // A later definition wins, mirroring shell export semantics.
    for (final line in const LineSplitter().convert(block)) {
      if (line.startsWith('PATH=')) {
        path = line.substring('PATH='.length);
      }
    }
    return path?.trim();
  }
}
