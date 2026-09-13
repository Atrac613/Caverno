import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/task_lifecycle_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _projection = TaskLifecycleProjection();

Conversation _conversation({
  ConversationWorkflowTaskStatus status = ConversationWorkflowTaskStatus.pending,
  ConversationExecutionValidationStatus? validationStatus,
  ConversationWorkflowTaskStatus? progressStatus,
  bool accepted = false,
  String validationCommand = 'dart test',
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Plan thread',
    messages: const <Message>[],
    createdAt: DateTime(2026, 9, 13),
    updatedAt: DateTime(2026, 9, 13),
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Add the CLI flags',
          validationCommand: validationCommand,
          status: status,
        ),
      ],
    ),
    executionProgress: [
      if (progressStatus != null || validationStatus != null)
        ConversationExecutionTaskProgress(
          taskId: 'task-1',
          status: progressStatus ?? status,
          validationStatus:
              validationStatus ?? ConversationExecutionValidationStatus.unknown,
        ),
    ],
    taskAcceptances: [
      if (accepted)
        ConversationTaskAcceptance(
          taskId: 'task-1',
          acceptedAt: DateTime(2026, 9, 13),
          rationale: 'The saved command passed and the output matches.',
        ),
    ],
  );
}

ConversationWorkflowTask _task(Conversation conversation) =>
    conversation.effectiveWorkflowSpec.tasks.single;

void main() {
  test('a finished task with no passing check is produced, not verified', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.completed,
    );

    expect(
      _projection.of(conversation, _task(conversation)),
      TaskLifecycleState.produced,
      reason:
          'A child saying done means produced. Nothing has confirmed it yet.',
    );
  });

  test('a passing validation promotes it to verified, never to accepted', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.completed,
      validationStatus: ConversationExecutionValidationStatus.passed,
    );

    expect(
      _projection.of(conversation, _task(conversation)),
      TaskLifecycleState.verified,
    );
  });

  test('only a recorded acceptance reads as accepted', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.completed,
      validationStatus: ConversationExecutionValidationStatus.passed,
      accepted: true,
    );

    expect(
      _projection.of(conversation, _task(conversation)),
      TaskLifecycleState.accepted,
    );
  });

  test('an acceptance outranks a status that was edited afterwards', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.pending,
      accepted: true,
    );

    expect(
      _projection.of(conversation, _task(conversation)),
      TaskLifecycleState.accepted,
      reason:
          'The judgement was recorded against evidence; reopening the task does '
          'not unmake it.',
    );
  });

  test('execution progress outranks the spec status', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.pending,
      progressStatus: ConversationWorkflowTaskStatus.inProgress,
    );

    expect(
      _projection.of(conversation, _task(conversation)),
      TaskLifecycleState.inProgress,
    );
  });

  test('a task with nothing to check still only reaches produced', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.completed,
      validationCommand: '',
    );

    expect(
      _projection.of(conversation, _task(conversation)),
      TaskLifecycleState.produced,
      reason:
          'Owing nothing mechanically is not the same as having proved '
          'something.',
    );
  });

  test('names every saved task by id', () {
    final conversation = _conversation(
      status: ConversationWorkflowTaskStatus.completed,
      validationStatus: ConversationExecutionValidationStatus.passed,
    );

    expect(_projection.namesByTaskId(conversation), {'task-1': 'verified'});
  });
}
