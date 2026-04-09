import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// Information about the currently active SSH session.
class SshSessionInfo {
  SshSessionInfo({
    required this.host,
    required this.port,
    required this.username,
    required this.connectedAt,
  });

  final String host;
  final int port;
  final String username;
  final DateTime connectedAt;
}

/// Result of a single `execute` call on the active SSH session.
class SshExecutionResult {
  SshExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;

  /// Produces a compact, LLM-friendly textual rendering used as the tool
  /// result body.
  String formatted() {
    final buffer = StringBuffer();
    buffer.writeln('exit_code: ${exitCode ?? 'n/a'}');
    if (stdout.isNotEmpty) {
      buffer.writeln('--- stdout ---');
      buffer.writeln(stdout);
    }
    if (stderr.isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(stderr);
    }
    return buffer.toString();
  }
}

/// Holds at most one live SSH session and executes commands against it.
///
/// The service is deliberately stateful and long-lived: the user initiates
/// a session from chat, runs multiple commands through it, then explicitly
/// disconnects. There is no connection pooling; a new `connect()` call
/// replaces any existing session.
class SshService {
  SSHClient? _client;
  SshSessionInfo? _sessionInfo;

  bool get isConnected => _client != null;
  SshSessionInfo? get activeSession => _sessionInfo;

  /// Opens a new SSH session, replacing any existing one.
  ///
  /// Surfaces readable exceptions for DNS/TCP failures, authentication
  /// failures, and timeouts.
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Tear down any prior session so a failed reconnect leaves no zombie.
    await disconnect();

    SSHSocket? socket;
    SSHClient? client;
    try {
      socket = await SSHSocket.connect(host, port, timeout: timeout);
      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      // Force authentication negotiation to surface auth failures eagerly
      // (rather than waiting for the first `execute` call).
      await client.authenticated.timeout(timeout);

      _client = client;
      _sessionInfo = SshSessionInfo(
        host: host,
        port: port,
        username: username,
        connectedAt: DateTime.now(),
      );
      appLog('[SshService] Connected: $username@$host:$port');
    } on TimeoutException {
      client?.close();
      throw Exception('SSH connect timed out after ${timeout.inSeconds}s');
    } on SSHAuthFailError catch (e) {
      client?.close();
      throw Exception('SSH authentication failed: $e');
    } on SSHAuthAbortError catch (e) {
      client?.close();
      throw Exception('SSH authentication aborted: $e');
    } on SocketException catch (e) {
      client?.close();
      throw Exception('SSH connection failed: ${e.message}');
    } catch (e) {
      client?.close();
      rethrow;
    }
  }

  /// Runs [command] on the active session and returns captured output.
  ///
  /// Throws [StateError] when no session is active.
  Future<SshExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('No active SSH session. Call connect() first.');
    }

    try {
      final session = await client.execute(command).timeout(timeout);

      final stdoutBytes = <int>[];
      final stderrBytes = <int>[];
      await Future.wait([
        session.stdout.forEach(stdoutBytes.addAll),
        session.stderr.forEach(stderrBytes.addAll),
      ]).timeout(timeout);
      await session.done.timeout(timeout);

      return SshExecutionResult(
        stdout: utf8.decode(stdoutBytes, allowMalformed: true),
        stderr: utf8.decode(stderrBytes, allowMalformed: true),
        exitCode: session.exitCode,
      );
    } on TimeoutException {
      throw Exception('SSH command timed out after ${timeout.inSeconds}s');
    }
  }

  /// Closes the active session, if any. Safe to call when nothing is open.
  Future<void> disconnect() async {
    final client = _client;
    if (client == null) return;
    try {
      client.close();
      await client.done;
    } catch (e) {
      appLog('[SshService] Error while closing client: $e');
    } finally {
      _client = null;
      _sessionInfo = null;
    }
  }
}

final sshServiceProvider = Provider<SshService>((ref) {
  final service = SshService();
  ref.onDispose(() {
    // Best-effort cleanup; ignore errors during shutdown.
    unawaited(service.disconnect());
  });
  return service;
});
