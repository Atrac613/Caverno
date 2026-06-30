import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:serious_python/serious_python.dart';

import '../../utils/logger.dart';
import 'script_runtime.dart';

/// [ScriptRuntime] backed by an embedded CPython interpreter (serious_python).
///
/// The interpreter cannot be re-initialized per call, so we follow the
/// serious_python model: a single long-lived worker (`worker/main.py`) is
/// started once on a background thread and driven over a loopback HTTP channel.
/// The host picks an ephemeral port and a per-session token; both are passed to
/// the worker via environment variables. Jobs are serialized.
class PythonScriptRuntime implements ScriptRuntime {
  PythonScriptRuntime();

  static const Duration _startupTimeout = Duration(seconds: 25);
  static const Duration _healthPollInterval = Duration(milliseconds: 150);

  http.Client? _client;
  int? _port;
  String? _token;
  bool _started = false;
  Future<void>? _startup;
  Directory? _previousCwd;

  // Serializes jobs against the single-threaded worker.
  Future<void> _jobQueue = Future<void>.value();

  @override
  String get language => 'python';

  @override
  String get displayName => 'Python';

  // serious_python supports every native platform Caverno targets.
  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<void> ensureStarted() {
    if (_started) return Future<void>.value();
    return _startup ??= _start();
  }

  Future<void> _start() async {
    try {
      _client = http.Client();
      _port = await _findFreePort();
      _token = _generateToken();
      _previousCwd = Directory.current;

      // Fire-and-forget: the worker serves forever, so this future never
      // completes. We await readiness via /health instead of awaiting run().
      unawaited(
        SeriousPython.run(
          environmentVariables: {
            'CAVERNO_PORT': '$_port',
            'CAVERNO_TOKEN': _token!,
          },
          sync: false,
        ).catchError((Object error) {
          appLog('[python] worker run() ended: $error');
          return null;
        }),
      );

      await _awaitReady();
      // serious_python sets Directory.current to the unpacked worker dir; put
      // the host process cwd back so other Dart tools keep their bearings.
      _restoreCwd();
      _started = true;
    } catch (error) {
      _startup = null; // allow a later retry
      _client?.close();
      _client = null;
      rethrow;
    }
  }

  Future<void> _awaitReady() async {
    final deadline = DateTime.now().add(_startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await _client!
            .get(
              Uri.parse('http://127.0.0.1:$_port/health'),
              headers: {'X-Caverno-Token': _token!},
            )
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) return;
      } catch (_) {
        // Worker not listening yet; keep polling.
      }
      await Future<void>.delayed(_healthPollInterval);
    }
    throw StateError(
      'Python worker did not become ready within '
      '${_startupTimeout.inSeconds}s',
    );
  }

  void _restoreCwd() {
    final previous = _previousCwd;
    if (previous == null) return;
    try {
      Directory.current = previous;
    } catch (error) {
      appLog('[python] failed to restore cwd: $error');
    }
  }

  @override
  Future<ScriptRunResult> run(ScriptRunRequest request) {
    final next = _jobQueue.then((_) => _runLocked(request));
    // Chain the queue but never let one job's failure poison the next.
    _jobQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<ScriptRunResult> _runLocked(ScriptRunRequest request) async {
    if (!isSupported) {
      return const ScriptRunResult(
        error: 'python_runtime_unsupported_platform',
      );
    }
    try {
      await ensureStarted();
    } catch (error) {
      return ScriptRunResult(error: 'python_runtime_unavailable: $error');
    }

    final body = jsonEncode({
      'code': request.code,
      'inputs': request.inputs.map((input) => input.toJson()).toList(),
      'cwd': request.workingDirectory ?? '',
      'timeout': request.timeout.inSeconds,
    });

    try {
      final response = await _client!
          .post(
            Uri.parse('http://127.0.0.1:$_port/run'),
            headers: {
              'Content-Type': 'application/json',
              'X-Caverno-Token': _token!,
            },
            body: body,
          )
          .timeout(request.timeout + const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return ScriptRunResult(
          error: 'python_worker_http_${response.statusCode}',
          stderr: response.body,
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return ScriptRunResult(
        stdout: decoded['stdout'] as String? ?? '',
        stderr: decoded['stderr'] as String? ?? '',
        result: decoded['result'],
        error: decoded['error'] as String?,
        traceback: decoded['traceback'] as String?,
        timedOut: decoded['timed_out'] as bool? ?? false,
      );
    } on TimeoutException {
      return const ScriptRunResult(
        error: 'python_worker_timeout',
        timedOut: true,
      );
    } catch (error) {
      return ScriptRunResult(error: 'python_worker_error: $error');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      SeriousPython.terminate();
    } catch (_) {
      // Ignore: terminate is best-effort and may be unsupported.
    }
    _client?.close();
    _client = null;
    _started = false;
    _startup = null;
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
