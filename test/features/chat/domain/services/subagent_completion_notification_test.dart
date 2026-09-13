import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/services/subagent_tool_contract.dart';
import 'package:flutter_test/flutter_test.dart';

SubagentTask _task({
  SubagentTaskStatus status = SubagentTaskStatus.completed,
  String resultSummary = '',
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

void main() {
  test('a child that reported something speaks for itself', () {
    final notification = SubagentCompletionNotification.forTask(
      _task(resultSummary: 'Listed add, list, done and delete.'),
    );

    expect(notification.isSuccessful, isTrue);
    expect(notification.body, 'Listed add, list, done and delete.');
  });

  test('a silent success still says something', () {
    expect(
      SubagentCompletionNotification.forTask(_task()).body,
      'Completed.',
    );
  });

  test('a failure is named by its error, and a bare one by a fallback', () {
    expect(
      SubagentCompletionNotification.forTask(
        _task(status: SubagentTaskStatus.failed, error: 'model unloaded'),
      ).body,
      'model unloaded',
    );
    final bare = SubagentCompletionNotification.forTask(
      _task(status: SubagentTaskStatus.failed),
    );
    expect(bare.isSuccessful, isFalse);
    expect(bare.body, 'Subagent failed.');
  });

  test('a long body is cut, because a notification is a glance', () {
    final notification = SubagentCompletionNotification.forTask(
      _task(resultSummary: 'x' * 500),
    );

    expect(
      notification.body.length,
      SubagentCompletionNotification.maxBodyChars + 3,
    );
    expect(notification.body, endsWith('...'));
  });
}
