import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/task_lifecycle_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _projection = TaskLifecycleProjection();

Conversation _conversation({
  ConversationWorkflowTaskStatus status =
      ConversationWorkflowTaskStatus.pending,
  ConversationExecutionValidationStatus? validationStatus,
  ConversationWorkflowTaskStatus? progressStatus,
  bool accepted = false,
  List<String> acceptanceEvidence = const [],
  String acceptanceRationale =
      'The saved command passed and the output matches.',
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
          rationale: acceptanceRationale,
          evidence: acceptanceEvidence,
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
  group('what an acceptance rested on', () {
    test('evidence comes before the rationale', () {
      // The parts differ in kind: a branch name and a command that passed are
      // facts the next turn cannot reconstruct, and the rationale is one turn's
      // prose about them.
      final conversation = _conversation(
        accepted: true,
        acceptanceEvidence: const [
          'worktree branch feature/cli-flags',
          'verified green: dart test',
        ],
        acceptanceRationale: 'The flags match the spec.',
      );

      expect(_projection.acceptanceSummariesByTaskId(conversation), {
        'task-1':
            'worktree branch feature/cli-flags, verified green: dart test '
            '-- The flags match the spec.',
      });
    });

    test('a task with no acceptance is absent, not empty', () {
      expect(
        _projection.acceptanceSummariesByTaskId(_conversation()),
        isEmpty,
        reason:
            'the prompt reads this by id and prints nothing for a miss; an '
            'empty string for every unaccepted task would be a line of noise '
            'per task',
      );
    });

    test('an acceptance that recorded nothing carries no line', () {
      final conversation = _conversation(
        accepted: true,
        acceptanceRationale: '   ',
      );

      expect(_projection.acceptanceSummariesByTaskId(conversation), isEmpty);
    });

    test('a long rationale is clipped before it reaches another prompt', () {
      final conversation = _conversation(
        accepted: true,
        acceptanceRationale: 'x' * 400,
      );
      final summary = _projection.acceptanceSummariesByTaskId(
        conversation,
      )['task-1']!;

      expect(summary.length, 180);
      expect(summary, endsWith('...'));
    });

    test('newlines in model prose collapse to one line', () {
      final conversation = _conversation(
        accepted: true,
        acceptanceRationale: 'It passed.\n\nAnd the files match.',
      );

      expect(_projection.acceptanceSummariesByTaskId(conversation), {
        'task-1': 'It passed. And the files match.',
      });
    });
  });
}
