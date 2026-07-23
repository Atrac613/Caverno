import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../utils/logger.dart';
import 'login_shell_environment.dart';

/// Singleton service backing the coding workspace's bottom terminal panel.
///
/// It owns one long-lived login shell running in a pseudo-terminal plus the
/// [Terminal] screen buffer that renders it. The service outlives the panel
/// widget on purpose: closing the panel only hides the view, so a `flutter
/// run` or a long build keeps going and its scrollback is still there when the
/// user re-opens it.
///
/// Desktop only. Mobile has no fork/exec (iOS) or a shell worth attaching to,
/// and the coding workspace there is remote anyway.
final codingTerminalServiceProvider = Provider<CodingTerminalService>((ref) {
  final service = CodingTerminalService();
  ref.onDispose(service.dispose);
  return service;
});

class CodingTerminalService extends ChangeNotifier {
  CodingTerminalService();

  /// Scrollback kept in memory. Roughly matches what a terminal emulator
  /// keeps by default; long builds stay reviewable without unbounded growth.
  static const int _maxScrollbackLines = 10000;

  /// Platforms where [Pty] can spawn a shell.
  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  final Terminal terminal = Terminal(maxLines: _maxScrollbackLines);
  final TerminalController terminalController = TerminalController();

  Pty? _pty;
  StreamSubscription<List<int>>? _outputSubscription;
  Future<void>? _startup;
  String? _workingDirectory;
  String? _targetDirectory;
  int _generation = 0;
  int? _exitCode;
  bool _disposed = false;

  /// Open/closed flag per conversation thread, keyed by conversation id
  /// (`null` = the not-yet-saved draft thread). Threads are independent: a
  /// thread the user never opened the terminal on stays closed when they
  /// switch to it. Only visibility is per thread — the shell itself is shared,
  /// because it is anchored to the project, not the conversation.
  final Map<String?, bool> _panelOpenByThread = <String?, bool>{};

  /// Whether the bottom panel is showing for [threadId]. Owned here rather
  /// than by the page so the header toggle and the panel's own close button
  /// agree, and so hiding the panel never implies killing the shell.
  bool isPanelOpenFor(String? threadId) =>
      _panelOpenByThread[threadId] ?? false;

  void togglePanel(String? threadId) =>
      _setPanelOpen(threadId, !isPanelOpenFor(threadId));

  void closePanel(String? threadId) => _setPanelOpen(threadId, false);

  void _setPanelOpen(String? threadId, bool value) {
    if (isPanelOpenFor(threadId) == value) return;
    _panelOpenByThread[threadId] = value;
    notifyListeners();
  }

  /// Directory the live (or last) shell was spawned in.
  String? get workingDirectory => _workingDirectory;

  /// Exit code of the shell once it terminated, `null` while it runs.
  int? get exitCode => _exitCode;

  bool get isRunning => _pty != null && _exitCode == null;

  /// Spawn the shell if none is running, or re-anchor it when the active
  /// project changed. Safe to call on every panel build.
  ///
  /// Switching projects replaces the session rather than keeping the old cwd:
  /// a terminal pointing at a project the user has left is worse than losing
  /// whatever was running in it.
  Future<void> ensureStarted({required String workingDirectory}) {
    final directory = _normalizeDirectory(workingDirectory);
    if (_targetDirectory == directory && (isRunning || _startup != null)) {
      return _startup ?? Future.value();
    }
    if (isRunning || _startup != null) {
      return restart(workingDirectory: workingDirectory);
    }
    return _startup = _start(workingDirectory);
  }

  /// Kill the current shell (if any) and spawn a fresh one.
  Future<void> restart({required String workingDirectory}) {
    _terminate();
    terminal.buffer.clear();
    terminal.buffer.setCursor(0, 0);
    return _startup = _start(workingDirectory);
  }

  Future<void> _start(String workingDirectory) async {
    if (!isSupported || _disposed) return;

    final directory = _normalizeDirectory(workingDirectory);
    // Claim this generation synchronously: awaiting the login environment
    // below leaves a window where a project switch can request another shell,
    // and only the newest request may install its Pty.
    final generation = ++_generation;
    _targetDirectory = directory;
    final shell = _resolveShell();
    // The login PATH is what makes `flutter`, `fvm`, `git` resolve inside a
    // GUI-launched app; the same reason the shell tool merges it.
    final environment = await LoginShellEnvironment.instance.environment();
    if (_disposed || generation != _generation) return;

    try {
      final pty = Pty.start(
        shell,
        arguments: _shellArguments(),
        workingDirectory: directory,
        environment: environment,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );

      _pty = pty;
      _workingDirectory = directory;
      _exitCode = null;

      _outputSubscription = pty.output.cast<List<int>>().listen(
        (chunk) => terminal.write(
          const Utf8Decoder(allowMalformed: true).convert(chunk),
        ),
      );
      unawaited(
        pty.exitCode.then((code) {
          if (_disposed || !identical(_pty, pty)) return;
          _exitCode = code;
          terminal.write('\r\n[process exited with code $code]\r\n');
          notifyListeners();
        }),
      );

      terminal.onOutput = (data) {
        if (_exitCode != null) return;
        pty.write(const Utf8Encoder().convert(data));
      };
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (_exitCode != null) return;
        pty.resize(height, width);
      };
    } catch (error) {
      appLog('CodingTerminalService: failed to start $shell: $error');
      terminal.write('\r\n[failed to start $shell: $error]\r\n');
      _pty = null;
      _exitCode = -1;
    } finally {
      if (generation == _generation) _startup = null;
      if (!_disposed) notifyListeners();
    }
  }

  static String? _normalizeDirectory(String directory) {
    final trimmed = directory.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _terminate() {
    _generation++;
    _startup = null;
    _outputSubscription?.cancel();
    _outputSubscription = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    final pty = _pty;
    _pty = null;
    _exitCode = null;
    if (pty == null) return;
    try {
      pty.kill();
    } catch (error) {
      appLog('CodingTerminalService: failed to kill shell: $error');
    }
  }

  static String _resolveShell() {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/sh';
  }

  /// Start POSIX shells as *login* shells so the user's prompt, aliases, and
  /// profile-managed PATH match what they see in Terminal.app.
  static List<String> _shellArguments() {
    if (Platform.isWindows) return const [];
    return const ['-l'];
  }

  @override
  void dispose() {
    _disposed = true;
    _terminate();
    terminalController.dispose();
    super.dispose();
  }
}
