import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/project_task_review_verdict.dart';
import 'package:caverno/features/project_farm/application/project_task_commit_turn_evidence.dart';
import 'package:caverno/features/project_farm/application/project_task_review_workflow.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_git_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/project_task_commit_test_support.dart';

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

  for (final native in ['findings', 'missing', 'incomplete']) {
    test(
      'native review $native cannot be replaced by a clean saved summary',
      () async {
        var conversation = initial();
        ProjectTaskReviewVerdict? verdict;
        var repaired = false;
        var reviewCount = 0;
        final decisions = <Map<String, Object?>>[];
        final workflow = ProjectTaskReviewWorkflow(
          conversationId: 'task',
          commit: (prompt, scope) => commitTurn(prompt),
          projectRoot: '/repo',
          prepareCommit: (_, _) async => true,
          readCommitSnapshot: (scope) async =>
              fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
          readGitState: gitState,
          readConversation: () => conversation,
          isSelected: () => true,
          isWaitingForUser: () => false,
          readReviewVerdict: () => verdict,
          readVerificationContext: () =>
              'Historical runner: .venv/bin/python -m pytest',
          onDecision: decisions.add,
          send: (prompt, {required codeReview}) async {
            final index = conversation.messages.length + 1;
            if (codeReview) {
              expect(
                prompt,
                contains('Historical runner: .venv/bin/python -m pytest'),
              );
              reviewCount++;
              verdict = switch (native) {
                'missing' => null,
                'incomplete' => ProjectTaskReviewVerdict.fromResponse(
                  'Inspection unavailable.',
                ),
                _ => ProjectTaskReviewVerdict.fromResponse(
                  reviewCount == 1
                      ? 'watcher.py:163: reject Infinity.\nPROJECT_TASK_REVIEW_FINDINGS'
                      : 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
                ),
              };
            } else {
              if (reviewCount > 0) {
                expect(prompt, contains('watcher.py:163: reject Infinity.'));
                repaired = true;
              }
              conversation = conversation.copyWith(
                turnDiffs: [...conversation.turnDiffs, diff(index)],
              );
            }
            conversation = conversation.copyWith(
              messages: [
                ...conversation.messages,
                assistant(
                  codeReview
                      ? 'No findings.\nPROJECT_TASK_REVIEW_CLEAN'
                      : 'Verified.\nPROJECT_TASK_READY_FOR_REVIEW',
                  index,
                ),
              ],
            );
            return true;
          },
        );
        expect(
          await workflow.run(),
          native == 'findings'
              ? ProjectTaskReviewResult.committed
              : ProjectTaskReviewResult.stopped,
        );
        expect(repaired, native == 'findings');
        if (native != 'findings') {
          expect(commitPrompts, isEmpty);
          expect(
            decisions.singleWhere(
              (decision) => decision['decision'] == 'stopped',
            )['gapCodes'],
            ['review_incomplete'],
          );
        }
      },
    );
  }

  test('implements, reviews through the dedicated route, and repairs', () async {
    var conversation = initial();
    final routes = <bool>[];
    final prompts = <String>[];
    var implementationCount = 0;
    final workflow = ProjectTaskReviewWorkflow(
      conversationId: 'task',
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
    for (final review in [prompts[1], prompts[3]]) {
      expect(review, contains('Begin this review turn by calling read_file'));
      expect(review, contains('wait for successful results'));
      expect(review, endsWith('- lib/task.dart'));
      expect(
        review,
        contains('historical evidence, not current review inspections'),
      );
    }
    for (final implementation in [prompts[0], prompts[2]]) {
      expect(
        implementation,
        contains(
          'review, roadmap update and commit are not remaining implementation work',
        ),
      );
      expect(
        implementation,
        contains(
          'Never report completion without captured change and successful verification evidence',
        ),
      );
    }
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
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
      commit: (prompt, scope) => commitTurn(prompt),
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, (await gitState([]))!.head),
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
        contains('Source: /repo/ROADMAP.md:4'),
        contains('index is already prepared'),
        contains('- /repo/lib/task.dart'),
        contains('Do not edit files, change staging, push, publish'),
        // Session f4269d8c: copying the log's run-on subjects produced a
        // 150-character subject holding the whole body.
        contains('at most 72 characters'),
        contains('second -m paragraph'),
      ),
    );
  });

  test(
    'missing roadmap preparation stops before the commit callback',
    () async {
      var conversation = initial();
      var inspections = 0;
      var preparations = 0;
      final workflow = cleanTaskWorkflow(
        read: () => conversation,
        update: (next) => conversation = next,
        commit: commitTurn,
        readGitState: gitState,
        prepareCommit: (_, _) async {
          preparations++;
          return true;
        },
        readCommitSnapshot: (scope) async {
          inspections++;
          final snapshot = fakeTaskCommitSnapshot(
            scope,
            (await gitState([]))!.head,
          );
          return inspections == 1
              ? snapshot
              : ProjectTaskCommitSnapshot(
                  head: snapshot.head,
                  indexFingerprint: 'prepared-index',
                  fileFingerprints: snapshot.fileFingerprints,
                  stagedPaths: scope.reviewedPaths,
                  unstagedPaths: {},
                );
        },
      );
      expect(await workflow.run(), ProjectTaskReviewResult.stopped);
      expect(preparations, 1);
      expect(workflow.stopReason, contains('roadmap update is missing'));
      expect(commitPrompts, isEmpty);
    },
  );

  for (final gate in ['completed', 'active', 'disabled', 'budget']) {
    test(
      'idle recovery requires a completed enabled goal with budget: $gate',
      () async {
        var conversation = initial();
        var preparations = 0;
        var reads = 0;
        var committed = false;
        final workflow = cleanTaskWorkflow(
          read: () => conversation,
          update: (next) => conversation = next,
          commit: (_) async {
            committed = true;
            return true;
          },
          readGitState: (_) async => ProjectTaskGitState(
            head: committed ? 'after' : 'before',
            dirtyPaths: [],
          ),
          prepareCommit: (_, _) async {
            preparations++;
            conversation = conversation.copyWith(
              goal: conversation.goal!.copyWith(
                status: gate == 'active'
                    ? ConversationGoalStatus.active
                    : ConversationGoalStatus.completed,
                enabled: gate != 'disabled',
                turnBudget: gate == 'budget' ? 1 : 0,
                turnsUsed: gate == 'budget' ? 1 : 0,
              ),
            );
            return true;
          },
          readCommitTurnEvidence: () => const ProjectTaskCommitTurnEvidence(
            completedNormally: true,
            mutationAttempted: false,
            failed: false,
          ),
          readCommitSnapshot: (scope) async => ProjectTaskCommitSnapshot(
            head: committed ? 'after' : 'before',
            indexFingerprint: reads++ < 2 ? 'baseline' : 'prepared',
            fileFingerprints: {for (final file in scope.paths) file: 'same'},
            stagedPaths: preparations < 2 ? {} : scope.paths,
            unstagedPaths: {},
          ),
        );
        expect(
          await workflow.run(),
          gate == 'completed'
              ? ProjectTaskReviewResult.committed
              : ProjectTaskReviewResult.stopped,
        );
        expect(preparations, gate == 'completed' ? 2 : 1);
        expect(committed, gate == 'completed');
      },
    );
  }

  test('unrelated staged work stops before preparation or commit', () async {
    var conversation = initial();
    var preparations = 0;
    final workflow = cleanTaskWorkflow(
      read: () => conversation,
      update: (next) => conversation = next,
      commit: commitTurn,
      readGitState: gitState,
      prepareCommit: (_, _) async {
        preparations++;
        return true;
      },
      readCommitSnapshot: (scope) async {
        final snapshot = fakeTaskCommitSnapshot(
          scope,
          (await gitState([]))!.head,
        );
        return ProjectTaskCommitSnapshot(
          head: snapshot.head,
          indexFingerprint: 'index',
          fileFingerprints: snapshot.fileFingerprints,
          stagedPaths: {...scope.paths, '/repo/unrelated.txt'},
          unstagedPaths: {},
        );
      },
    );
    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(workflow.stopReason, contains('unrelated staged'));
    expect(preparations, 0);
    expect(commitPrompts, isEmpty);
  });

  test('does not commit an incomplete or guarded review', () async {
    for (final response in [
      'Review is incomplete.',
      'PROJECT_TASK_REVIEW_CLEAN\nInspection is unverified.',
    ]) {
      var conversation = initial();
      var attemptedCommit = false;
      final workflow = cleanTaskWorkflow(
        read: () => conversation,
        update: (value) => conversation = value,
        commit: (_) async {
          attemptedCommit = true;
          return true;
        },
        readGitState: gitState,
        reviewResponse: response,
      );
      expect(await workflow.run(), ProjectTaskReviewResult.stopped);
      expect(attemptedCommit, isFalse);
      expect(workflow.stopReason, contains('review ended without'));
    }
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

  test('checks roadmap edits captured during the commit turn', () async {
    var conversation = initial();
    var committed = false;
    final inspectedPaths = <List<String>>[];
    final workflow = cleanTaskWorkflow(
      read: () => conversation,
      update: (value) => conversation = value,
      commit: (_) async {
        committed = true;
        conversation = conversation.copyWith(
          turnDiffs: [
            ...conversation.turnDiffs,
            diff(2).copyWith(
              files: const [
                TurnDiffFile(
                  filePath: 'ROADMAP.md',
                  unifiedPatch: '-[ ]\n+[x]',
                ),
              ],
            ),
          ],
        );
        return true;
      },
      readGitState: (paths) async {
        inspectedPaths.add([...paths]);
        return ProjectTaskGitState(
          head: committed ? 'new-head' : 'old-head',
          dirtyPaths: committed && paths.contains('ROADMAP.md')
              ? const ['ROADMAP.md']
              : const [],
        );
      },
    );
    expect(await workflow.run(), ProjectTaskReviewResult.stopped);
    expect(inspectedPaths.firstWhere((paths) => paths.isNotEmpty), [
      'lib/task.dart',
    ]);
    expect(inspectedPaths.last, ['lib/task.dart', 'ROADMAP.md']);
    expect(workflow.stopReason, contains('ROADMAP.md'));
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
  String reviewResponse = 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
  Future<bool> Function(String, ProjectTaskCommitScope)? prepareCommit,
  Future<ProjectTaskCommitSnapshot?> Function(ProjectTaskCommitScope)?
  readCommitSnapshot,
  ProjectTaskCommitTurnEvidence? Function()? readCommitTurnEvidence,
}) {
  final now = DateTime(2026);
  var calls = 0;
  return ProjectTaskReviewWorkflow(
    conversationId: 'task',
    readConversation: read,
    isSelected: () => true,
    isWaitingForUser: () => false,
    commit: (prompt, scope) => commit(prompt),
    projectRoot: '/repo',
    readCommitTurnEvidence: readCommitTurnEvidence,
    prepareCommit: prepareCommit ?? (_, _) async => true,
    readCommitSnapshot:
        readCommitSnapshot ??
        (scope) async =>
            fakeTaskCommitSnapshot(scope, (await readGitState([]))!.head),
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
                  ? reviewResponse
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
