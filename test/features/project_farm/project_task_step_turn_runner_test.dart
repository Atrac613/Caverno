import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/project_farm/application/project_task_step_turn_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Conversation conversation;
  late bool selected;
  late bool waiting;
  late int sends;
  late ProjectTaskStepTurnRunner runner;
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
    runner = ProjectTaskStepTurnRunner(
      readConversation: () => conversation,
      isSelected: () => selected,
      isWaitingForUser: () => waiting,
      admits: ProjectTaskStepTurnRunner.completedGoal,
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

  test('completed goals still respect disablement and budget', () async {
    for (final goal in [
      conversation.goal!.copyWith(enabled: false),
      conversation.goal!.copyWith(turnBudget: 1, turnsUsed: 1),
      conversation.goal!.copyWith(tokenBudget: 10, tokenUsage: 10),
    ]) {
      conversation = conversation.copyWith(goal: goal);
      expect(await runner.send('Commit'), isFalse);
    }
    expect(sends, 0);
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

  test('subtask turns run only on an active goal within budget', () {
    final goal = conversation.goal!;
    bool admits(ConversationGoal goal) =>
        ProjectTaskStepTurnRunner.activeGoal(goal);
    expect(admits(goal), isFalse, reason: 'completed');
    expect(
      admits(goal.copyWith(status: ConversationGoalStatus.active)),
      isTrue,
    );
    expect(
      admits(
        goal.copyWith(
          status: ConversationGoalStatus.active,
          turnBudget: 1,
          turnsUsed: 1,
        ),
      ),
      isFalse,
    );
    expect(
      admits(goal.copyWith(status: ConversationGoalStatus.blocked)),
      isFalse,
    );
  });

  test('reopens a goal an earlier subtask completed too early', () async {
    var reopened = 0;
    final subtaskRunner = ProjectTaskStepTurnRunner(
      readConversation: () => conversation,
      isSelected: () => selected,
      isWaitingForUser: () => waiting,
      admits: ProjectTaskStepTurnRunner.activeGoal,
      reactivateCompleted: () async {
        reopened++;
        conversation = conversation.copyWith(
          goal: conversation.goal!.copyWith(
            status: ConversationGoalStatus.active,
          ),
        );
      },
      sendTurn: (_) async {
        sends++;
        return ChatTurnOwner(conversationId: 'task', interactionGeneration: 1);
      },
      waitForCompletion: (_) async {},
    );

    expect(await subtaskRunner.send('Subtask 2'), isTrue);
    expect(reopened, 1);
    expect(sends, 1);
  });
}
