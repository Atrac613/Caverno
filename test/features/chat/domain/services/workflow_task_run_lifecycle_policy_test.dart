import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkflowTaskRunLifecyclePolicy', () {
    test('allows depth seven and stops at depth eight', () {
      final conversation = _conversation(const [
        ConversationWorkflowTask(
          id: 'completed',
          title: 'Completed',
          status: ConversationWorkflowTaskStatus.completed,
        ),
        ConversationWorkflowTask(id: 'next', title: 'Next'),
      ]);

      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: conversation,
          completedTaskId: 'completed',
          continuationDepth: 7,
        )?.nextTask.id,
        'next',
      );
      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: conversation,
          completedTaskId: 'completed',
          continuationDepth: 8,
        ),
        isNull,
      );
      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: conversation,
          completedTaskId: 'completed',
          continuationDepth: -1,
        ),
        isNotNull,
      );
    });

    test('requires the refreshed current task to be completed', () {
      for (final status in [
        ConversationWorkflowTaskStatus.pending,
        ConversationWorkflowTaskStatus.inProgress,
        ConversationWorkflowTaskStatus.blocked,
      ]) {
        final conversation = _conversation([
          ConversationWorkflowTask(
            id: 'current',
            title: 'Current',
            status: status,
          ),
          const ConversationWorkflowTask(id: 'next', title: 'Next'),
        ]);

        expect(
          WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
            conversation: conversation,
            completedTaskId: 'current',
            continuationDepth: 0,
          ),
          isNull,
          reason: status.name,
        );
      }

      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: _conversation(const [
            ConversationWorkflowTask(id: 'next', title: 'Next'),
          ]),
          completedTaskId: 'missing',
          continuationDepth: 0,
        ),
        isNull,
      );
    });

    test('selects an in-progress task before an earlier pending task', () {
      final selection = WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
        conversation: _conversation(const [
          ConversationWorkflowTask(
            id: 'completed',
            title: 'Completed',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          ConversationWorkflowTask(id: 'pending', title: 'Pending'),
          ConversationWorkflowTask(
            id: 'active',
            title: 'Active',
            status: ConversationWorkflowTaskStatus.inProgress,
          ),
        ]),
        completedTaskId: 'completed',
        continuationDepth: 0,
      );

      expect(selection?.completedTask.id, 'completed');
      expect(selection?.nextTask.id, 'active');
    });

    test('selects the first pending task when no task is active', () {
      final selection = WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
        conversation: _conversation(const [
          ConversationWorkflowTask(
            id: 'completed',
            title: 'Completed',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          ConversationWorkflowTask(id: 'first', title: 'First'),
          ConversationWorkflowTask(id: 'second', title: 'Second'),
        ]),
        completedTaskId: 'completed',
        continuationDepth: 0,
      );

      expect(selection?.nextTask.id, 'first');
    });

    test('rejects missing and same-ID next tasks', () {
      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: _conversation(const [
            ConversationWorkflowTask(
              id: 'completed',
              title: 'Completed',
              status: ConversationWorkflowTaskStatus.completed,
            ),
          ]),
          completedTaskId: 'completed',
          continuationDepth: 0,
        ),
        isNull,
      );
      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: _conversation(const [
            ConversationWorkflowTask(
              id: 'duplicate',
              title: 'Completed',
              status: ConversationWorkflowTaskStatus.completed,
            ),
            ConversationWorkflowTask(id: 'duplicate', title: 'Pending'),
          ]),
          completedTaskId: 'duplicate',
          continuationDepth: 0,
        ),
        isNull,
      );
    });

    test('treats only completed and blocked statuses as terminal', () {
      expect(
        WorkflowTaskRunLifecyclePolicy.isTerminalStatus(
          ConversationWorkflowTaskStatus.completed,
        ),
        isTrue,
      );
      expect(
        WorkflowTaskRunLifecyclePolicy.isTerminalStatus(
          ConversationWorkflowTaskStatus.blocked,
        ),
        isTrue,
      );
      for (final status in [
        null,
        ConversationWorkflowTaskStatus.pending,
        ConversationWorkflowTaskStatus.inProgress,
      ]) {
        expect(
          WorkflowTaskRunLifecyclePolicy.isTerminalStatus(status),
          isFalse,
          reason: status?.name ?? 'null',
        );
      }
    });
  });
}

Conversation _conversation(List<ConversationWorkflowTask> tasks) {
  final now = DateTime(2026, 7, 18);
  return Conversation(
    id: 'conversation',
    title: 'Lifecycle policy test',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workflowSpec: ConversationWorkflowSpec(tasks: tasks),
  );
}
