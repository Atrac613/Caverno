import 'dart:async';

import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_cli_input.dart';
import 'package:caverno/features/terminal/application/caverno_terminal_interaction_controller.dart';
import 'package:caverno/features/terminal/presentation/caverno_terminal_presenter.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CavernoTerminalInteractionController', () {
    for (final capability in const [
      'command_execution',
      'git_mutation',
      'file_mutation',
      'browser_action',
    ]) {
      test('approves interactive $capability once', () async {
        final decisions = _RecordingDecisions();
        final controller = CavernoTerminalInteractionController(
          input: _LineInput(isTerminal: true, lines: ['yes']),
          output: _RecordingOutput(),
          decisions: decisions,
        );

        await controller.handle(_approval(capability: capability));

        expect(decisions.approvals, [('approval-1', true)]);
        expect(decisions.terminations, isEmpty);
      });
    }

    test('shows the exact command beside the model reason', () async {
      final output = _RecordingOutput();
      final controller = CavernoTerminalInteractionController(
        input: _LineInput(isTerminal: true, lines: ['n']),
        output: output,
        decisions: _RecordingDecisions(),
      );

      await controller.handle(
        _approval(
          capability: 'command_execution',
          command: 'python3 -m unittest; rm -rf build',
        ),
      );

      expect(
        output.stderr.toString(),
        contains('Command: python3 -m unittest; rm -rf build\n'),
      );
    });

    test('stops waiting once a phone answers the approval', () async {
      final input = _TypedInput();
      final output = _RecordingOutput();
      final decisions = _RecordingDecisions();
      final controller = CavernoTerminalInteractionController(
        input: input,
        output: output,
        decisions: decisions,
      );

      final handled = controller.handle(_approval(capability: 'file_mutation'));
      await pumpEventQueue();
      decisions.settledElsewhere['approval-1']!.complete();
      await handled;

      expect(decisions.approvals, isEmpty);
      expect(decisions.terminations, isEmpty);
      expect(output.stderr.toString(), contains('Answered on another device.'));
    });

    test('never lets a late answer grant the next approval', () async {
      final input = _TypedInput();
      final output = _RecordingOutput();
      final decisions = _RecordingDecisions();
      final controller = CavernoTerminalInteractionController(
        input: input,
        output: output,
        decisions: decisions,
      );

      final first = controller.handle(_approval(capability: 'file_mutation'));
      await pumpEventQueue();
      decisions.settledElsewhere['approval-1']!.complete();
      await first;
      final second = controller.handle(
        _approval(capability: 'command_execution', id: 'approval-2'),
      );
      await pumpEventQueue();
      // Typed for the first prompt, arriving while the second one shows.
      input.type('y');
      await pumpEventQueue();
      expect(decisions.approvals, isEmpty);
      expect(input.reads, 1);
      input.type('y');
      await second;

      expect(decisions.approvals, [('approval-2', true)]);
      expect(
        output.stderr.toString(),
        contains('Ignored input typed before this prompt.'),
      );
    });

    test('fails closed for a non-interactive approval', () async {
      final decisions = _RecordingDecisions();
      final controller = CavernoTerminalInteractionController(
        input: _LineInput(isTerminal: false),
        output: _RecordingOutput(),
        decisions: decisions,
      );

      await controller.handle(_approval(capability: 'file_mutation'));

      expect(decisions.approvals, [('approval-1', false)]);
      expect(
        decisions.terminations.single.exitCode,
        CavernoCliExitCode.approval,
      );
      expect(decisions.terminations.single.code, 'approval_unavailable');
    });

    test('fails closed when prompts are disabled for a TTY run', () async {
      final decisions = _RecordingDecisions();
      final output = _RecordingOutput();
      final controller = CavernoTerminalInteractionController(
        input: _LineInput(isTerminal: true, lines: ['yes']),
        output: output,
        decisions: decisions,
        interactive: false,
      );

      await controller.handle(_approval(capability: 'file_mutation'));

      expect(decisions.approvals, [('approval-1', false)]);
      expect(decisions.terminations.single.code, 'approval_unavailable');
      expect(output.stderr.toString(), isNot(contains('Approve once?')));
    });

    test('rejects Computer Use even when a TTY is available', () async {
      final decisions = _RecordingDecisions();
      final controller = CavernoTerminalInteractionController(
        input: _LineInput(isTerminal: true, lines: ['yes']),
        output: _RecordingOutput(),
        decisions: decisions,
      );

      await controller.handle(_approval(capability: 'computer_use'));

      expect(decisions.approvals, [('approval-1', false)]);
      expect(decisions.terminations.single.code, 'computer_use_unavailable');
    });

    test(
      'returns an interactive answer and ignores duplicate events',
      () async {
        final decisions = _RecordingDecisions();
        final controller = CavernoTerminalInteractionController(
          input: _LineInput(isTerminal: true, lines: ['2']),
          output: _RecordingOutput(),
          decisions: decisions,
        );
        final event = CavernoRuntimeQuestionRequired(
          sequence: 1,
          timestamp: DateTime.utc(2026),
          turnId: 'turn-1',
          request: const CavernoRuntimeQuestionRequest(
            id: 'question-1',
            prompt: 'Choose',
            options: ['One', 'Two'],
          ),
        );

        await controller.handle(event);
        await controller.handle(event);

        expect(decisions.questions, [('question-1', '2')]);
      },
    );
  });
}

CavernoRuntimeApprovalRequired _approval({
  required String capability,
  String id = 'approval-1',
  String? command,
}) {
  return CavernoRuntimeApprovalRequired(
    sequence: 1,
    timestamp: DateTime.utc(2026),
    turnId: 'turn-1',
    request: CavernoRuntimeApprovalRequest(
      id: id,
      capability: capability,
      risk: CavernoRuntimeApprovalRisk.high,
      summary: 'Perform the action',
      target: '/tmp/project',
      command: command,
      rememberAllowed: true,
    ),
  );
}

final class _LineInput implements CavernoCliInputPort {
  _LineInput({required this.isTerminal, List<String> lines = const []})
    : _lines = List<String>.from(lines);

  @override
  final bool isTerminal;
  final List<String> _lines;

  @override
  Future<String> readFile(String path) => throw UnimplementedError();

  @override
  Future<String?> readLine() async =>
      _lines.isEmpty ? null : _lines.removeAt(0);

  @override
  Future<String> readToEnd() => throw UnimplementedError();
}

/// Lines the test types one at a time, after the prompt is already waiting.
final class _TypedInput implements CavernoCliInputPort {
  final _waiting = <Completer<String?>>[];

  void type(String line) => _waiting.removeAt(0).complete(line);

  int get reads => _waiting.length;

  @override
  bool get isTerminal => true;

  @override
  Future<String> readFile(String path) => throw UnimplementedError();

  @override
  Future<String?> readLine() {
    final line = Completer<String?>();
    _waiting.add(line);
    return line.future;
  }

  @override
  Future<String> readToEnd() => throw UnimplementedError();
}

final class _RecordingOutput implements CavernoTerminalOutputPort {
  final stderr = StringBuffer();

  @override
  void writeStderr(String value) {
    stderr.write(value);
  }

  @override
  void writeStdout(String value) {}
}

final class _RecordingDecisions implements CavernoTerminalDecisionPort {
  final approvals = <(String, bool)>[];
  final questions = <(String, String?)>[];
  final terminations = <({String code, String message, int exitCode})>[];
  final settledElsewhere = <String, Completer<void>>{};

  @override
  Future<void> settled(String id) =>
      (settledElsewhere[id] ??= Completer<void>()).future;

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
  }
}
