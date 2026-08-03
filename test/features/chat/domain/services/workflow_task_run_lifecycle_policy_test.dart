import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkflowTaskRunLifecyclePolicy', () {
    test('allows depth seven and stops at depth eight', () {
      final conversation = _conversation(
        const [
          ConversationWorkflowTask(
            id: 'completed',
            title: 'Completed',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          ConversationWorkflowTask(id: 'next', title: 'Next'),
        ],
        progress: const [_completedProgress],
      );

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
        final conversation = _conversation(
          const [
            ConversationWorkflowTask(
              id: 'current',
              title: 'Current',
              status: ConversationWorkflowTaskStatus.completed,
            ),
            ConversationWorkflowTask(id: 'next', title: 'Next'),
          ],
          progress: [
            ConversationExecutionTaskProgress(
              taskId: 'current',
              status: status,
            ),
          ],
        );

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

    test('requires progress completion instead of authored completion', () {
      final legacyCompleted = _conversation(const [
        ConversationWorkflowTask(
          id: 'current',
          title: 'Current',
          status: ConversationWorkflowTaskStatus.completed,
        ),
        ConversationWorkflowTask(id: 'next', title: 'Next'),
      ]);

      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: legacyCompleted,
          completedTaskId: 'current',
          continuationDepth: 0,
        ),
        isNull,
      );

      final progressCompleted = _conversation(
        const [
          ConversationWorkflowTask(id: 'current', title: 'Current'),
          ConversationWorkflowTask(id: 'next', title: 'Next'),
        ],
        progress: const [
          ConversationExecutionTaskProgress(
            taskId: 'current',
            status: ConversationWorkflowTaskStatus.completed,
          ),
        ],
      );
      final selection = WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
        conversation: progressCompleted,
        completedTaskId: 'current',
        continuationDepth: 0,
      );

      expect(selection?.completedTask.id, 'current');
      expect(
        selection?.completedTask.status,
        ConversationWorkflowTaskStatus.completed,
      );
      expect(selection?.nextTask.id, 'next');
    });

    test('selects an in-progress task before an earlier pending task', () {
      final selection = WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
        conversation: _conversation(
          const [
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
          ],
          progress: const [
            _completedProgress,
            ConversationExecutionTaskProgress(
              taskId: 'active',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
        completedTaskId: 'completed',
        continuationDepth: 0,
      );

      expect(selection?.completedTask.id, 'completed');
      expect(selection?.nextTask.id, 'active');
    });

    test('selects the first pending task when no task is active', () {
      final selection = WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
        conversation: _conversation(
          const [
            ConversationWorkflowTask(
              id: 'completed',
              title: 'Completed',
              status: ConversationWorkflowTaskStatus.completed,
            ),
            ConversationWorkflowTask(id: 'first', title: 'First'),
            ConversationWorkflowTask(id: 'second', title: 'Second'),
          ],
          progress: const [_completedProgress],
        ),
        completedTaskId: 'completed',
        continuationDepth: 0,
      );

      expect(selection?.nextTask.id, 'first');
    });

    test('rejects missing and same-ID next tasks', () {
      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: _conversation(
            const [
              ConversationWorkflowTask(
                id: 'completed',
                title: 'Completed',
                status: ConversationWorkflowTaskStatus.completed,
              ),
            ],
            progress: const [_completedProgress],
          ),
          completedTaskId: 'completed',
          continuationDepth: 0,
        ),
        isNull,
      );
      expect(
        WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
          conversation: _conversation(
            const [
              ConversationWorkflowTask(
                id: 'duplicate',
                title: 'Completed',
                status: ConversationWorkflowTaskStatus.completed,
              ),
              ConversationWorkflowTask(id: 'duplicate', title: 'Pending'),
            ],
            progress: const [
              ConversationExecutionTaskProgress(
                taskId: 'duplicate',
                status: ConversationWorkflowTaskStatus.completed,
              ),
            ],
          ),
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

const _completedProgress = ConversationExecutionTaskProgress(
  taskId: 'completed',
  status: ConversationWorkflowTaskStatus.completed,
);

Conversation _conversation(
  List<ConversationWorkflowTask> tasks, {
  List<ConversationExecutionTaskProgress> progress = const [],
}) {
  final now = DateTime(2026, 7, 18);
  return Conversation(
    id: 'conversation',
    title: 'Lifecycle policy test',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workflowSpec: ConversationWorkflowSpec(tasks: tasks),
    executionProgress: progress,
  );
}
