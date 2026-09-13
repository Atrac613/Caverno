import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/subagent_result_payloads.dart';
import 'package:caverno/features/chat/domain/services/subagent_tool_contract.dart';
import 'package:flutter_test/flutter_test.dart';

const _payloads = SubagentResultPayloads();

SubagentTask _task({
  SubagentTaskStatus status = SubagentTaskStatus.completed,
  String resultSummary = 'Read the spec and listed the commands.',
  String? error,
}) => SubagentTask(
  id: 'child-1',
  conversationId: 'conversation-1',
  interactionGeneration: 1,
  status: status,
  description: 'Read the spec',
  resultSummary: resultSummary,
  error: error,
);

Map<String, dynamic> _decode(String payload) =>
    jsonDecode(payload) as Map<String, dynamic>;

void main() {
  test('a missing id is a bad call, not a refusal', () {
    final result = _payloads.missingTaskId('get_subagent_result');

    expect(result.isSuccess, isFalse);
    expect(result.result, isEmpty);
    expect(result.errorMessage, 'task_id is required');
  });

  test('an unknown id names the ids that exist', () {
    final result = _payloads.unknownTask(
      toolName: 'get_subagent_result',
      taskId: 'a-plan-task-id',
      knownTaskIds: const ['child-1'],
    );
    final payload = _decode(result.result);

    expect(payload['code'], subagentTaskUnknownCode);
    expect(payload['status'], 'not_found');
    expect(payload['known_task_ids'], ['child-1']);
    expect(
      payload['required_action'],
      contains('workflow_task_id'),
      reason:
          'The parent passed the plan id to a parameter called task_id; the '
          'answer has to say so.',
    );
  });

  test('a completed child carries its summary and succeeds', () {
    final result = _payloads.forTask(
      toolName: 'get_subagent_result',
      task: _task(),
    );

    expect(result.isSuccess, isTrue);
    expect(
      _decode(result.result)['summary'],
      'Read the spec and listed the commands.',
    );
  });

  test('a failed child carries its error and does not succeed', () {
    final result = _payloads.forTask(
      toolName: 'get_subagent_result',
      task: _task(status: SubagentTaskStatus.failed, error: 'model unloaded'),
    );

    expect(result.isSuccess, isFalse);
    expect(_decode(result.result)['error'], 'model unloaded');
  });

  test('a running child is told to check again, with no summary', () {
    final result = _payloads.forTask(
      toolName: 'get_subagent_result',
      task: _task(status: SubagentTaskStatus.running, resultSummary: ''),
    );
    final payload = _decode(result.result);

    expect(payload['note'], contains('Still running'));
    expect(
      payload.containsKey('summary'),
      isFalse,
      reason: 'An unfinished child has nothing to summarize yet.',
    );
  });

  group('a worktree child reports what only it can', () {
    WorktreeAgentTask task({
      WorktreeAgentTaskStatus status = WorktreeAgentTaskStatus.completed,
      bool verifiedGreen = true,
      int changedFileCount = 2,
      String error = '',
    }) => WorktreeAgentTask(
      id: 'worktree-1',
      status: status,
      title: 'Scaffold the CLI',
      branchName: 'feature/scaffold',
      worktreePath: '/tmp/worktrees/scaffold',
      workflowTaskId: 'task-1',
      verificationCommand: 'dart test',
      verifiedGreen: verifiedGreen,
      error: error,
      changedFiles: [
        for (var index = 0; index < changedFileCount; index++)
          WorktreeAgentChangedFileEvidence(path: 'lib/file_$index.dart'),
      ],
      createdAt: DateTime(2026, 9, 13),
      updatedAt: DateTime(2026, 9, 13),
    );

    test('the branch, the verification and the count', () {
      final payload = _decode(
        _payloads
            .forWorktreeTask(toolName: 'get_subagent_result', task: task())
            .result,
      );

      expect(payload['runner'], 'worktree');
      expect(payload['branch_name'], 'feature/scaffold');
      expect(payload['verification_command'], 'dart test');
      expect(payload['verified'], isTrue);
      expect(payload['changed_file_count'], 2);
      expect(payload['workflow_task_id'], 'task-1');
    });

    test('not verified is an answer, not an omission', () {
      final payload = _decode(
        _payloads
            .forWorktreeTask(
              toolName: 'get_subagent_result',
              task: task(verifiedGreen: false),
            )
            .result,
      );

      expect(
        payload['verified'],
        isFalse,
        reason: '"not yet" and "failed" are both things the parent must act on.',
      );
    });

    test('a running branch is told to check again and does not fail', () {
      final result = _payloads.forWorktreeTask(
        toolName: 'get_subagent_result',
        task: task(status: WorktreeAgentTaskStatus.running),
      );

      expect(result.isSuccess, isTrue);
      expect(_decode(result.result)['note'], contains('Still running'));
    });

    test('a failed branch does not succeed and carries its error', () {
      final result = _payloads.forWorktreeTask(
        toolName: 'get_subagent_result',
        task: task(status: WorktreeAgentTaskStatus.failed, error: 'git locked'),
      );

      expect(result.isSuccess, isFalse);
      expect(_decode(result.result)['error'], 'git locked');
    });
  });

  test('the enqueue answer says the child is running, not merely queued', () {
    // Nothing but a slash command drives the scheduler, so the parent's route
    // starts the run itself; an answer that said "queued" would have the parent
    // poll a child that never begins.
    final payload = _decode(
      _payloads
          .worktreeEnqueued(
            toolName: 'spawn_subagent',
            taskId: 'worktree-1',
            workflowTaskId: 'task-1',
            branchName: 'feature/scaffold',
            worktreePath: '/tmp/worktrees/scaffold',
            verificationCommand: 'dart test',
          )
          .result,
    );

    expect(payload['started'], isTrue);
    expect(payload['status'], 'enqueued');
    expect(payload['required_action'], contains('Poll get_subagent_result'));
  });

  test('a second branch for one task is refused, with the first one named', () {
    final payload = _decode(
      _payloads
          .worktreeAlreadyRunning(
            toolName: 'spawn_subagent',
            taskId: 'worktree-1',
            workflowTaskId: 'task-1',
            branchName: 'feature/scaffold',
          )
          .result,
    );

    expect(payload['code'], 'worktree_child_already_running');
    expect(payload['task_id'], 'worktree-1');
    expect(
      payload['required_action'],
      contains('Poll get_subagent_result'),
      reason:
          'The refusal has to name the poll, because the parent did the thing '
          'this prevents -- started a second branch -- when nothing did.',
    );
  });
}
