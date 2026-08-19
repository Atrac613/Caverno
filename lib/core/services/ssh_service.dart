import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../../features/chat/domain/entities/chat_turn_owner.dart';
import '../utils/logger.dart';
import 'ssh_client_connector.dart';

// [connect] speaks in credentials, so callers get the credential types and
// the identity errors they must report without a second import.
export 'ssh_client_connector.dart';
export 'ssh_host_key_providers.dart' show sshServiceProvider;

typedef SshConnectorFn =
    Future<SSHClient> Function({
      required String host,
      required int port,
      required String username,
      required SshAuthCredential credential,
      required Duration timeout,
    });

/// Information about an active SSH session.
class SshSessionInfo {
  SshSessionInfo({
    required this.host,
    required this.port,
    required this.username,
    required this.connectedAt,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String username;
  final DateTime connectedAt;
  final String fingerprint;
}

/// Result of a single SSH command.
class SshExecutionResult {
  SshExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;

  /// Produces a compact, LLM-friendly tool result body.
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

/// Owns independent SSH sessions keyed by exact chat turn identity.
class SshService {
  SshService({SshConnectorFn? connector})
    : _connector = connector ?? SshClientConnector.connect;

  final SshConnectorFn _connector;
  final Map<ChatTurnOwner, _SshOwnerState> _states = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  int _nextSessionFingerprint = 0;
  bool _disposed = false;

  bool isConnected({required ChatTurnOwner owner}) =>
      _states[owner]?.client != null;

  SshSessionInfo? status({required ChatTurnOwner owner}) =>
      _states[owner]?.sessionInfo;

  SshSessionInfo? activeSession({required ChatTurnOwner owner}) =>
      status(owner: owner);

  String? activeSessionFingerprint({required ChatTurnOwner owner}) =>
      _states[owner]?.sessionInfo?.fingerprint;

  /// Opens a session for [owner], replacing only that owner's prior session.
  Future<void> connect({
    required ChatTurnOwner owner,
    required String host,
    required int port,
    required String username,
    required SshAuthCredential credential,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_disposed || _retiredOwners.contains(owner)) {
      throw StateError(
        _disposed
            ? 'SSH service has been disposed.'
            : 'SSH session owner has been retired.',
      );
    }

    final state = _SshOwnerState(
      fingerprint: 'ssh-session:${++_nextSessionFingerprint}',
    );
    final previous = _states[owner];
    _states[owner] = state;
    if (previous != null) {
      await _closeState(previous);
    }
    _ensureActive(owner, state);

    SSHClient? client;
    try {
      client = await _connector(
        host: host,
        port: port,
        username: username,
        credential: credential,
        timeout: timeout,
      );
      _ensureActive(owner, state);
      await client.authenticated.timeout(timeout);
      _ensureActive(owner, state);

      state
        ..client = client
        ..sessionInfo = SshSessionInfo(
          host: host,
          port: port,
          username: username,
          connectedAt: DateTime.now(),
          fingerprint: state.fingerprint,
        );
      appLog('[SshService] Connected: $username@$host:$port');
    } on TimeoutException {
      await _closeClient(client);
      _removePendingState(owner, state);
      throw Exception('SSH connect timed out after ${timeout.inSeconds}s');
    } on SSHAuthFailError {
      await _closeClient(client);
      _removePendingState(owner, state);
      throw Exception('SSH auth failed: $username@$host:$port, $credential');
    } on SSHAuthAbortError catch (error) {
      await _closeClient(client);
      _removePendingState(owner, state);
      throw Exception('SSH authentication aborted: $error');
    } on SocketException catch (error) {
      await _closeClient(client);
      _removePendingState(owner, state);
      throw Exception('SSH connection failed: ${error.message}');
    } catch (_) {
      await _closeClient(client);
      _removePendingState(owner, state);
      rethrow;
    }
  }

  /// Runs [command] on the exact owner's active session.
  Future<SshExecutionResult> execute({
    required ChatTurnOwner owner,
    required String command,
    String? expectedFingerprint,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final state = _states[owner];
    final client = state?.client;
    if (state == null || client == null) {
      throw StateError('No active SSH session. Call connect() first.');
    }
    _ensureExpectedFingerprint(state, expectedFingerprint);

    try {
      final session = await client.execute(command).timeout(timeout);
      _ensureActiveClient(owner, state, client);
      _ensureExpectedFingerprint(state, expectedFingerprint);
      final stdoutBytes = <int>[];
      final stderrBytes = <int>[];
      await Future.wait([
        session.stdout.forEach(stdoutBytes.addAll),
        session.stderr.forEach(stderrBytes.addAll),
      ]).timeout(timeout);
      await session.done.timeout(timeout);
      _ensureActiveClient(owner, state, client);
      _ensureExpectedFingerprint(state, expectedFingerprint);

      return SshExecutionResult(
        stdout: utf8.decode(stdoutBytes, allowMalformed: true),
        stderr: utf8.decode(stderrBytes, allowMalformed: true),
        exitCode: session.exitCode,
      );
    } on TimeoutException {
      throw Exception('SSH command timed out after ${timeout.inSeconds}s');
    }
  }

  /// Disconnects only [owner] while allowing an intentional later reconnect.
  Future<void> disconnect({required ChatTurnOwner owner}) =>
      _retireCurrentState(owner);

  /// Closes only the exact externally observed session.
  Future<bool> disconnectIfFingerprint({
    required ChatTurnOwner owner,
    required String expectedFingerprint,
  }) async {
    final state = _states[owner];
    if (state == null || state.fingerprint != expectedFingerprint) return false;
    _states.remove(owner);
    await _closeState(state);
    return true;
  }

  /// Permanently retires and closes the exact owner.
  Future<void> clearOwner({required ChatTurnOwner owner}) {
    _retiredOwners.add(owner);
    return _retireCurrentState(owner);
  }

  Future<void> _retireCurrentState(ChatTurnOwner owner) {
    final state = _states.remove(owner);
    return state == null ? Future<void>.value() : _closeState(state);
  }

  /// Retires every owner and closes all sessions. Safe to call repeatedly.
  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    _disposed = true;
    final states = _states.values.toList(growable: false);
    _states.clear();
    return Future.wait<void>(states.map(_closeState));
  }

  void _ensureActive(ChatTurnOwner owner, _SshOwnerState state) {
    if (_disposed ||
        _retiredOwners.contains(owner) ||
        !identical(_states[owner], state)) {
      throw StateError(
        'SSH session owner was cleared before connection completed.',
      );
    }
  }

  void _ensureActiveClient(
    ChatTurnOwner owner,
    _SshOwnerState state,
    SSHClient client,
  ) {
    if (!identical(_states[owner], state) || !identical(state.client, client)) {
      throw StateError('No active SSH session. Call connect() first.');
    }
  }

  void _ensureExpectedFingerprint(
    _SshOwnerState state,
    String? expectedFingerprint,
  ) {
    if (expectedFingerprint != null &&
        state.fingerprint != expectedFingerprint) {
      throw StateError('The active SSH session identity changed.');
    }
  }

  void _removePendingState(ChatTurnOwner owner, _SshOwnerState state) {
    if (state.client == null && identical(_states[owner], state)) {
      _states.remove(owner);
    }
  }

  Future<void> _closeState(_SshOwnerState state) {
    final client = state.client;
    state
      ..client = null
      ..sessionInfo = null;
    return _closeClient(client);
  }

  Future<void> _closeClient(SSHClient? client) async {
    if (client == null) return;
    try {
      client.close();
      await client.done;
    } catch (error) {
      appLog('[SshService] Error while closing client: $error');
    }
  }
}

class _SshOwnerState {
  _SshOwnerState({required this.fingerprint});

  final String fingerprint;
  SSHClient? client;
  SshSessionInfo? sessionInfo;
}

