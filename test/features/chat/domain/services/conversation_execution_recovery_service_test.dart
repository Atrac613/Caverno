import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_execution_recovery_service.dart';

void main() {
  test('suggests validation retry and replan actions after a failed check', () {
    final suggestions = ConversationExecutionRecoveryService.suggest(
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Validate the current slice',
        validationCommand: 'flutter test',
      ),
      progress: const ConversationExecutionTaskProgress(
        taskId: 'task-1',
        status: ConversationWorkflowTaskStatus.inProgress,
        validationStatus: ConversationExecutionValidationStatus.failed,
        lastValidationSummary: 'The smoke suite is still failing.',
      ),
    );

    expect(
      suggestions.map((item) => item.action),
      containsAll([
        ConversationExecutionRecoveryAction.retryValidation,
        ConversationExecutionRecoveryAction.replanValidationPath,
      ]),
    );
  });

  test('suggests blocker editing and blocker-focused replan actions', () {
    final suggestions = ConversationExecutionRecoveryService.suggest(
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Unblock the approved plan',
      ),
      progress: const ConversationExecutionTaskProgress(
        taskId: 'task-1',
        status: ConversationWorkflowTaskStatus.blocked,
        blockedReason: 'The saved validation path is no longer reliable.',
      ),
    );

    expect(
      suggestions.map((item) => item.action),
      containsAll([
        ConversationExecutionRecoveryAction.editBlockedReason,
        ConversationExecutionRecoveryAction.replanBlockedTask,
      ]),
    );
  });
}
