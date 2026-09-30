import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/project_farm/application/project_task_review_turn_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Conversation conversation;
  late bool selected;
  late bool waiting;
  late int sends;
  late int reactivations;
  late ConversationGoalStatus reported;
  late ProjectTaskReviewTurnRunner runner;
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
        createdAt: now,
        updatedAt: now,
      ),
    );
    selected = true;
    waiting = false;
    sends = 0;
    reactivations = 0;
    reported = ConversationGoalStatus.active;
    runner = ProjectTaskReviewTurnRunner(
      readConversation: () => conversation,
      isSelected: () => selected,
      isWaitingForUser: () => waiting,
      reactivate: () async {
        reactivations++;
        conversation = conversation.copyWith(
          goal: conversation.goal!.copyWith(
            status: ConversationGoalStatus.active,
          ),
        );
      },
      sendTurn: (_, {required codeReview}) async {
        sends++;
        return ChatTurnOwner(conversationId: 'task', interactionGeneration: 1);
      },
      waitForCompletion: (_) async {
        conversation = conversation.copyWith(
          goal: conversation.goal!.copyWith(status: reported),
        );
      },
    );
  });

  test('requires accepted completion for implementation', () async {
    expect(await runner.send('Implement', codeReview: false), isFalse);
    reported = ConversationGoalStatus.completed;
    expect(await runner.send('Implement', codeReview: false), isTrue);
  });
  test('resumes a completed implementation for review repairs', () async {
    conversation = conversation.copyWith(
      goal: conversation.goal!.copyWith(
        status: ConversationGoalStatus.completed,
      ),
    );
    reported = ConversationGoalStatus.completed;
    expect(await runner.send('Repair', codeReview: false), isTrue);
    expect(reactivations, 1);
  });
  test('review remains read-only and does not reactivate completion', () async {
    conversation = conversation.copyWith(
      goal: conversation.goal!.copyWith(
        status: ConversationGoalStatus.completed,
      ),
    );
    expect(await runner.send('Review', codeReview: true), isTrue);
    expect(reactivations, 0);
  });
  test('respects selection and pending input', () async {
    selected = false;
    expect(await runner.send('Implement', codeReview: false), isFalse);
    selected = true;
    waiting = true;
    expect(await runner.send('Implement', codeReview: false), isFalse);
    expect(sends, 0);
  });
  test('does not resume blocked or confirmation-bound goals', () async {
    for (final status in [
      ConversationGoalStatus.blocked,
      ConversationGoalStatus.awaitingConfirmation,
    ]) {
      conversation = conversation.copyWith(
        goal: conversation.goal!.copyWith(status: status),
      );
      expect(await runner.send('Implement', codeReview: false), isFalse);
    }
    expect(sends, 0);
  });
  test('does not spend a capped goal', () async {
    conversation = conversation.copyWith(
      goal: conversation.goal!.copyWith(turnBudget: 1, turnsUsed: 1),
    );
    expect(await runner.send('Implement', codeReview: false), isFalse);
    expect(sends, 0);
  });
}
