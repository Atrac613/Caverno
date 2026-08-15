import 'dart:async';
import 'dart:io';

import '../../data/datasources/flutter_run_process_runner.dart';
import '../entities/flutter_run_device.dart';
import '../entities/flutter_run_session.dart';
import 'flutter_run_command_builder.dart';

/// Drives one project's `flutter run`: device discovery, the process, its log
/// stream, and stopping it.
///
/// Stopping is staged rather than an immediate kill. `flutter run` owns a
/// device connection and child tooling; quitting through its own `q` command
/// lets it detach cleanly, and the signals below are the fallback for a process
/// that has stopped reading stdin.
class FlutterRunSessionController {
  FlutterRunSessionController({
    required FlutterRunProcessRunner runner,
    FlutterRunCommandBuilder commands = const FlutterRunCommandBuilder(),
    DateTime Function()? clock,
    Duration gracefulQuitTimeout = const Duration(seconds: 5),
    Duration terminateTimeout = const Duration(seconds: 5),
  }) : _runner = runner,
       _commands = commands,
       _clock = clock ?? DateTime.now,
       _gracefulQuitTimeout = gracefulQuitTimeout,
       _terminateTimeout = terminateTimeout;

  final FlutterRunProcessRunner _runner;
  final FlutterRunCommandBuilder _commands;
  final DateTime Function() _clock;
  final Duration _gracefulQuitTimeout;
  final Duration _terminateTimeout;

  final _stateController = StreamController<FlutterRunSessionState>.broadcast();

  FlutterRunSessionState _state = const FlutterRunSessionState();
  FlutterRunProcessHandle? _handle;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;

  FlutterRunSessionState get state => _state;

  Stream<FlutterRunSessionState> get states => _stateController.stream;

  bool isFlutterProject(String projectRoot) =>
      _commands.isFlutterProject(projectRoot);

  /// Lists run targets. Returns an empty list on any failure and leaves the
  /// reason in the state, so the caller shows one message instead of two.
  Future<List<FlutterRunDevice>> listDevices({
    required String projectRoot,
  }) async {
    if (_state.isActive) return const [];
    _emit(
      _state.copyWith(
        status: FlutterRunStatus.listingDevices,
        clearFailure: true,
      ),
    );
    final command = _commands.devices(projectRoot: projectRoot);
    final FlutterRunCommandOutput output;
    try {
      output = await _runner.run(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: command.workingDirectory,
      );
    } on Object catch (error) {
      _emit(_failed('${command.displayCommand}: $error'));
      return const [];
    }

    if (!output.succeeded) {
      _emit(_failed(_firstMeaningfulLine(output.stderr, output.stdout)));
      return const [];
    }

    final devices = FlutterRunCommandBuilder.parseDevices(output.stdout);
    _emit(_state.copyWith(status: FlutterRunStatus.idle));
    return devices;
  }

  /// Starts `flutter run` on [device]. Does nothing when a run is active.
  Future<void> start({
    required String projectRoot,
    required FlutterRunDevice device,
  }) async {
    if (_state.isActive) return;
    final command = _commands.run(
      projectRoot: projectRoot,
      deviceId: device.id,
    );
    _emit(
      FlutterRunSessionState(
        status: FlutterRunStatus.starting,
        device: device,
        command: command.displayCommand,
      ),
    );
    _append(FlutterRunLogSource.harness, '\$ ${command.displayCommand}');

    final FlutterRunProcessHandle handle;
    try {
      handle = await _runner.start(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: command.workingDirectory,
      );
    } on Object catch (error) {
      _emit(_failed('$error'));
      return;
    }

    _handle = handle;
    _stdout = handle.stdoutLines.listen(
      (line) => _append(FlutterRunLogSource.stdout, line),
    );
    _stderr = handle.stderrLines.listen(
      (line) => _append(FlutterRunLogSource.stderr, line),
    );
    _emit(_state.copyWith(status: FlutterRunStatus.running));

    unawaited(
      handle.exitCode.then(
        _onExit,
        onError: (Object error) => _emit(_failed('$error')),
      ),
    );
  }

  /// Asks the run to stop: `q`, then SIGTERM, then SIGKILL.
  Future<void> stop() async {
    final handle = _handle;
    if (handle == null || !_state.isActive) return;
    _emit(_state.copyWith(status: FlutterRunStatus.stopping));
    _append(FlutterRunLogSource.harness, 'Stopping...');

    handle.write('q');
    if (await _waitForExit(_gracefulQuitTimeout)) return;

    _append(FlutterRunLogSource.harness, 'Still running; sending SIGTERM.');
    handle.kill();
    if (await _waitForExit(_terminateTimeout)) return;

    _append(FlutterRunLogSource.harness, 'Still running; sending SIGKILL.');
    handle.kill(ProcessSignal.sigkill);
  }

  /// Clears a finished run so the panel can return to its idle state. Keeps
  /// the logs: they are the reason the run is worth looking at after it ended.
  void acknowledgeExit() {
    if (_state.isActive) return;
    _emit(_state.copyWith(status: FlutterRunStatus.idle, clearFailure: true));
  }

  void clearLogs() {
    _emit(_state.copyWith(logs: const <FlutterRunLogLine>[]));
  }

  Future<void> dispose() async {
    await _stdout?.cancel();
    await _stderr?.cancel();
    _handle?.kill(ProcessSignal.sigkill);
    _handle = null;
    await _stateController.close();
  }

  Future<bool> _waitForExit(Duration timeout) async {
    final handle = _handle;
    if (handle == null) return true;
    try {
      await handle.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } on Object {
      return true;
    }
  }

  void _onExit(int code) {
    unawaited(_stdout?.cancel());
    unawaited(_stderr?.cancel());
    _stdout = null;
    _stderr = null;
    _handle = null;
    _append(FlutterRunLogSource.harness, 'Process exited with code $code.');
    _emit(
      _state.copyWith(
        status: code == 0 ? FlutterRunStatus.exited : FlutterRunStatus.failed,
        exitCode: code,
      ),
    );
  }

  FlutterRunSessionState _failed(String message) => _state.copyWith(
    status: FlutterRunStatus.failed,
    failure: message.trim().isEmpty ? 'The command failed.' : message.trim(),
  );

  void _append(FlutterRunLogSource source, String text) {
    _emit(
      _state.appendLog(
        FlutterRunLogLine(text: text, source: source, at: _clock()),
      ),
    );
  }

  void _emit(FlutterRunSessionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  static String _firstMeaningfulLine(String stderr, String stdout) {
    for (final candidate in [stderr, stdout]) {
      for (final line in candidate.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    return '';
  }
}
