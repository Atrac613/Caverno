import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/delegated_result_digest.dart';
import 'package:flutter_test/flutter_test.dart';

const _digest = DelegatedResultDigest();

SubagentTask _child({
  required String id,
  SubagentTaskStatus status = SubagentTaskStatus.completed,
  String description = 'Scaffold the CLI',
  String workflowTaskId = 'task-1',
}) => SubagentTask(
  id: id,
  conversationId: 'conversation-1',
  interactionGeneration: 1,
  status: status,
  description: description,
  workflowTaskId: workflowTaskId,
);

void main() {
  test('names the child id the parent has to pass back', () {
    final summaries = _digest.summaries(
      children: [_child(id: 'child-a')],
      acceptedTaskIds: const {},
    );

    expect(summaries, hasLength(1));
    // Labelled by the parameter that consumes it: the first version said
    // child_id / workflow_task_id, and the parent passed the workflow id to
    // get_subagent_result, whose parameter is task_id.
    expect(summaries.single, contains('get_subagent_result task_id: child-a'));
    expect(
      summaries.single,
      contains('accept_task workflow_task_id: task-1'),
    );
    expect(summaries.single, contains('completed'));
  });

  test('omits a child that is still running', () {
    expect(
      _digest.summaries(
        children: [
          _child(id: 'child-a', status: SubagentTaskStatus.running),
        ],
        acceptedTaskIds: const {},
      ),
      isEmpty,
      reason: 'There is nothing to judge until the child has settled.',
    );
  });

  test('keeps a failed child, which is also a judgement to make', () {
    expect(
      _digest.summaries(
        children: [_child(id: 'child-a', status: SubagentTaskStatus.failed)],
        acceptedTaskIds: const {},
      ),
      hasLength(1),
    );
  });

  test('drops a task the parent has already accepted', () {
    expect(
      _digest.summaries(
        children: [_child(id: 'child-a')],
        acceptedTaskIds: const {'task-1'},
      ),
      isEmpty,
      reason: 'Listing it again invites a second acceptance of one result.',
    );
  });

  test('an ordinary delegation carries no saved task', () {
    final summaries = _digest.summaries(
      children: [_child(id: 'child-a', workflowTaskId: '')],
      acceptedTaskIds: const {},
    );

    expect(summaries.single, contains('get_subagent_result task_id: child-a'));
    expect(summaries.single, isNot(contains('workflow_task_id')));
  });

  group('worktree children', () {
    WorktreeAgentTask worktree({
      String workflowTaskId = 'task-1',
      WorktreeAgentTaskStatus status = WorktreeAgentTaskStatus.completed,
      bool verifiedGreen = true,
    }) => WorktreeAgentTask(
      id: 'worktree-1',
      status: status,
      title: 'Scaffold the CLI',
      branchName: 'feature/scaffold',
      worktreePath: '/tmp/worktrees/scaffold',
      workflowTaskId: workflowTaskId,
      verificationCommand: 'dart test',
      verifiedGreen: verifiedGreen,
      changedFiles: const [
        WorktreeAgentChangedFileEvidence(path: 'bin/todo.dart'),
      ],
      createdAt: DateTime(2026, 9, 13),
      updatedAt: DateTime(2026, 9, 13),
    );

    test('are named by branch, and carry both ids the tools take', () {
      final summaries = _digest.summaries(
        children: const [],
        acceptedTaskIds: const {},
        worktreeChildren: [worktree()],
      );

      expect(summaries, hasLength(1));
      expect(summaries.single, contains('(worktree feature/scaffold)'));
      expect(
        summaries.single,
        contains('get_subagent_result task_id: worktree-1'),
      );
      expect(
        summaries.single,
        contains('accept_task workflow_task_id: task-1'),
      );
      expect(summaries.single, contains('verified: true'));
      expect(summaries.single, contains('1 changed file(s)'));
    });

    test('come first, because they are the kind an acceptance can rest on', () {
      final summaries = _digest.summaries(
        children: [_child(id: 'child-a')],
        acceptedTaskIds: const {},
        worktreeChildren: [worktree()],
      );

      expect(summaries, hasLength(2));
      expect(summaries.first, contains('worktree feature/scaffold'));
    });

    test('an unbound branch is not the parent\'s to judge', () {
      expect(
        _digest.summaries(
          children: const [],
          acceptedTaskIds: const {},
          worktreeChildren: [worktree(workflowTaskId: '')],
        ),
        isEmpty,
        reason: 'The UI and LL37 enqueue branches with no saved task.',
      );
    });

    test('a running branch waits, and an accepted task drops out', () {
      expect(
        _digest.summaries(
          children: const [],
          acceptedTaskIds: const {},
          worktreeChildren: [
            worktree(status: WorktreeAgentTaskStatus.running),
          ],
        ),
        isEmpty,
      );
      expect(
        _digest.summaries(
          children: const [],
          acceptedTaskIds: const {'task-1'},
          worktreeChildren: [worktree()],
        ),
        isEmpty,
      );
    });
  });
}
