import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/project_farm/application/project_task_review_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026);
  Conversation initial() => Conversation(
    id: 'task',
    title: 'Task',
    messages: [],
    createdAt: now,
    updatedAt: now,
    goal: ConversationGoal(
      id: 'goal',
      objective: 'Implement task\nSource: ROADMAP.md:4',
      createdAt: now,
      updatedAt: now,
    ),
  );

  Message assistant(String content, int index) => Message(
    id: 'assistant-$index',
    content: content,
    role: MessageRole.assistant,
    timestamp: now,
  );

  TurnDiff diff(int index) => TurnDiff(
    id: 'diff-$index',
    assistantMessageId: 'assistant-$index',
    userPromptPreview: 'task',
    timestamp: now,
    files: [
      TurnDiffFile(
        filePath: 'lib/task.dart',
        unifiedPatch: '@@ -1 +1 @@\n-old\n+new',
      ),
    ],
  );

  test(
    'implements, reviews through the dedicated route, and repairs',
    () async {
      var conversation = initial();
      final routes = <bool>[];
      final prompts = <String>[];
      var implementationCount = 0;
      final workflow = ProjectTaskReviewWorkflow(
        conversationId: 'task',
        readConversation: () => conversation,
        isSelected: () => true,
        isWaitingForUser: () => false,
        send: (prompt, {required codeReview}) async {
          routes.add(codeReview);
          prompts.add(prompt);
          final index = routes.length;
          if (codeReview) {
            conversation = conversation.copyWith(
              messages: [
                ...conversation.messages,
                assistant(
                  index == 2
                      ? 'Fix a null case.\nPROJECT_TASK_REVIEW_FINDINGS'
                      : 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
                  index,
                ),
              ],
            );
          } else {
            implementationCount++;
            conversation = conversation.copyWith(
              messages: [
                ...conversation.messages,
                assistant('Verified.\nPROJECT_TASK_READY_FOR_REVIEW', index),
              ],
              turnDiffs: [...conversation.turnDiffs, diff(implementationCount)],
            );
          }
          return true;
        },
      );

      expect(await workflow.run(), ProjectTaskReviewResult.clean);
      expect(routes, [false, true, false, true]);
      expect(prompts[1], contains('```diff'));
      expect(prompts[2], contains('Fix a null case.'));
    },
  );

  test('stops when task changes have no reviewable patch', () async {
    var conversation = initial();
    var calls = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      send: (_, {required codeReview}) async {
        calls++;
        conversation = conversation.copyWith(
          messages: [assistant('Done.\nPROJECT_TASK_READY_FOR_REVIEW', calls)],
        );
        return true;
      },
    );
    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(
      calls,
      2,
      reason: 'one bounded recovery follows a false ready claim',
    );
  });

  test('recovers a false ready claim before starting review', () async {
    var conversation = initial();
    final routes = <bool>[];
    final prompts = <String>[];
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      send: (prompt, {required codeReview}) async {
        routes.add(codeReview);
        prompts.add(prompt);
        final call = routes.length;
        conversation = conversation.copyWith(
          messages: [
            ...conversation.messages,
            assistant(
              call == 1
                  ? 'Modified files and all tests pass.\n'
                        'PROJECT_TASK_READY_FOR_REVIEW\n\n'
                        'Deliverable claim check: no mutation was recorded.'
                  : call == 2
                  ? 'Implemented and verified.\nPROJECT_TASK_READY_FOR_REVIEW'
                  : 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
              call,
            ),
          ],
          turnDiffs: call == 2 ? [diff(call)] : conversation.turnDiffs,
        );
        return true;
      },
    );

    expect(await workflow.run(), ProjectTaskReviewResult.clean);
    expect(routes, [false, false, true]);
    expect(prompts[1], contains('no reviewable file change'));
    expect(prompts[2], contains('```diff'));
  });

  test('continues once when a no-diff turn omits the ready marker', () async {
    var conversation = initial();
    final routes = <bool>[];
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      send: (_, {required codeReview}) async {
        routes.add(codeReview);
        final call = routes.length;
        conversation = conversation.copyWith(
          messages: [
            ...conversation.messages,
            assistant(
              call == 1
                  ? 'I read the same files but made no change.'
                  : call == 2
                  ? 'Implemented and verified.\nPROJECT_TASK_READY_FOR_REVIEW'
                  : 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
              call,
            ),
          ],
          turnDiffs: call == 2 ? [diff(call)] : conversation.turnDiffs,
        );
        return true;
      },
    );

    expect(await workflow.run(), ProjectTaskReviewResult.clean);
    expect(routes, [false, false, true]);
  });

  test('does not continue when a question needs a user answer', () async {
    var conversation = initial();
    var waiting = false;
    var calls = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => waiting,
      send: (_, {required codeReview}) async {
        calls++;
        conversation = conversation.copyWith(
          messages: [
            ...conversation.messages,
            assistant('Which option?', calls),
          ],
        );
        waiting = true;
        return true;
      },
    );

    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(calls, 1);
  });

  test('stops before review when the user switches threads', () async {
    var conversation = initial();
    var selected = true;
    var calls = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => selected,
      isWaitingForUser: () => false,
      send: (_, {required codeReview}) async {
        calls++;
        conversation = conversation.copyWith(
          messages: [assistant('Done.\nPROJECT_TASK_READY_FOR_REVIEW', calls)],
          turnDiffs: [diff(calls)],
        );
        selected = false;
        return true;
      },
    );
    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(calls, 1);
  });
}
