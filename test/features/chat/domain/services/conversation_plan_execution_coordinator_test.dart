import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_coordinator.dart';

void main() {
  test('buildTaskPrompt keeps task metadata in execution prompt order', () {
    final prompt = ConversationPlanExecutionCoordinator.buildTaskPrompt(
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Ship the next slice',
        targetFiles: ['lib/main.dart'],
        validationCommand: 'flutter test',
        notes: 'Keep the first cut narrow.',
      ),
      intro: 'Implement the saved task.',
      targetFilesLabel: 'Target files',
      validationLabel: 'Validation',
      notesLabel: 'Notes',
      outro: 'Reply with the implementation result.',
    );

    expect(prompt, contains('Implement the saved task.'));
    expect(prompt, contains('Saved task ID: task-1'));
    expect(prompt, contains('Target files: lib/main.dart'));
    expect(prompt, contains('Validation: flutter test'));
    expect(prompt, contains('Notes: Keep the first cut narrow.'));
    expect(
      prompt,
      contains(
        'Work only on this saved task. Do not implement future saved tasks.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not create or modify files outside the target files unless the saved validation step requires it.',
      ),
    );
    expect(
      prompt,
      contains(
        'Stop after the saved validation step and report that result before moving on.',
      ),
    );
    expect(prompt, contains('Reply with the implementation result.'));
  });

  test('buildBlockedTaskReplanContext preserves unrelated task ids', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: DateTime(2026, 4, 18, 14),
      updatedAt: DateTime(2026, 4, 18, 14, 5),
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Unblock the current task',
            status: ConversationWorkflowTaskStatus.blocked,
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Keep the next validation slice stable',
          ),
        ],
      ),
      executionProgress: const [
        ConversationExecutionTaskProgress(
          taskId: 'task-1',
          status: ConversationWorkflowTaskStatus.blocked,
          blockedReason: 'Validation is red.',
        ),
      ],
    );

    final context =
        ConversationPlanExecutionCoordinator.buildBlockedTaskReplanContext(
          conversation: conversation,
          task: conversation.projectedExecutionTasks.first,
          blockedReason: 'Validation is red.',
        );

    expect(context, contains('- blockedTask: Unblock the current task'));
    expect(context, contains('- blockedReason: Validation is red.'));
    expect(context, contains('- preserveTaskIds:'));
    expect(context, contains('task-2: Keep the next validation slice stable'));
  });

  test('buildAutoContinueTaskPrompt carries the next task metadata', () {
    const completedTask = ConversationWorkflowTask(
      id: 'task-1',
      title: 'Implement the ping utility',
    );
    const nextTask = ConversationWorkflowTask(
      id: 'task-2',
      title: 'Load the config file',
      targetFiles: ['src/config_loader.py', 'config/config.yaml'],
      validationCommand: 'pytest tests/test_config_loader.py',
      notes: 'Keep the initial loader synchronous.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildAutoContinueTaskPrompt(
          completedTask: completedTask,
          nextTask: nextTask,
        );

    expect(prompt, contains('Completed task ID: task-1'));
    expect(prompt, contains('Completed task: Implement the ping utility'));
    expect(prompt, contains('Next task ID: task-2'));
    expect(prompt, contains('Next task: Load the config file'));
    expect(
      prompt,
      contains('Target files: src/config_loader.py, config/config.yaml'),
    );
    expect(prompt, contains('Validation: pytest tests/test_config_loader.py'));
    expect(prompt, contains('Notes: Keep the initial loader synchronous.'));
    expect(
      prompt,
      contains(
        'Work only on this saved task. Do not implement future saved tasks.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not create or modify files outside the target files unless the saved validation step requires it.',
      ),
    );
    expect(
      prompt,
      contains(
        'Stop after the saved validation step and report that result before moving on.',
      ),
    );
    expect(
      prompt,
      contains(
        'Continue immediately with the next pending saved task without asking for confirmation.',
      ),
    );
  });

  test('buildTaskDriftRecoveryPrompt re-anchors the saved task', () {
    const task = ConversationWorkflowTask(
      id: 'task-2',
      title: 'Implement the YAML config loader',
      targetFiles: ['src/config_loader.py', 'tests/test_config_loader.py'],
      validationCommand: 'pytest tests/test_config_loader.py',
      notes: 'Parse the YAML host list only.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildTaskDriftRecoveryPrompt(
          task: task,
          unrelatedTouchedPaths: const ['pyproject.toml'],
          scaffoldCommands: const ['mkdir -p live_ping_cli'],
          alreadyTouchedTargetFiles: const ['src/config_loader.py'],
          repeatedTargetFiles: const ['src/config_loader.py'],
          remainingTargetFiles: const ['tests/test_config_loader.py'],
        );

    expect(prompt, contains('Saved task drift detected.'));
    expect(prompt, contains('Saved task: Implement the YAML config loader'));
    expect(
      prompt,
      contains(
        'Only touch these target files next: src/config_loader.py, tests/test_config_loader.py',
      ),
    );
    expect(prompt, contains('Ignore these unrelated paths: pyproject.toml'));
    expect(
      prompt,
      contains('You already updated these target files: src/config_loader.py'),
    );
    expect(
      prompt,
      contains(
        'Do not rewrite these target files again unless validation fails: src/config_loader.py',
      ),
    );
    expect(prompt, contains('Stop rewriting already-covered files.'));
    expect(
      prompt,
      contains(
        'Focus on the remaining target files next: tests/test_config_loader.py',
      ),
    );
    expect(
      prompt,
      contains(
        'Finish the remaining target files before making any other edits.',
      ),
    );
    expect(
      prompt,
      contains(
        'Ignore this unrelated scaffolding command: mkdir -p live_ping_cli',
      ),
    );
    expect(
      prompt,
      contains(
        'Your next action must directly modify one of the remaining target files or run the saved validation command.',
      ),
    );
    expect(
      prompt,
      contains(
        'If every target file is already covered, run the saved validation command now instead of rewriting files.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not implement future saved tasks while recovering this task.',
      ),
    );
  });

  test('validationTask prefers the active task before the pending queue', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: DateTime(2026, 4, 18, 15),
      updatedAt: DateTime(2026, 4, 18, 15, 5),
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Keep implementing',
            status: ConversationWorkflowTaskStatus.inProgress,
            validationCommand: 'flutter test',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Next task',
            validationCommand: 'dart test',
          ),
        ],
      ),
    );

    final validationTask = ConversationPlanExecutionCoordinator.validationTask(
      conversation,
    );

    expect(validationTask?.id, 'task-1');
  });
}
