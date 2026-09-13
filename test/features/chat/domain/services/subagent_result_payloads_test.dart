import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
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
}
