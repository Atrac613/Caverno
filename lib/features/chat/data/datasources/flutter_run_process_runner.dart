import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A spawned process, narrowed to what a run session needs.
///
/// An interface rather than `Process` so the session can be driven by a fake in
/// tests: spawning a real `flutter run` to assert on log plumbing would make
/// those tests need a device.
abstract interface class FlutterRunProcessHandle {
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  Future<int> get exitCode;

  /// Sends [input] to the process. `flutter run` takes single-letter commands
  /// this way, including `q` for a graceful quit.
  void write(String input);

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Result of one non-interactive command, e.g. `flutter devices --machine`.
class FlutterRunCommandOutput {
  const FlutterRunCommandOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

/// Spawns Flutter tooling. The only place in this feature that touches
/// `dart:io` process APIs.
abstract interface class FlutterRunProcessRunner {
  Future<FlutterRunCommandOutput> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  });

  Future<FlutterRunProcessHandle> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  });
}

class SystemFlutterRunProcessRunner implements FlutterRunProcessRunner {
  const SystemFlutterRunProcessRunner({Map<String, String>? environment})
    : _environment = environment;

  final Map<String, String>? _environment;

  @override
  Future<FlutterRunCommandOutput> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: _environment,
      // The tool prints its own banners; inheriting a login environment is
      // what makes `fvm` resolvable when the app was launched from Finder.
      includeParentEnvironment: true,
      runInShell: false,
    );
    return FlutterRunCommandOutput(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  @override
  Future<FlutterRunProcessHandle> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: _environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    return _SystemProcessHandle(process);
  }
}

class _SystemProcessHandle implements FlutterRunProcessHandle {
  _SystemProcessHandle(this._process);

  final Process _process;

  @override
  Stream<String> get stdoutLines => _process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  Stream<String> get stderrLines => _process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(String input) {
    try {
      _process.stdin.write(input);
    } on Object {
      // The process may have exited between the check and the write; a stop
      // that races the app's own exit is not a failure.
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}
