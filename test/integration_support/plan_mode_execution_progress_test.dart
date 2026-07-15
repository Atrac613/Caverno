import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

import '../../integration_test/test_support/plan_mode_execution_progress.dart';
import '../../integration_test/test_support/plan_mode_heartbeat.dart';

void main() {
  Conversation buildConversation({
    List<ConversationWorkflowTask> tasks = const [],
  }) {
    return Conversation(
      id: 'conversation-1',
      title: 'Execution progress',
      messages: const [],
      createdAt: DateTime(2026, 4, 23, 12),
      updatedAt: DateTime(2026, 4, 23, 12),
      workflowStage: ConversationWorkflowStage.tasks,
      workflowSpec: ConversationWorkflowSpec(tasks: tasks),
    );
  }

  group('executionLogsContainWorkflowCompleted', () {
    test('detects English all-tasks-complete markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The validation passed.',
          'All planned tasks are complete.',
        ]),
        isTrue,
      );
    });

    test('detects Japanese all-tasks-complete markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'タスク「Verify ping execution with localhost」が完了しました。',
          'すべての予定されていたタスクが完了しました。',
        ]),
        isTrue,
      );
    });

    test('ignores single-task completion without workflow completion', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The task is complete.',
          'Continue immediately with the next pending saved task.',
        ]),
        isFalse,
      );
    });

    test('detects terminal task completion before final answer streaming', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
          'The task "Create test_ping.py to validate the CLI" has been completed successfully.',
          '[Tool] Resending tool results as user message',
          '[LLM] ========== streamChatCompletion ==========',
        ]),
        isTrue,
      );
    });

    test(
      'detects final task completion when the final answer request repeats the handoff prompt',
      () {
        expect(
          executionLogsContainWorkflowCompleted(const <String>[
            'The task "Verify the CLI tool by pinging 8.8.8.8" has been completed successfully.',
            '[Tool] Resending tool results as user message',
            '[LLM] ========== streamChatCompletion ==========',
            'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
          ]),
          isTrue,
        );
      },
    );

    test('detects all-tasks-in-plan completion markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'Task 16901b8a-0a8e-4304-b54d-12d9850a7968 has been completed successfully.',
          'All tasks in the plan have been completed.',
        ]),
        isTrue,
      );
    });

    test('detects all-tasks-in-current-plan completion markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'I have completed the task of adding a `README.md` with usage instructions.',
          'All tasks in the current plan are now complete.',
        ]),
        isTrue,
      );
    });

    test('ignores mid-workflow completion followed by another handoff', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The task "Create README.md with usage instructions" is complete.',
          '[Tool] Resending tool results as user message',
          'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
        ]),
        isFalse,
      );
    });
  });

  group('executionLogsContainLateValidationAnswerProgress', () {
    test('detects final answer progress after a successful validation', () {
      expect(
        executionLogsContainLateValidationAnswerProgress(const <String>[
          '[LLM] {"command":"python3 main.py --help","exit_code":0,"stdout":"usage"}',
          '[Tool] Resending tool results as user message',
          '[LLM] ========== streamChatCompletion ==========',
        ]),
        isTrue,
      );
    });

    test('ignores answer streaming without a successful validation first', () {
      expect(
        executionLogsContainLateValidationAnswerProgress(const <String>[
          '[Tool] Resending tool results as user message',
          '[LLM] ========== streamChatCompletion ==========',
        ]),
        isFalse,
      );
    });
  });

  group('executionTasksContainOnlyCompleted', () {
    test('accepts non-empty workflows where every task is completed', () {
      expect(
        executionTasksContainOnlyCompleted([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create README.md',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          const ConversationWorkflowTask(
            id: 'task-2',
            title: 'Verify localhost ping',
            status: ConversationWorkflowTaskStatus.completed,
          ),
        ]),
        isTrue,
      );
    });

    test('rejects empty workflows and incomplete task lists', () {
      expect(executionTasksContainOnlyCompleted(const []), isFalse);
      expect(
        executionTasksContainOnlyCompleted([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create README.md',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          const ConversationWorkflowTask(
            id: 'task-2',
            title: 'Verify localhost ping',
            status: ConversationWorkflowTaskStatus.inProgress,
          ),
        ]),
        isFalse,
      );
    });
  });

  group('activePlanModeWorkflowTaskTitle', () {
    test('prefers in-progress, blocked, pending, then the last task', () {
      expect(
        activePlanModeWorkflowTaskTitle([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Completed task',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          const ConversationWorkflowTask(
            id: 'task-2',
            title: 'In-progress task',
            status: ConversationWorkflowTaskStatus.inProgress,
          ),
          const ConversationWorkflowTask(
            id: 'task-3',
            title: 'Blocked task',
            status: ConversationWorkflowTaskStatus.blocked,
          ),
        ]),
        'In-progress task',
      );
      expect(
        activePlanModeWorkflowTaskTitle([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Completed task',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          const ConversationWorkflowTask(
            id: 'task-2',
            title: 'Blocked task',
            status: ConversationWorkflowTaskStatus.blocked,
          ),
          const ConversationWorkflowTask(
            id: 'task-3',
            title: 'Pending task',
            status: ConversationWorkflowTaskStatus.pending,
          ),
        ]),
        'Blocked task',
      );
      expect(
        activePlanModeWorkflowTaskTitle([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Completed task',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          const ConversationWorkflowTask(
            id: 'task-2',
            title: 'Pending task',
            status: ConversationWorkflowTaskStatus.pending,
          ),
        ]),
        'Pending task',
      );
      expect(
        activePlanModeWorkflowTaskTitle([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Completed task',
            status: ConversationWorkflowTaskStatus.completed,
          ),
        ]),
        'Completed task',
      );
      expect(activePlanModeWorkflowTaskTitle(const []), isNull);
    });
  });

  group('plan mode execution log counts', () {
    test('counts content tool, file write, and validation-like events', () {
      const logs = <String>[
        '[ContentTool] Appended result to message',
        '[McpToolService] Executing tool: write_file',
        '[McpToolService] Executing tool: edit_file',
        '[McpToolService] Executing tool: rollback_last_file_change',
        '[McpToolService] Executing tool: local_execute_command',
        '[McpToolService] Executing tool: run_tests',
        '[McpToolService] Executing tool: read_file',
        '[Tool] Lifecycle {"lifecycleState":"completed"}',
        '[Tool] Lifecycle {"lifecycleState":"skipped"}',
        '[Tool] Lifecycle {"lifecycleState":"started"}',
        '[LLM] === Response ===',
      ];

      expect(countPlanModeContentToolResults(logs), 1);
      expect(countPlanModeFileWriteExecutions(logs), 3);
      expect(countPlanModeValidationLikeExecutions(logs), 2);
      expect(countPlanModeExecutionActivities(logs), 3);
    });
  });

  group('resolvePlanModeExecutionSubphase', () {
    test('resolves validation, next task, saved task, and fallback phases', () {
      final now = DateTime(2026, 4, 23, 12);

      expect(
        resolvePlanModeExecutionSubphase(
          PlanModePhaseTrace()..validationStartedAt = now,
          'Validate CLI',
        ),
        'validation',
      );
      expect(
        resolvePlanModeExecutionSubphase(
          PlanModePhaseTrace()..nextTaskStartedAt = now,
          'Validate CLI',
        ),
        'nextTask',
      );
      expect(
        resolvePlanModeExecutionSubphase(
          PlanModePhaseTrace()..firstTaskStartedAt = now,
          'Create CLI',
        ),
        'savedTask',
      );
      expect(
        resolvePlanModeExecutionSubphase(
          PlanModePhaseTrace()..firstTaskStartedAt = now,
          null,
        ),
        'execution',
      );
      expect(
        resolvePlanModeExecutionSubphase(PlanModePhaseTrace(), null),
        'execution',
      );
    });
  });

  group('summarizePlanModeWorkflowTasks', () {
    test('summarizes task titles and statuses', () {
      expect(summarizePlanModeWorkflowTasks(const []), 'none');
      expect(
        summarizePlanModeWorkflowTasks([
          const ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create CLI',
            status: ConversationWorkflowTaskStatus.completed,
          ),
          const ConversationWorkflowTask(
            id: 'task-2',
            title: 'Validate CLI',
            status: ConversationWorkflowTaskStatus.inProgress,
          ),
        ]),
        'Create CLI:completed, Validate CLI:inProgress',
      );
    });
  });

  group('shouldRecoverExecutionFromExecutionDocument', () {
    test('recovers execution after approval when tasks are still empty', () {
      final conversation = buildConversation().copyWith(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Create a Python CLI ping tool\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Implement ping_cli.py\n'
              '   - Status: inProgress\n',
        ),
      );

      expect(
        shouldRecoverExecutionFromExecutionDocument(
          conversation: conversation,
          isLoading: false,
          hasPendingApprovals: false,
          approvalTappedAt: DateTime(2026, 4, 23, 12, 5),
        ),
        isTrue,
      );
    });

    test('does not recover before approval is tapped', () {
      final conversation = buildConversation().copyWith(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Create a Python CLI ping tool\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Implement ping_cli.py\n'
              '   - Status: inProgress\n',
        ),
      );

      expect(
        shouldRecoverExecutionFromExecutionDocument(
          conversation: conversation,
          isLoading: false,
          hasPendingApprovals: false,
          approvalTappedAt: null,
        ),
        isFalse,
      );
    });
  });
}
