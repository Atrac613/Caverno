import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/application/runtime/caverno_runtime_event.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/presentation/caverno_cli_redactor.dart';
import 'package:caverno/features/terminal/presentation/caverno_terminal_presenter.dart';

void main() {
  test('keeps human assistant output separate from diagnostics', () {
    final output = _RecordingOutput();
    final presenter = CavernoTerminalPresenter(
      outputMode: CavernoCliOutputMode.human,
      output: output,
    );

    presenter.present(_started(sequence: 1));
    presenter.present(
      CavernoRuntimeAssistantDelta(
        sequence: 2,
        timestamp: DateTime.utc(2026),
        turnId: 'turn-1',
        delta: 'Hello',
      ),
    );
    presenter.present(
      CavernoRuntimeToolLifecycle(
        sequence: 3,
        timestamp: DateTime.utc(2026),
        turnId: 'turn-1',
        toolCallId: 'tool-1',
        toolName: 'read_file',
        state: CavernoRuntimeToolLifecycleState.completed,
        loopIndex: 1,
        resultStatus: 'success',
      ),
    );
    presenter.present(
      CavernoRuntimeRunCompleted(
        sequence: 4,
        timestamp: DateTime.utc(2026),
        turnId: 'turn-1',
        content: 'Hello',
      ),
    );

    expect(output.stdout.toString(), 'Hello\n');
    expect(output.stderr.toString(), contains('model=qwen'));
    expect(output.stderr.toString(), contains('[tool] read_file'));
    expect(output.stdout.toString(), isNot(contains('[tool]')));
  });

  test('emits one redacted JSON object per runtime event', () {
    final output = _RecordingOutput();
    final presenter = CavernoTerminalPresenter(
      outputMode: CavernoCliOutputMode.json,
      output: output,
      redactor: CavernoCliRedactor(secrets: const ['secret-key']),
    );

    presenter.present(_started(sequence: 1));
    presenter.present(
      CavernoRuntimeApprovalRequired(
        sequence: 2,
        timestamp: DateTime.utc(2026),
        turnId: 'turn-1',
        request: const CavernoRuntimeApprovalRequest(
          id: 'approval-1',
          capability: 'command_execution',
          risk: CavernoRuntimeApprovalRisk.high,
          summary: 'curl -H "Authorization: secret-key" example.test',
        ),
      ),
    );

    final events = output.stdout
        .toString()
        .trim()
        .split('\n')
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);
    expect(events.map((event) => event['sequence']), [1, 2]);
    expect(
      events.every((event) => event['schema'] == 'caverno_cli_event'),
      isTrue,
    );
    expect(output.stdout.toString(), isNot(contains('secret-key')));
    expect(output.stderr, isEmpty);
  });
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
    frontendDiagnostics: const <String, String>{
      'approvalMode': 'manual',
      'outputMode': 'json',
    },
  );
}

final class _RecordingOutput implements CavernoTerminalOutputPort {
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
