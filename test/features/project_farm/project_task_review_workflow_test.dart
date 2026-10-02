import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/project_farm/application/project_task_review_workflow.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_git_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026);
  var commits = 0;
  final commitPrompts = <String>[];
  Future<bool> commitTurn(String prompt) async {
    commitPrompts.add(prompt);
    commits++;
    return true;
  }

  Future<ProjectTaskGitState?> gitState(List<String> paths) async =>
      ProjectTaskGitState(head: 'head-$commits', dirtyPaths: const []);

  setUp(commitPrompts.clear);
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

  test('implements, reviews through the dedicated route, and repairs', () async {
    var conversation = initial();
    final routes = <bool>[];
    final prompts = <String>[];
    var implementationCount = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: commitTurn,
      readGitState: gitState,
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
                    ? '<tool_use>{"name":"read_file","arguments":{"path":"a"}}'
                          '</tool_use>\nFix a null case.\n'
                          'PROJECT_TASK_REVIEW_FINDINGS'
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

    expect(await workflow.run(), ProjectTaskReviewResult.committed);
    expect(routes, [false, true, false, true]);
    expect(prompts[1], contains('```diff'));
    expect(prompts[2], contains('Fix a null case.'));
    // Session 40851e45: narrow repairs left a neighbouring variant for the
    // next review, three rounds running.
    expect(prompts[2], contains('underlying defect behind each finding'));
    // Session 80dc7079: the review's raw tool markup reached the repair
    // prompt as if it were review text.
    expect(prompts[2], isNot(contains('<tool_use>')));
  });

  test('stops when task changes have no reviewable patch', () async {
    var conversation = initial();
    var calls = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: commitTurn,
      readGitState: gitState,
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

  test('records why the review never started', () async {
    // Session 1d76c878: the review never ran and nothing said whether the
    // goal status or the marker line stopped it.
    var conversation = initial();
    var completed = true;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: commitTurn,
      readGitState: gitState,
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      send: (_, {required codeReview}) async {
        conversation = conversation.copyWith(
          messages: [
            assistant(
              'Done.\nPROJECT_TASK_READY_FOR_REVIEW\n\n'
              'Deliverable claim check: `a.py` was not modified.',
              1,
            ),
          ],
          turnDiffs: [diff(1)],
        );
        return completed;
      },
    );

    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(
      workflow.stopReason,
      allOf(
        contains('does not end with PROJECT_TASK_READY_FOR_REVIEW'),
        contains('Deliverable claim check'),
      ),
    );

    conversation = initial();
    completed = false;
    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(workflow.stopReason, contains('without a recorded goal completion'));
  });

  test('recovers a false ready claim before starting review', () async {
    var conversation = initial();
    final routes = <bool>[];
    final prompts = <String>[];
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: commitTurn,
      readGitState: gitState,
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

    expect(await workflow.run(), ProjectTaskReviewResult.committed);
    expect(routes, [false, false, true]);
    expect(prompts[1], contains('no reviewable file change'));
    expect(prompts[2], contains('```diff'));
  });

  test('continues once when a no-diff turn omits the ready marker', () async {
    var conversation = initial();
    final routes = <bool>[];
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: commitTurn,
      readGitState: gitState,
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

    expect(await workflow.run(), ProjectTaskReviewResult.committed);
    expect(routes, [false, false, true]);
  });

  test('does not continue when a question needs a user answer', () async {
    var conversation = initial();
    var waiting = false;
    var calls = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: commitTurn,
      readGitState: gitState,
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
      commit: commitTurn,
      readGitState: gitState,
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
  test('commits the reviewed task and checks the commit in git', () async {
    var conversation = initial();
    final workflow = cleanTaskWorkflow(
      read: () => conversation,
      update: (next) => conversation = next,
      commit: commitTurn,
      readGitState: gitState,
    );

    expect(await workflow.run(), ProjectTaskReviewResult.committed);
    expect(commitPrompts, hasLength(1));
    expect(
      commitPrompts.single,
      allOf(
        contains('Source: ROADMAP.md:4'),
        contains('mark it done'),
        contains('- lib/task.dart'),
        contains('Do not push'),
        // Session f4269d8c: copying the log's run-on subjects produced a
        // 150-character subject holding the whole body.
        contains('at most 72 characters'),
        contains('second -m paragraph'),
      ),
    );
  });

  test('stops when the commit turn made no commit', () async {
    // The reported defect: a clean review ended the workflow with the task
    // uncommitted, and the dashboard moved on to the next roadmap item.
    var conversation = initial();
    final workflow = cleanTaskWorkflow(
      read: () => conversation,
      update: (next) => conversation = next,
      commit: (_) async => true,
      readGitState: (_) async =>
          const ProjectTaskGitState(head: 'unchanged', dirtyPaths: []),
    );

    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(workflow.stopReason, contains('no new commit'));
  });

  test('stops when task files remain uncommitted', () async {
    var conversation = initial();
    var head = 'before';
    final workflow = cleanTaskWorkflow(
      read: () => conversation,
      update: (next) => conversation = next,
      commit: (_) async {
        head = 'after';
        return true;
      },
      readGitState: (_) async => ProjectTaskGitState(
        head: head,
        dirtyPaths: head == 'after' ? const [' M lib/task.dart'] : const [],
      ),
    );

    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(workflow.stopReason, contains('lib/task.dart'));
  });

  test('does not commit when git cannot be read', () async {
    var conversation = initial();
    var commitCalls = 0;
    final workflow = cleanTaskWorkflow(
      read: () => conversation,
      update: (next) => conversation = next,
      commit: (_) async {
        commitCalls++;
        return true;
      },
      readGitState: (_) async => null,
    );

    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(commitCalls, 0);
  });
}

/// A workflow whose implementation captures one change and whose review is
/// clean, so the run reaches the commit stage.
ProjectTaskReviewWorkflow cleanTaskWorkflow({
  required Conversation Function() read,
  required void Function(Conversation) update,
  required Future<bool> Function(String) commit,
  required Future<ProjectTaskGitState?> Function(List<String>) readGitState,
}) {
  final now = DateTime(2026);
  var calls = 0;
  return ProjectTaskReviewWorkflow(
    conversationId: 'task',
    readConversation: read,
    isSelected: () => true,
    isWaitingForUser: () => false,
    commit: commit,
    readGitState: readGitState,
    send: (_, {required codeReview}) async {
      calls++;
      final conversation = read();
      update(
        conversation.copyWith(
          messages: [
            ...conversation.messages,
            Message(
              id: 'assistant-$calls',
              content: codeReview
                  ? 'No findings.\nPROJECT_TASK_REVIEW_CLEAN'
                  : 'Verified.\nPROJECT_TASK_READY_FOR_REVIEW',
              role: MessageRole.assistant,
              timestamp: now,
            ),
          ],
          turnDiffs: codeReview
              ? conversation.turnDiffs
              : [
                  TurnDiff(
                    id: 'diff-$calls',
                    assistantMessageId: 'assistant-$calls',
                    userPromptPreview: 'task',
                    timestamp: now,
                    files: const [
                      TurnDiffFile(
                        filePath: 'lib/task.dart',
                        unifiedPatch: '@@ -1 +1 @@\n-old\n+new',
                      ),
                    ],
                  ),
                ],
        ),
      );
      return true;
    },
  );
}
