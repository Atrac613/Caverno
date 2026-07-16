import '../../chat/application/runtime/caverno_runtime_event.dart';
import '../presentation/caverno_terminal_presenter.dart';
import 'caverno_cli_contract.dart';
import 'caverno_cli_input.dart';

abstract interface class CavernoTerminalDecisionPort {
  Future<void> resolveApproval({required String id, required bool approved});

  Future<void> resolveQuestion({required String id, String? answer});

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

    final target = request.target?.trim();
    if (target != null && target.isNotEmpty) {
      output.writeStderr('Target: $target\n');
    }
    if (request.rememberAllowed) {
      output.writeStderr('This action can be remembered by the application.\n');
    }
    output.writeStderr('Approve once? [y/N] ');
    final response = (await input.readLine())?.trim().toLowerCase();
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
    output.writeStderr('Answer: ');
    final answer = (await input.readLine())?.trim();
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
}
