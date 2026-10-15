import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import '../presentation/caverno_terminal_presenter.dart';
import 'caverno_cli_contract.dart';
import 'caverno_cli_input.dart';

abstract interface class CavernoTerminalDecisionPort {
  Future<void> resolveApproval({required String id, required bool approved});

  Future<void> resolveQuestion({required String id, String? answer});

  /// Completes once the interaction [id] is no longer pending, whoever
  /// answered it. A farm run also offers its approvals to a paired phone, and
  /// a prompt answered there must not keep waiting on this terminal.
  Future<void> settled(String id);

  Future<void> terminate({
    required String code,
    required String message,
    required int exitCode,
  });
}

final class CavernoTerminalInteractionController {
  CavernoTerminalInteractionController({
    required this.input,
    required this.output,
    required this.decisions,
    bool? interactive,
  }) : interactive = interactive ?? input.isTerminal;

  final CavernoCliInputPort input;
  final CavernoTerminalOutputPort output;
  final CavernoTerminalDecisionPort decisions;
  final bool interactive;
  final Set<String> _handledRequestIds = <String>{};

  /// The single outstanding stdin read; a second concurrent read would throw.
  Future<String?>? _pendingLine;

  /// Whether [_pendingLine] was started for a prompt answered elsewhere.
  bool _pendingLineIsStale = false;

  Future<void> handle(CavernoRuntimeEvent event) async {
    switch (event) {
      case CavernoRuntimeApprovalRequired():
        await _handleApproval(event.request);
      case CavernoRuntimeQuestionRequired():
        await _handleQuestion(event.request);
      default:
        return;
    }
  }

  Future<void> _handleApproval(CavernoRuntimeApprovalRequest request) async {
    if (!_handledRequestIds.add(request.id)) {
      return;
    }

    if (request.capability == 'computer_use') {
      await decisions.resolveApproval(id: request.id, approved: false);
      await decisions.terminate(
        code: 'computer_use_unavailable',
        message: 'Computer Use is unavailable from the terminal CLI.',
        exitCode: CavernoCliExitCode.approval,
      );
      return;
    }

    if (!interactive) {
      await decisions.resolveApproval(id: request.id, approved: false);
      await decisions.terminate(
        code: 'approval_unavailable',
        message:
            'Approval is required, but this run does not allow interactive prompts.',
        exitCode: CavernoCliExitCode.approval,
      );
      return;
    }

    final command = request.command?.trim();
    if (command != null && command.isNotEmpty) {
      output.writeStderr('Command: $command\n');
    }
    final target = request.target?.trim();
    if (target != null && target.isNotEmpty) {
      output.writeStderr('Target: $target\n');
    }
    if (request.rememberAllowed) {
      output.writeStderr('This action can be remembered by the application.\n');
    }
    final (line, settledElsewhere) = await _readAnswer(
      request.id,
      'Approve once? [y/N] ',
    );
    if (settledElsewhere) return;
    final response = line?.trim().toLowerCase();
    final approved = response == 'y' || response == 'yes';
    await decisions.resolveApproval(id: request.id, approved: approved);
    if (!approved) {
      await decisions.terminate(
        code: 'approval_denied',
        message: 'The requested action was denied.',
        exitCode: CavernoCliExitCode.approval,
      );
    }
  }

  Future<void> _handleQuestion(CavernoRuntimeQuestionRequest request) async {
    if (!_handledRequestIds.add(request.id)) {
      return;
    }

    if (!interactive) {
      await decisions.resolveQuestion(id: request.id);
      await decisions.terminate(
        code: 'question_unavailable',
        message:
            'A user answer is required, but this run does not allow interactive prompts.',
        exitCode: CavernoCliExitCode.blocked,
      );
      return;
    }

    for (var index = 0; index < request.options.length; index += 1) {
      output.writeStderr('  ${index + 1}) ${request.options[index]}\n');
    }
    final (line, settledElsewhere) = await _readAnswer(request.id, 'Answer: ');
    if (settledElsewhere) return;
    final answer = line?.trim();
    await decisions.resolveQuestion(
      id: request.id,
      answer: answer?.isEmpty == true ? null : answer,
    );
    if (answer == null || answer.isEmpty) {
      await decisions.terminate(
        code: 'question_cancelled',
        message: 'The required question was not answered.',
        exitCode: CavernoCliExitCode.blocked,
      );
    }
  }

  /// Prompts with [prompt] until a line arrives or [id] is settled elsewhere.
  ///
  /// A line typed for a prompt that was answered on another device arrives
  /// late, while the next prompt is showing. It is discarded rather than taken
  /// as that prompt's answer, so a "y" meant for one approval can never grant
  /// the next one.
  Future<(String?, bool)> _readAnswer(String id, String prompt) async {
    final settled = decisions.settled(id).then((_) => (null, true));
    while (true) {
      output.writeStderr(prompt);
      final stale = _pendingLineIsStale;
      final line = _pendingLine ??= input.readLine();
      final result = await Future.any<(String?, bool)>([
        line.then((value) => (value, false)),
        settled,
      ]);
      if (result.$2) {
        _pendingLineIsStale = true;
        output.writeStderr('\nAnswered on another device.\n');
        return result;
      }
      _pendingLine = null;
      _pendingLineIsStale = false;
      if (!stale) return result;
      output.writeStderr('Ignored input typed before this prompt.\n');
    }
  }
}
