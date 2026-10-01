import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/project_farm/application/project_task_commit_turn_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Conversation conversation;
  late bool selected;
  late bool waiting;
  late int sends;
  late ProjectTaskCommitTurnRunner runner;
  setUp(() {
    final now = DateTime(2026);
    conversation = Conversation(
      id: 'task',
      title: 'Task',
      messages: [],
      createdAt: now,
      updatedAt: now,
      goal: ConversationGoal(
        id: 'goal',
        objective: 'Implement task',
        projectTaskAutoReview: true,
        status: ConversationGoalStatus.completed,
        createdAt: now,
        updatedAt: now,
      ),
    );
    selected = true;
    waiting = false;
    sends = 0;
    runner = ProjectTaskCommitTurnRunner(
      readConversation: () => conversation,
      isSelected: () => selected,
      isWaitingForUser: () => waiting,
      sendTurn: (_) async {
        sends++;
        return ChatTurnOwner(conversationId: 'task', interactionGeneration: 1);
      },
      waitForCompletion: (_) async {},
    );
  });

  test('commits a completed goal and leaves its status alone', () async {
    expect(await runner.send('Commit'), isTrue);
    expect(sends, 1);
    expect(conversation.goal!.status, ConversationGoalStatus.completed);
  });

  test('does not commit an unfinished goal', () async {
    conversation = conversation.copyWith(
      goal: conversation.goal!.copyWith(status: ConversationGoalStatus.active),
    );
    expect(await runner.send('Commit'), isFalse);
    expect(sends, 0);
  });

  test('respects selection and pending input', () async {
    selected = false;
    expect(await runner.send('Commit'), isFalse);
    selected = true;
    waiting = true;
    expect(await runner.send('Commit'), isFalse);
    expect(sends, 0);
  });
}
