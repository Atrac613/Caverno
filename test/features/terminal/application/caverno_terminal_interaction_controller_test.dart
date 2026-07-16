import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/application/runtime/caverno_runtime_event.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_cli_input.dart';
import 'package:caverno/features/terminal/application/caverno_terminal_interaction_controller.dart';
import 'package:caverno/features/terminal/presentation/caverno_terminal_presenter.dart';

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

CavernoRuntimeApprovalRequired _approval({required String capability}) {
  return CavernoRuntimeApprovalRequired(
    sequence: 1,
    timestamp: DateTime.utc(2026),
    turnId: 'turn-1',
    request: CavernoRuntimeApprovalRequest(
      id: 'approval-1',
      capability: capability,
      risk: CavernoRuntimeApprovalRisk.high,
      summary: 'Perform the action',
      target: '/tmp/project',
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
