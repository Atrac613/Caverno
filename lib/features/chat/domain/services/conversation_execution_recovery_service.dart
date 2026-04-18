import '../entities/conversation_workflow.dart';

enum ConversationExecutionRecoveryAction {
  retryValidation,
  replanValidationPath,
  editBlockedReason,
  replanBlockedTask,
}

class ConversationExecutionRecoverySuggestion {
  const ConversationExecutionRecoverySuggestion({
    required this.action,
    required this.reason,
  });

  final ConversationExecutionRecoveryAction action;
  final String reason;
}

class ConversationExecutionRecoveryService {
  ConversationExecutionRecoveryService._();

  static List<ConversationExecutionRecoverySuggestion> suggest({
    required ConversationWorkflowTask task,
    ConversationExecutionTaskProgress? progress,
  }) {
    if (progress == null) {
      return const [];
    }

    final suggestions = <ConversationExecutionRecoverySuggestion>[];
    final validationCommand = task.validationCommand.trim();
    final validationSummary =
        progress.normalizedValidationSummary ?? progress.normalizedSummary;
    final blockedReason = progress.normalizedBlockedReason;

    if (progress.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        validationCommand.isNotEmpty) {
      suggestions.add(
        ConversationExecutionRecoverySuggestion(
          action: ConversationExecutionRecoveryAction.retryValidation,
          reason:
              validationSummary ??
              'The saved validation step failed, so rerunning it is the fastest way to confirm the current state.',
        ),
      );
      suggestions.add(
        ConversationExecutionRecoverySuggestion(
          action: ConversationExecutionRecoveryAction.replanValidationPath,
          reason:
              blockedReason ??
              validationSummary ??
              'If the same validation keeps failing, narrow the next draft to the validation path before changing unrelated tasks.',
        ),
      );
    }

    if (progress.status == ConversationWorkflowTaskStatus.blocked) {
      suggestions.add(
        ConversationExecutionRecoverySuggestion(
          action: ConversationExecutionRecoveryAction.editBlockedReason,
          reason:
              blockedReason ??
              'Capture the blocker details so the next task run or replan has concrete context.',
        ),
      );
      suggestions.add(
        ConversationExecutionRecoverySuggestion(
          action: ConversationExecutionRecoveryAction.replanBlockedTask,
          reason:
              blockedReason ??
              'Use a narrow blocker-focused replan when the current task cannot move forward as written.',
        ),
      );
    }

    final emitted = <ConversationExecutionRecoveryAction>{};
    return suggestions.where((suggestion) {
      if (emitted.contains(suggestion.action)) {
        return false;
      }
      emitted.add(suggestion.action);
      return true;
    }).toList(growable: false);
  }
}
