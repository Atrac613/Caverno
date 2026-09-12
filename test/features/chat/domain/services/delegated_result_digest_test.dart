import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
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
    expect(summaries.single, contains('[child_id: child-a]'));
    expect(summaries.single, contains('[workflow_task_id: task-1]'));
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

    expect(summaries.single, contains('[child_id: child-a]'));
    expect(summaries.single, isNot(contains('workflow_task_id')));
  });
}
