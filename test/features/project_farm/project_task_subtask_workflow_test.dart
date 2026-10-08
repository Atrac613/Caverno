import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/project_task_terminal_status.dart';
import 'package:caverno/features/project_farm/application/project_task_review_workflow.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_git_state.dart';
import 'package:caverno/features/project_farm/domain/project_task_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/project_task_commit_test_support.dart';

void main() {
  final now = DateTime(2026);
  const subtasks = [
    ConversationWorkflowTask(
      id: 'project-subtask-1',
      title: 'Add the parser',
      targetFiles: ['lib/parser.dart'],
    ),
    ConversationWorkflowTask(id: 'project-subtask-2', title: 'Wire it in'),
    ConversationWorkflowTask(id: 'project-subtask-3', title: 'Add tests'),
  ];

  late Conversation conversation;
  late List<String> stepPrompts;
  late List<String> sendPrompts;
  late List<String> marked;
  late List<ProjectTaskProgress> reports;
  late int commits;

  setUp(() {
    conversation = Conversation(
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
    stepPrompts = [];
    sendPrompts = [];
    marked = [];
    reports = [];
    commits = 0;
  });

  void reply(String content, {bool withDiff = false}) {
    final index = conversation.messages.length + 1;
    conversation = conversation.copyWith(
      messages: [
        ...conversation.messages,
        Message(
          id: 'assistant-$index',
          content: content,
          role: MessageRole.assistant,
          timestamp: now,
        ),
      ],
      turnDiffs: [
        ...conversation.turnDiffs,
        if (withDiff)
          TurnDiff(
            id: 'diff-$index',
            assistantMessageId: 'assistant-$index',
            userPromptPreview: 'task',
            timestamp: now,
            files: const [
              TurnDiffFile(
                filePath: 'lib/parser.dart',
                unifiedPatch: '@@ -1 +1 @@\n-old\n+new',
              ),
            ],
          ),
      ],
    );
  }

  ProjectTaskReviewWorkflow workflow({
    String subtaskReply = 'Done.\nPROJECT_TASK_SUBTASK_DONE',
    bool finalTurnEdits = true,
    ProjectTaskTerminalStatus? subtaskStatus,
    bool statusRequired = false,
    void Function(Map<String, Object?>)? onDecision,
    List<String> dirtyPaths = const [],
    List<bool>? reviewRoutes,
  }) => ProjectTaskReviewWorkflow(
    projectRoot: '/repo',
    prepareCommit: (_, _) async => true,
    readCommitSnapshot: (scope) async =>
        fakeTaskCommitSnapshot(scope, 'head-$commits'),
    conversationId: 'task',
    readConversation: () => conversation,
    isSelected: () => true,
    isWaitingForUser: () => false,
    decompose: (_) async => subtasks,
    readSubtaskStatus: statusRequired || subtaskStatus != null
        ? () => subtaskStatus
        : null,
    onDecision: onDecision,
    sendStep: (prompt) async {
      stepPrompts.add(prompt);
      reply(subtaskReply, withDiff: true);
      return true;
    },
    markSubtaskDone: (id) async => marked.add(id),
    onProgress: reports.add,
    send: (prompt, {required codeReview}) async {
      sendPrompts.add(prompt);
      reviewRoutes?.add(codeReview);
      if (codeReview) {
        reply('No findings.\nPROJECT_TASK_REVIEW_CLEAN');
      } else {
        reply(
          'Verified.\nPROJECT_TASK_READY_FOR_REVIEW',
          withDiff: finalTurnEdits,
        );
      }
      return true;
    },
    commit: (_, _) async {
      commits++;
      return true;
    },
    readGitState: (_) async => ProjectTaskGitState(
      head: 'head-$commits',
      dirtyPaths: commits == 0 ? dirtyPaths : const [],
    ),
  );

  group('resume', () {
    // The sidebar kept "findings remain" after manual fixes, and no run could
    // pick the task up again: the workflow only started on an empty thread.
    void stoppedAfter(Set<String> completed, {bool goalCompleted = false}) {
      reply('Earlier run.');
      conversation = conversation.copyWith(
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Implement task',
          tasks: subtasks,
        ),
        executionProgress: [
          for (final id in completed)
            ConversationExecutionTaskProgress(
              taskId: id,
              status: ConversationWorkflowTaskStatus.completed,
            ),
        ],
        goal: conversation.goal!.copyWith(
          status: goalCompleted
              ? ConversationGoalStatus.completed
              : ConversationGoalStatus.active,
        ),
      );
    }

    test('continues from the first unfinished subtask', () async {
      stoppedAfter({'project-subtask-1'});
      expect(await workflow().resume(), ProjectTaskReviewResult.committed);
      expect(stepPrompts, hasLength(1));
      expect(stepPrompts.single, contains('Wire it in'));
      expect(marked, ['project-subtask-2', 'project-subtask-3']);
    });

    test('reviews the current changes once every subtask is done', () async {
      stoppedAfter(subtasks.map((task) => task.id).toSet());
      conversation = conversation.copyWith(
        turnDiffs: [
          TurnDiff(
            id: 'manual',
            assistantMessageId: 'assistant-1',
            userPromptPreview: 'fix',
            timestamp: now,
            files: const [
              TurnDiffFile(
                filePath: 'lib/parser.dart',
                unifiedPatch: '@@ -1 +1 @@\n-old\n+new',
              ),
            ],
          ),
        ],
      );
      final routes = <bool>[];
      expect(
        await workflow(
          dirtyPaths: const ['lib/parser.dart'],
          reviewRoutes: routes,
        ).resume(),
        ProjectTaskReviewResult.committed,
      );
      expect(stepPrompts, isEmpty);
      expect(routes.first, isTrue, reason: 'no implementation turn first');
      expect(commits, 1);
    });

    test('a task with nothing uncommitted is already committed', () async {
      stoppedAfter(subtasks.map((task) => task.id).toSet());
      conversation = conversation.copyWith(
        turnDiffs: [
          TurnDiff(
            id: 'done',
            assistantMessageId: 'assistant-1',
            userPromptPreview: 'task',
            timestamp: now,
            files: const [TurnDiffFile(filePath: 'lib/parser.dart')],
          ),
        ],
      );
      expect(await workflow().resume(), ProjectTaskReviewResult.committed);
      expect(sendPrompts, isEmpty);
      expect(reports.last.outcome, ProjectTaskOutcome.committed);
    });

    test('an unstarted thread is not resumed', () async {
      expect(await workflow().resume(), ProjectTaskReviewResult.stopped);
      expect(sendPrompts, isEmpty);
    });
  });

  test(
    'a saved memory update after the subtask marker permits progression',
    () async {
      expect(
        await workflow(
          subtaskReply:
              'Verified.\nPROJECT_TASK_SUBTASK_DONE\n'
              '<tool_use>{"name":"memory_update","arguments":{"summaryUpdated":true}}</tool_use>',
        ).run(),
        ProjectTaskReviewResult.committed,
      );
      expect(stepPrompts, hasLength(2));
      expect(marked, [
        'project-subtask-1',
        'project-subtask-2',
        'project-subtask-3',
      ]);
    },
  );

  test('visible text after a marker still blocks progression', () async {
    expect(
      await workflow(
        subtaskReply:
            'PROJECT_TASK_SUBTASK_DONE\nRemaining work is unresolved.\n'
            '<tool_use>{"name":"memory_update","arguments":{}}</tool_use>',
      ).run(),
      ProjectTaskReviewResult.stopped,
    );
    expect(marked, isEmpty);
    expect(sendPrompts, isEmpty);
  });

  test('runs one turn per subtask and records each as done', () async {
    expect(await workflow().run(), ProjectTaskReviewResult.committed);

    expect(stepPrompts, hasLength(2));
    expect(
      stepPrompts.first,
      allOf(
        contains('1. [now] Add the parser (likely files: lib/parser.dart)'),
        contains('3. Add tests'),
        contains('PROJECT_TASK_SUBTASK_DONE'),
      ),
    );
    expect(stepPrompts.last, contains('1. [done] Add the parser'));
    expect(
      sendPrompts.first,
      allOf(contains('3. [now] Add tests'), contains('READY_FOR_REVIEW')),
    );
    expect(marked, [
      'project-subtask-1',
      'project-subtask-2',
      'project-subtask-3',
    ]);
  });

  test('reports each stage in order', () async {
    await workflow().run();

    expect(
      reports.map((r) => '${r.phase.name}:${r.subtaskIndex}/${r.subtaskCount}'),
      [
        'decompose:0/0',
        'implement:0/3',
        'implement:1/3',
        'implement:2/3',
        'review:2/3',
        'commit:2/3',
        'commit:2/3',
      ],
    );
    expect(reports.last.outcome, ProjectTaskOutcome.committed);
  });

  test('stops at a subtask whose response omits its marker', () async {
    final run = workflow(subtaskReply: 'I could not finish this.');

    expect(await run.run(), ProjectTaskReviewResult.stopped);
    expect(run.stopReason, contains('subtask 1'));
    expect(marked, isEmpty);
    expect(sendPrompts, isEmpty);
    expect(reports.last.phase, ProjectTaskPhase.implement);
    expect(reports.last.outcome, ProjectTaskOutcome.stopped);
  });

  test(
    'reports the harness rejection before the rewritten marker gap',
    () async {
      final decisions = <Map<String, Object?>>[];
      final run = workflow(
        subtaskReply: 'The current project subtask remains incomplete.',
        subtaskStatus: ProjectTaskTerminalStatus.subtask(
          taskId: 'project-subtask-1',
          accepted: false,
          gaps: ['Required subtask tool actions remain unexecuted.'],
          gapCodes: ['unexecuted_actions'],
        ),
        onDecision: decisions.add,
      );
      expect(await run.run(), ProjectTaskReviewResult.stopped);
      expect(
        run.stopReason,
        contains('Required subtask tool actions remain unexecuted.'),
      );
      expect(run.stopReason, isNot(contains('does not end with')));
      final decision = decisions.firstWhere(
        (value) => value['decision'] == 'stopped',
      );
      expect(decision['reason'], 'subtask 1 was rejected by the harness');
      expect(decision['gapCodes'], ['unexecuted_actions']);
      expect(marked, isEmpty);
      expect(sendPrompts, isEmpty);
    },
  );

  for (final verdict in [
    null,
    ProjectTaskTerminalStatus.subtask(taskId: 'other-task', accepted: true),
  ]) {
    test(
      'does not advance without the current subtask verdict: ${verdict?.subtaskId}',
      () async {
        final run = workflow(subtaskStatus: verdict, statusRequired: true);
        expect(await run.run(), ProjectTaskReviewResult.stopped);
        expect(run.stopReason, 'subtask 1 has no matching harness verdict');
        expect(marked, isEmpty);
        expect(sendPrompts, isEmpty);
      },
    );
  }

  test('accepts a last subtask that only verifies earlier edits', () async {
    // The change check counts from before the first subtask, so a final
    // verification-only turn does not read as "no reviewable change".
    expect(
      await workflow(finalTurnEdits: false).run(),
      ProjectTaskReviewResult.committed,
    );
  });

  test('runs the task as one step when decomposition gives nothing', () async {
    final run = ProjectTaskReviewWorkflow(
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, 'head-$commits'),
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      decompose: (_) async => const [],
      sendStep: (prompt) async {
        stepPrompts.add(prompt);
        return true;
      },
      onProgress: reports.add,
      send: (prompt, {required codeReview}) async {
        sendPrompts.add(prompt);
        codeReview
            ? reply('No findings.\nPROJECT_TASK_REVIEW_CLEAN')
            : reply('Verified.\nPROJECT_TASK_READY_FOR_REVIEW', withDiff: true);
        return true;
      },
      commit: (_, _) async {
        commits++;
        return true;
      },
      readGitState: (_) async =>
          ProjectTaskGitState(head: 'head-$commits', dirtyPaths: const []),
    );

    expect(await run.run(), ProjectTaskReviewResult.committed);
    expect(stepPrompts, isEmpty);
    expect(sendPrompts.first, isNot(contains('Subtasks:')));
    expect(reports[1].subtaskCount, 1);
  });

  test('does not record a subtask whose verification failed', () async {
    // Coding verification marks the subtask blocked when the turn's tests
    // fail; the model's done marker must not overwrite that verdict.
    final run = ProjectTaskReviewWorkflow(
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, 'head-$commits'),
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      decompose: (_) async => subtasks,
      sendStep: (prompt) async {
        reply('Done.\nPROJECT_TASK_SUBTASK_DONE', withDiff: true);
        conversation = conversation.copyWith(
          executionProgress: [
            const ConversationExecutionTaskProgress(
              taskId: 'project-subtask-1',
              status: ConversationWorkflowTaskStatus.blocked,
              validationStatus: ConversationExecutionValidationStatus.failed,
              lastValidationSummary: '2 tests failed',
            ),
          ],
        );
        return true;
      },
      markSubtaskDone: (id) async => marked.add(id),
      onProgress: reports.add,
      send: (prompt, {required codeReview}) async => true,
      commit: (_, _) async => true,
      readGitState: (_) async => null,
    );

    expect(await run.run(), ProjectTaskReviewResult.stopped);
    expect(
      run.stopReason,
      'subtask 1 ended with failed verification: 2 tests failed',
    );
    expect(marked, isEmpty);
  });

  test('reviews and commits an earlier run\'s uncommitted change', () async {
    // Session b2971ae0: the re-run made no edit because the work was done.
    final commitPrompts = <String>[];
    final run = ProjectTaskReviewWorkflow(
      projectRoot: '/repo',
      prepareCommit: (_, _) async => true,
      readCommitSnapshot: (scope) async =>
          fakeTaskCommitSnapshot(scope, 'head-$commits'),
      conversationId: 'task',
      readConversation: () => conversation,
      isSelected: () => true,
      isWaitingForUser: () => false,
      // Two captured edits of one file, as an earlier run with two turns
      // leaves; session 80dc7079 listed the path twice.
      inheritedFiles: const [
        TurnDiffFile(filePath: '/repo/.gitignore', unifiedPatch: '@@ -1 +1 @@'),
        TurnDiffFile(
          filePath: '/repo/.gitignore',
          unifiedPatch: '@@ -1 +1,2 @@\n state.json\n+config.json',
        ),
      ],
      send: (prompt, {required codeReview}) async {
        sendPrompts.add(prompt);
        codeReview
            ? reply('No findings.\nPROJECT_TASK_REVIEW_CLEAN')
            : reply(
                'Already in place and verified.\nPROJECT_TASK_READY_FOR_REVIEW',
              );
        return true;
      },
      commit: (prompt, scope) async {
        commitPrompts.add(prompt);
        commits++;
        return true;
      },
      readGitState: (_) async =>
          ProjectTaskGitState(head: 'head-$commits', dirtyPaths: const []),
    );

    expect(await run.run(), ProjectTaskReviewResult.committed);
    expect(
      sendPrompts.first,
      contains('left these changes uncommitted: /repo/.gitignore. Treat'),
    );
    expect(
      sendPrompts[1],
      allOf(contains('+config.json'), contains('earlier run of this task')),
    );
    expect(commitPrompts.single, contains('- /repo/.gitignore'));
  });

  test('reviews the net task change, not stacked captured patches', () async {
    // Session be9dbba9: eight earlier runs left 29 captured patches for 7
    // files, 44,502 characters, and the workflow stopped before review.
    final stacked = [
      for (var turn = 0; turn < 2; turn++)
        TurnDiffFile(
          filePath: '/repo/watcher.py',
          unifiedPatch: '@@ -1 +1 @@\n${'+stale turn $turn\n' * 1200}',
        ),
    ];
    final requested = <List<String>>[];
    ProjectTaskReviewWorkflow workflow({required bool readsGit}) =>
        ProjectTaskReviewWorkflow(
          projectRoot: '/repo',
          prepareCommit: (_, _) async => true,
          readCommitSnapshot: (scope) async =>
              fakeTaskCommitSnapshot(scope, 'head-$commits'),
          conversationId: 'task',
          readConversation: () => conversation,
          isSelected: () => true,
          isWaitingForUser: () => false,
          inheritedFiles: stacked,
          send: (prompt, {required codeReview}) async {
            sendPrompts.add(prompt);
            codeReview
                ? reply('No findings.\nPROJECT_TASK_REVIEW_CLEAN')
                : reply('Verified.\nPROJECT_TASK_READY_FOR_REVIEW');
            return true;
          },
          commit: (_, _) async {
            commits++;
            return true;
          },
          readGitState: (_) async =>
              ProjectTaskGitState(head: 'head-$commits', dirtyPaths: const []),
          readTaskPatch: readsGit
              ? (paths) async {
                  requested.add(paths);
                  return const [
                    TurnDiffFile(
                      filePath: 'watcher.py',
                      unifiedPatch: '@@ -1 +1 @@\n-print(x)\n+logger.info(x)',
                    ),
                  ];
                }
              : null,
        );

    final fresh = conversation;
    // Without a git reader the stacked captures are too large to inline;
    // the reviewer gets each path once and reads the net diff from git
    // (session d8ffeb92 stopped here with a finished implementation).
    expect(
      await workflow(readsGit: false).run(),
      ProjectTaskReviewResult.committed,
    );
    expect(
      sendPrompts[1],
      allOf(
        contains('too large to include in full here'),
        isNot(contains('stale turn')),
        contains('diff HEAD -- <path>'),
      ),
    );
    expect('- /repo/watcher.py ('.allMatches(sendPrompts[1]), hasLength(1));

    conversation = fresh;
    sendPrompts.clear();
    expect(
      await workflow(readsGit: true).run(),
      ProjectTaskReviewResult.committed,
    );
    expect(requested.first, ['/repo/watcher.py']);
    expect(
      sendPrompts[1],
      allOf(contains('+logger.info(x)'), isNot(contains('stale turn'))),
    );
  });

  test(
    'records earlier subtask changes before a verify-only last turn',
    () async {
      // Session 6f3ea3cf: the last subtask only verified README edits made in
      // the two before it, and the per-turn change check refused completion.
      final recorded = <List<String>>[];
      final run = ProjectTaskReviewWorkflow(
        projectRoot: '/repo',
        prepareCommit: (_, _) async => true,
        readCommitSnapshot: (scope) async =>
            fakeTaskCommitSnapshot(scope, 'head-$commits'),
        conversationId: 'task',
        readConversation: () => conversation,
        isSelected: () => true,
        isWaitingForUser: () => false,
        decompose: (_) async => subtasks,
        sendStep: (prompt) async {
          reply('Done.\nPROJECT_TASK_SUBTASK_DONE', withDiff: true);
          return true;
        },
        recordPriorChanges: (paths) async => recorded.add(paths),
        send: (prompt, {required codeReview}) async {
          codeReview
              ? reply('No findings.\nPROJECT_TASK_REVIEW_CLEAN')
              : reply('Verified.\nPROJECT_TASK_READY_FOR_REVIEW');
          return true;
        },
        commit: (_, _) async {
          commits++;
          return true;
        },
        readGitState: (_) async =>
            ProjectTaskGitState(head: 'head-$commits', dirtyPaths: const []),
      );

      expect(await run.run(), ProjectTaskReviewResult.committed);
      expect(recorded, [
        ['lib/parser.dart'],
      ]);
    },
  );
}
