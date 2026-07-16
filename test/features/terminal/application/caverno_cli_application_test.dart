import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:caverno/features/terminal/application/caverno_cli_application.dart';
import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_cli_input.dart';
import 'package:caverno/features/terminal/application/caverno_cli_runtime_port.dart';
import 'package:caverno/features/terminal/presentation/caverno_terminal_presenter.dart';

void main() {
  test('returns success after the shared runtime terminal event', () async {
    final runtime = _FakeRuntime((runtime, invocation, prompt) async {
      runtime.emit(_started(sequence: 1));
      runtime.emit(
        CavernoRuntimeAssistantDelta(
          sequence: 2,
          timestamp: DateTime.utc(2026),
          turnId: 'turn-1',
          delta: 'Hello',
        ),
      );
      runtime.emit(
        CavernoRuntimeRunCompleted(
          sequence: 3,
          timestamp: DateTime.utc(2026),
          turnId: 'turn-1',
          content: 'Hello',
        ),
      );
    });
    final output = _RecordingTerminal();
    final application = CavernoCliApplication(
      input: _FakeInput(isTerminal: false),
      output: output,
      runtime: runtime,
    );

    final exitCode = await application.run(
      CavernoCliInvocation.parse(const ['chat', 'hello']),
    );

    expect(exitCode, CavernoCliExitCode.success);
    expect(output.stdout.toString(), 'Hello\n');
    expect(runtime.prepared, isTrue);
    expect(runtime.closed, isTrue);
  });

  test('fails closed when a non-TTY runtime requests approval', () async {
    final runtime = _FakeRuntime((runtime, invocation, prompt) async {
      runtime.emit(_started(sequence: 1));
      runtime.emit(
        CavernoRuntimeApprovalRequired(
          sequence: 2,
          timestamp: DateTime.utc(2026),
          turnId: 'turn-1',
          request: const CavernoRuntimeApprovalRequest(
            id: 'approval-1',
            capability: 'file_mutation',
            risk: CavernoRuntimeApprovalRisk.high,
            summary: 'Write a file',
          ),
        ),
      );
    });
    final application = CavernoCliApplication(
      input: _FakeInput(isTerminal: false),
      output: _RecordingTerminal(),
      runtime: runtime,
    );

    final exitCode = await application.run(
      CavernoCliInvocation.parse(const ['chat', 'change it']),
    );

    expect(exitCode, CavernoCliExitCode.approval);
    expect(runtime.approvals, [('approval-1', false)]);
    expect(runtime.terminations.single.code, 'approval_unavailable');
  });

  test('JSON mode never opens an approval prompt on a TTY', () async {
    final runtime = _FakeRuntime((runtime, invocation, prompt) async {
      runtime.emit(_started(sequence: 1));
      runtime.emit(
        CavernoRuntimeApprovalRequired(
          sequence: 2,
          timestamp: DateTime.utc(2026),
          turnId: 'turn-1',
          request: const CavernoRuntimeApprovalRequest(
            id: 'approval-1',
            capability: 'file_mutation',
            risk: CavernoRuntimeApprovalRisk.high,
            summary: 'Write a file',
          ),
        ),
      );
    });
    final output = _RecordingTerminal();
    final application = CavernoCliApplication(
      input: _FakeInput(isTerminal: true),
      output: output,
      runtime: runtime,
    );

    final exitCode = await application.run(
      CavernoCliInvocation.parse(const ['chat', '--json', 'change it']),
    );

    expect(exitCode, CavernoCliExitCode.approval);
    expect(runtime.approvals, [('approval-1', false)]);
    expect(runtime.terminations.single.code, 'approval_unavailable');
    expect(output.stderr.toString(), isNot(contains('Approve once?')));
  });

  test('maps cancellation to exit code 130', () async {
    final cancellation = StreamController<void>();
    final runtime = _FakeRuntime((runtime, invocation, prompt) async {
      runtime.emit(_started(sequence: 1));
      cancellation.add(null);
    });
    final application = CavernoCliApplication(
      input: _FakeInput(isTerminal: false),
      output: _RecordingTerminal(),
      runtime: runtime,
      cancellationSignals: cancellation.stream,
    );

    final exitCode = await application.run(
      CavernoCliInvocation.parse(const ['chat', 'wait']),
    );

    expect(exitCode, CavernoCliExitCode.cancelled);
    expect(runtime.cancelled, isTrue);
    await cancellation.close();
  });
}

typedef _StartBehavior =
    Future<void> Function(
      _FakeRuntime runtime,
      CavernoCliInvocation invocation,
      String prompt,
    );

final class _FakeRuntime implements CavernoCliRuntimePort {
  _FakeRuntime(this._startBehavior);

  final _StartBehavior _startBehavior;
  final StreamController<CavernoRuntimeEvent> _events =
      StreamController<CavernoRuntimeEvent>.broadcast(sync: true);
  final approvals = <(String, bool)>[];
  final questions = <(String, String?)>[];
  final terminations = <({String code, String message, int exitCode})>[];
  bool prepared = false;
  bool cancelled = false;
  bool closed = false;
  int _sequence = 1;

  @override
  Stream<CavernoRuntimeEvent> get events => _events.stream;

  void emit(CavernoRuntimeEvent event) {
    _sequence = event.sequence;
    _events.add(event);
  }

  @override
  Future<void> prepare(CavernoCliInvocation invocation) async {
    prepared = true;
  }

  @override
  Future<void> start({
    required CavernoCliInvocation invocation,
    required String prompt,
  }) => _startBehavior(this, invocation, prompt);

  @override
  Future<void> resolveApproval({
    required String id,
    required bool approved,
  }) async {
    approvals.add((id, approved));
  }

  @override
  Future<void> resolveQuestion({required String id, String? answer}) async {
    questions.add((id, answer));
  }

  @override
  Future<void> terminate({
    required String code,
    required String message,
    required int exitCode,
  }) async {
    terminations.add((code: code, message: message, exitCode: exitCode));
    emit(
      CavernoRuntimeRunFailed(
        sequence: ++_sequence,
        timestamp: DateTime.utc(2026),
        turnId: 'turn-1',
        code: code,
        message: message,
        exitCode: exitCode,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    await terminate(
      code: 'cancelled',
      message: 'Cancelled',
      exitCode: CavernoCliExitCode.cancelled,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}

final class _FakeInput implements CavernoCliInputPort {
  const _FakeInput({required this.isTerminal});

  @override
  final bool isTerminal;

  @override
  Future<String> readFile(String path) => throw UnimplementedError();

  @override
  Future<String?> readLine() async => null;

  @override
  Future<String> readToEnd() async => '';
}

final class _RecordingTerminal implements CavernoTerminalOutputPort {
  final stdout = StringBuffer();
  final stderr = StringBuffer();

  @override
  void writeStderr(String value) {
    stderr.write(value);
  }

  @override
  void writeStdout(String value) {
    stdout.write(value);
  }
}

CavernoRuntimeRunStarted _started({required int sequence}) {
  return CavernoRuntimeRunStarted(
    sequence: sequence,
    timestamp: DateTime.utc(2026),
    turnId: 'turn-1',
    surface: CavernoRuntimeSurface.terminal,
    mode: 'general',
    model: 'qwen',
    baseUrl: 'http://localhost:1234/v1',
    workspace: null,
    toolNames: const [],
    hidden: false,
  );
}
