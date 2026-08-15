import 'dart:async';

import '../../data/datasources/flutter_run_process_runner.dart';
import '../entities/flutter_run_device.dart';
import '../entities/flutter_run_session.dart';
import 'flutter_run_command_builder.dart';

/// Devices found, or the reason none were.
class FlutterRunDeviceListing {
  const FlutterRunDeviceListing.found(this.devices) : failure = null;

  const FlutterRunDeviceListing.failed(this.failure)
    : devices = const <FlutterRunDevice>[];

  final List<FlutterRunDevice> devices;
  final String? failure;
}

/// Runs `flutter devices --machine` and reads back what it found.
///
/// Streamed rather than collected, and bounded by a timeout, because the
/// command is not reliably quick: it blocks behind another flutter command's
/// startup lock, and `fvm` sits waiting on stdin when the pinned SDK is
/// missing. Buffering until exit hid both -- the panel said "looking for
/// devices" with no way to learn what it was waiting on, and nothing to end
/// the wait.
class FlutterRunDeviceLister {
  const FlutterRunDeviceLister({
    required FlutterRunProcessRunner runner,
    required FlutterRunCommandBuilder commands,
    required Duration timeout,
  }) : _runner = runner,
       _commands = commands,
       _timeout = timeout;

  final FlutterRunProcessRunner _runner;
  final FlutterRunCommandBuilder _commands;
  final Duration _timeout;

  /// Grace for the pipes to close after the process exits.
  static const _drainTimeout = Duration(seconds: 2);

  Future<FlutterRunDeviceListing> list({
    required String projectRoot,
    required void Function(FlutterRunLogSource source, String text) onLog,
  }) async {
    final command = _commands.devices(projectRoot: projectRoot);
    onLog(FlutterRunLogSource.harness, '\$ ${command.displayCommand}');

    final FlutterRunProcessHandle handle;
    try {
      handle = await _runner.start(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: command.workingDirectory,
      );
    } on Object catch (error) {
      return FlutterRunDeviceListing.failed(
        '${command.displayCommand}: $error',
      );
    }

    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final outDrained = Completer<void>();
    final errDrained = Completer<void>();
    // Echoed as it arrives so a wait is legible: "Waiting for another flutter
    // command to release the startup lock..." answers "why is this taking so
    // long", and only helps if the user can see it.
    final outSubscription = handle.stdoutLines.listen(
      (line) {
        stdout.writeln(line);
        onLog(FlutterRunLogSource.stdout, line);
      },
      onDone: outDrained.complete,
      onError: (Object _) => outDrained.complete(),
      cancelOnError: true,
    );
    final errSubscription = handle.stderrLines.listen(
      (line) {
        stderr.writeln(line);
        onLog(FlutterRunLogSource.stderr, line);
      },
      onDone: errDrained.complete,
      onError: (Object _) => errDrained.complete(),
      cancelOnError: true,
    );

    int? exitCode;
    String? failure;
    try {
      exitCode = await handle.exitCode.timeout(_timeout);
      // Exiting does not mean the pipes are empty: a command that writes its
      // answer and exits immediately leaves output queued behind the exit
      // future, and cancelling here would read back nothing.
      await Future.wait([
        outDrained.future,
        errDrained.future,
      ]).timeout(_drainTimeout, onTimeout: () => const []);
    } on TimeoutException {
      handle.kill();
      onLog(
        FlutterRunLogSource.harness,
        'Gave up after ${_timeout.inSeconds}s.',
      );
    } on Object catch (error) {
      failure = '$error';
    } finally {
      await outSubscription.cancel();
      await errSubscription.cancel();
    }

    if (failure != null) return FlutterRunDeviceListing.failed(failure);
    final reported = _firstMeaningfulLine(stderr.toString(), stdout.toString());
    if (exitCode == null) {
      return FlutterRunDeviceListing.failed(
        reported.isEmpty
            ? 'Timed out after ${_timeout.inSeconds}s. Another flutter '
                  'command may hold the startup lock.'
            : reported,
      );
    }
    if (exitCode != 0) return FlutterRunDeviceListing.failed(reported);
    return FlutterRunDeviceListing.found(
      FlutterRunCommandBuilder.parseDevices(stdout.toString()),
    );
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
