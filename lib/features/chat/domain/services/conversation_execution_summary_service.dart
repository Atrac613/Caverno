import '../entities/conversation_workflow.dart';

class ConversationExecutionTaskSummary {
  const ConversationExecutionTaskSummary({
    this.lastOutcome,
    this.lastValidation,
    this.lastValidationCommand,
    this.blockedSince,
  });

  final String? lastOutcome;
  final String? lastValidation;
  final String? lastValidationCommand;
  final DateTime? blockedSince;
}

class ConversationExecutionSummaryService {
  ConversationExecutionSummaryService._();

  static ConversationExecutionTaskSummary summarize(
    ConversationExecutionTaskProgress? progress,
  ) {
    if (progress == null) {
      return const ConversationExecutionTaskSummary();
    }

    final events = progress.recentEvents;
    final latestEvent = events.isEmpty ? null : events.last;
    final latestValidationEvent = _lastEventOfType(
      events,
      ConversationExecutionTaskEventType.validated,
    );
    final blockedEvent =
        progress.status == ConversationWorkflowTaskStatus.blocked
        ? _lastEventOfType(events, ConversationExecutionTaskEventType.blocked)
        : null;

    return ConversationExecutionTaskSummary(
      lastOutcome:
          latestEvent?.normalizedSummary ??
          progress.normalizedSummary ??
          progress.normalizedBlockedReason,
      lastValidation: latestValidationEvent != null
          ? latestValidationEvent.normalizedValidationSummary ??
                latestValidationEvent.normalizedSummary
          : progress.normalizedValidationSummary,
      lastValidationCommand: latestValidationEvent != null
          ? latestValidationEvent.normalizedValidationCommand ??
                progress.normalizedValidationCommand
          : progress.normalizedValidationCommand,
      blockedSince: blockedEvent?.createdAt,
    );
  }

  static ConversationExecutionTaskEvent? _lastEventOfType(
    List<ConversationExecutionTaskEvent> events,
    ConversationExecutionTaskEventType type,
  ) {
    for (final event in events.reversed) {
      if (event.type == type) {
        return event;
      }
    }
    return null;
  }
}
