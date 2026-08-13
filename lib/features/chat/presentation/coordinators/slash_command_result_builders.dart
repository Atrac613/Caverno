import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_catalog.dart';

typedef ProReasoningSlashCommandHandler = bool Function(String question);

SlashCommandExecutionResult buildProReasoningSlashCommandResult({
  required bool isCodingWorkspace,
  required String args,
  required ProReasoningSlashCommandHandler startProReasoning,
  required SlashCommandTextResolver text,
}) {
  if (isCodingWorkspace) {
    return SlashCommandExecutionResult.keepInput(
      feedbackMessage: text('chat.slash_pro_unavailable'),
    );
  }
  final question = args.trim();
  if (question.isEmpty) {
    return SlashCommandExecutionResult.keepInput(
      feedbackMessage: text('chat.slash_pro_question_required'),
    );
  }
  if (!startProReasoning(question)) {
    return SlashCommandExecutionResult.keepInput(
      feedbackMessage: text('chat.slash_pro_busy'),
    );
  }
  return SlashCommandExecutionResult(
    feedbackMessage: text('chat.slash_pro_started'),
  );
}

SlashCommandExecutionResult buildSlashModeChangedResult(
  SlashCommandTextResolver text,
  String modeKey,
) => SlashCommandExecutionResult(
  feedbackMessage: text(
    'chat.slash_mode_changed',
    namedArgs: {'mode': text(modeKey)},
  ),
);
