import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_execution_summary_service.dart';

void main() {
  test('summarize prefers the latest execution event for the outcome', () {
    final progress = ConversationExecutionTaskProgress(
      taskId: 'task-1',
      status: ConversationWorkflowTaskStatus.inProgress,
      summary: 'Older summary',
      events: [
        ConversationExecutionTaskEvent(
          type: ConversationExecutionTaskEventType.started,
          createdAt: DateTime(2026, 4, 18, 9, 0),
          summary: 'Started the task',
        ),
        ConversationExecutionTaskEvent(
          type: ConversationExecutionTaskEventType.replanned,
          createdAt: DateTime(2026, 4, 18, 9, 5),
          summary: 'Adjusted the execution order',
        ),
      ],
    );

    final summary = ConversationExecutionSummaryService.summarize(progress);

    expect(summary.lastOutcome, 'Adjusted the execution order');
  });

  test('summarize returns validation detail and blocked timestamp', () {
    final progress = ConversationExecutionTaskProgress(
      taskId: 'task-1',
      status: ConversationWorkflowTaskStatus.blocked,
      validationStatus: ConversationExecutionValidationStatus.failed,
      lastValidationCommand: 'flutter test',
      lastValidationSummary: 'A failing validation remained',
      events: [
        ConversationExecutionTaskEvent(
          type: ConversationExecutionTaskEventType.validated,
          createdAt: DateTime(2026, 4, 18, 9, 10),
          validationCommand: 'flutter test',
          validationSummary: 'Widget smoke failed',
        ),
        ConversationExecutionTaskEvent(
          type: ConversationExecutionTaskEventType.blocked,
          createdAt: DateTime(2026, 4, 18, 9, 12),
          blockedReason: 'Waiting for the failing test to be fixed',
        ),
      ],
    );

    final summary = ConversationExecutionSummaryService.summarize(progress);

    expect(summary.lastValidationCommand, 'flutter test');
    expect(summary.lastValidation, 'Widget smoke failed');
    expect(summary.blockedSince, DateTime(2026, 4, 18, 9, 12));
  });
}
