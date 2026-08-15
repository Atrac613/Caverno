import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/flutter_run_process_runner.dart';
import 'package:caverno/features/chat/domain/entities/flutter_run_device.dart';
import 'package:caverno/features/chat/domain/entities/flutter_run_session.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_command_builder.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_session_controller.dart';

void main() {
  const device = FlutterRunDevice(
    id: 'macos',
    name: 'macOS',
    targetPlatform: 'darwin',
  );

  FlutterRunSessionController controllerFor(
    _FakeRunner runner, {
    Duration graceful = const Duration(milliseconds: 20),
    Duration terminate = const Duration(milliseconds: 20),
  }) {
    return FlutterRunSessionController(
      runner: runner,
      commands: const FlutterRunCommandBuilder(usesFvm: _alwaysFvm),
      clock: () => DateTime.utc(2026, 8, 15, 20),
      gracefulQuitTimeout: graceful,
      terminateTimeout: terminate,
    );
  }

  test('lists devices through the project toolchain', () async {
    final runner = _FakeRunner(
      runOutput: const FlutterRunCommandOutput(
        exitCode: 0,
        stdout: '[{"name":"macOS","id":"macos","targetPlatform":"darwin"}]',
        stderr: '',
      ),
    );
    final controller = controllerFor(runner);

    final devices = await controller.listDevices(projectRoot: '/work/app');

    expect(devices.single.id, 'macos');
    expect(runner.ranExecutable, 'fvm');
    expect(runner.ranArguments, ['flutter', 'devices', '--machine']);
    expect(controller.state.status, FlutterRunStatus.idle);
    await controller.dispose();
  });

  test('a failed device listing explains itself once', () async {
    final runner = _FakeRunner(
      runOutput: const FlutterRunCommandOutput(
        exitCode: 1,
        stdout: '',
        stderr: '\nNo pubspec.yaml file found.\n',
      ),
    );
    final controller = controllerFor(runner);

    final devices = await controller.listDevices(projectRoot: '/work/app');

    expect(devices, isEmpty);
    expect(controller.state.status, FlutterRunStatus.failed);
    expect(controller.state.failure, 'No pubspec.yaml file found.');
    await controller.dispose();
  });

  test('streams both output channels into the log', () async {
    final runner = _FakeRunner();
    final controller = controllerFor(runner);

    await controller.start(projectRoot: '/work/app', device: device);
    runner.handle.emitStdout('Launching lib/main.dart on macOS...');
    runner.handle.emitStderr('A dependency is out of date.');
    await pumpEventQueue();

    expect(controller.state.status, FlutterRunStatus.running);
    expect(controller.state.command, 'fvm flutter run -d macos');
    expect(controller.state.logs.map((line) => line.text), [
      r'$ fvm flutter run -d macos',
      'Launching lib/main.dart on macOS...',
      'A dependency is out of date.',
    ]);
    expect(controller.state.logs.last.isError, isTrue);
    await controller.dispose();
  });

  test('stop asks flutter to quit before signalling', () async {
    final runner = _FakeRunner();
    final controller = controllerFor(runner);
    await controller.start(projectRoot: '/work/app', device: device);

    final stopping = controller.stop();
    await pumpEventQueue();
    expect(runner.handle.stdinWrites, ['q']);
    expect(runner.handle.signals, isEmpty);

    runner.handle.exit(0);
    await stopping;

    expect(controller.state.status, FlutterRunStatus.exited);
    expect(controller.state.exitCode, 0);
    await controller.dispose();
  });

  test(
    'escalates to SIGTERM then SIGKILL for a process that ignores q',
    () async {
      final runner = _FakeRunner();
      final controller = controllerFor(runner);
      await controller.start(projectRoot: '/work/app', device: device);

      await controller.stop();

      expect(runner.handle.stdinWrites, ['q']);
      expect(runner.handle.signals, [
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
      await controller.dispose();
    },
  );

  test('a non-zero exit is reported as a failed run', () async {
    final runner = _FakeRunner();
    final controller = controllerFor(runner);
    await controller.start(projectRoot: '/work/app', device: device);

    runner.handle.exit(1);
    await pumpEventQueue();

    expect(controller.state.status, FlutterRunStatus.failed);
    expect(controller.state.exitCode, 1);
    expect(controller.state.logs.last.text, contains('exited with code 1'));
    await controller.dispose();
  });

  test('a spawn failure keeps the reason instead of a blank panel', () async {
    final runner = _FakeRunner(startError: 'No such file or directory: fvm');
    final controller = controllerFor(runner);

    await controller.start(projectRoot: '/work/app', device: device);

    expect(controller.state.status, FlutterRunStatus.failed);
    expect(controller.state.failure, contains('No such file'));
    await controller.dispose();
  });

  test('refuses to start a second run over a live one', () async {
    final runner = _FakeRunner();
    final controller = controllerFor(runner);
    await controller.start(projectRoot: '/work/app', device: device);

    await controller.start(projectRoot: '/work/app', device: device);

    expect(runner.startCount, 1);
    await controller.dispose();
  });

  test('keeps only the most recent lines', () async {
    final runner = _FakeRunner();
    final controller = controllerFor(runner);
    await controller.start(projectRoot: '/work/app', device: device);

    for (
      var index = 0;
      index < FlutterRunSessionState.maxRetainedLines;
      index++
    ) {
      runner.handle.emitStdout('line $index');
    }
    await pumpEventQueue();

    expect(
      controller.state.logs,
      hasLength(FlutterRunSessionState.maxRetainedLines),
    );
    expect(controller.state.logs.last.text, endsWith('line 1999'));
    // The command echo was the first line and has aged out.
    expect(controller.state.logs.first.text, isNot(contains(r'$ fvm')));
    await controller.dispose();
  });
}

bool _alwaysFvm(String projectRoot) => true;

class _FakeRunner implements FlutterRunProcessRunner {
  _FakeRunner({this.runOutput, this.startError});

  final FlutterRunCommandOutput? runOutput;
  final String? startError;
  final handle = _FakeHandle();

  String? ranExecutable;
  List<String>? ranArguments;
  int startCount = 0;

  @override
  Future<FlutterRunCommandOutput> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    ranExecutable = executable;
    ranArguments = arguments;
    return runOutput ??
        const FlutterRunCommandOutput(exitCode: 0, stdout: '[]', stderr: '');
  }

  @override
  Future<FlutterRunProcessHandle> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    startCount += 1;
    final failure = startError;
    if (failure != null) throw ProcessException(executable, arguments, failure);
    return handle;
  }
}

class _FakeHandle implements FlutterRunProcessHandle {
  final _stdout = StreamController<String>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final stdinWrites = <String>[];
  final signals = <ProcessSignal>[];

  void emitStdout(String line) => _stdout.add(line);
  void emitStderr(String line) => _stderr.add(line);

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<String> get stdoutLines => _stdout.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(String input) => stdinWrites.add(input);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == ProcessSignal.sigkill) exit(-9);
    return true;
  }
}
