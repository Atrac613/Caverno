import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/anabasis_acceptance_elicitation.dart';
import 'package:test/test.dart';

const _elicitation = AnabasisAcceptanceElicitation();

WorktreeAgentTask _worktreeChild({
  String id = 'child-1',
  String workflowTaskId = 'task-1',
  WorktreeAgentTaskStatus status = WorktreeAgentTaskStatus.completed,
  String verificationCommand = 'dart test',
  bool verifiedGreen = true,
  List<WorktreeAgentChangedFileEvidence> changedFiles = const [
    WorktreeAgentChangedFileEvidence(path: 'lib/sync/engine.dart'),
  ],
  List<String> expectedTargetFiles = const ['lib/sync/engine.dart'],
}) => WorktreeAgentTask(
  id: id,
  title: 'Build the sync engine',
  status: status,
  workflowTaskId: workflowTaskId,
  branchName: 'anabasis/build-sync',
  worktreePath: '/tmp/worktrees/build-sync',
  createdAt: DateTime(2026, 9, 13),
  updatedAt: DateTime(2026, 9, 13),
  verificationCommand: verificationCommand,
  verifiedGreen: verifiedGreen,
  changedFiles: changedFiles,
  expectedTargetFiles: expectedTargetFiles,
);

SubagentTask _subagentChild({
  String id = 'sub-1',
  String workflowTaskId = 'task-2',
  SubagentTaskStatus status = SubagentTaskStatus.completed,
  String resultSummary = 'Read the spec and summarized it',
}) => SubagentTask(
  id: id,
  conversationId: 'conversation-1',
  workflowTaskId: workflowTaskId,
  status: status,
  description: 'Summarize the spec',
  resultSummary: resultSummary,
);

AcceptanceElicitationPlan _decide({
  bool isParentTurn = true,
  List<WorktreeAgentTask> worktreeChildren = const [],
  List<SubagentTask> children = const [],
  Set<String> acceptedTaskIds = const {},
  Set<String> alreadyElicitedTaskIds = const {},
}) => _elicitation.decide(
  isParentTurn: isParentTurn,
  worktreeChildren: worktreeChildren,
  children: children,
  acceptedTaskIds: acceptedTaskIds,
  alreadyElicitedTaskIds: alreadyElicitedTaskIds,
);

void main() {
  group('when a judgement is owed', () {
    test('a verified worktree result with changed files is eligible', () {
      final plan = _decide(worktreeChildren: [_worktreeChild()]);

      expect(plan.eligibility, AcceptanceElicitationEligibility.eligible);
      expect(plan.candidates.single.workflowTaskId, 'task-1');
      expect(
        plan.candidates.single.evidence,
        containsAll(<String>[
          'worktree branch anabasis/build-sync',
          'verified green: dart test',
        ]),
        reason:
            'the turn is asked to judge, not to re-gather what the audit '
            'already read',
      );
    });

    test('a finished inspecting child is eligible on its summary', () {
      final plan = _decide(children: [_subagentChild()]);

      expect(plan.eligibility, AcceptanceElicitationEligibility.eligible);
      expect(plan.candidates.single.workflowTaskId, 'task-2');
    });
  });

  group('when nothing is owed', () {
    test('an ordinary turn is never asked to accept', () {
      final plan = _decide(
        isParentTurn: false,
        worktreeChildren: [_worktreeChild()],
      );

      expect(plan.eligibility, AcceptanceElicitationEligibility.notParentTurn);
      expect(plan.candidates, isEmpty);
    });

    test('a running branch is not judgeable', () {
      final plan = _decide(
        worktreeChildren: [
          _worktreeChild(status: WorktreeAgentTaskStatus.running),
        ],
      );

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.noJudgeableResult,
        reason:
            'the write path answers a running branch with "poll until it is '
            'done", which is advice a turn holding one tool cannot take',
      );
    });

    test('a failed verification is left to a turn that can go and fix it', () {
      final plan = _decide(
        worktreeChildren: [_worktreeChild(verifiedGreen: false)],
      );

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.noJudgeableResult,
      );
    });

    test('a child that reported nothing leaves nothing to judge', () {
      final plan = _decide(children: [_subagentChild(resultSummary: '')]);

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.noJudgeableResult,
      );
    });

    test('an already accepted task is not put to the parent twice', () {
      final plan = _decide(
        worktreeChildren: [_worktreeChild()],
        acceptedTaskIds: {'task-1'},
      );

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.noJudgeableResult,
      );
    });

    test('declining sticks: one elicitation per result', () {
      final plan = _decide(
        worktreeChildren: [_worktreeChild()],
        alreadyElicitedTaskIds: {'task-1'},
      );

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.alreadyElicited,
        reason:
            'a parent that declined leaves the result exactly as eligible as '
            'it was, so an unguarded trigger asks again forever',
      );
    });

    test('a child bound to no saved task is nobody\'s to accept', () {
      final plan = _decide(
        worktreeChildren: [_worktreeChild(workflowTaskId: '')],
      );

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.noJudgeableResult,
      );
    });
  });

  group('when both runners ran for one task', () {
    test('the worktree result is the one described', () {
      final plan = _decide(
        worktreeChildren: [_worktreeChild(workflowTaskId: 'task-9')],
        children: [_subagentChild(workflowTaskId: 'task-9')],
      );

      expect(plan.candidates, hasLength(1));
      expect(
        plan.candidates.single.childId,
        'child-1',
        reason:
            'the worktree result is the only kind that can pass a level, and '
            'the write path will rest on it',
      );
    });

    test('a still-running branch outranks a finished subagent summary', () {
      final plan = _decide(
        worktreeChildren: [
          _worktreeChild(
            workflowTaskId: 'task-9',
            status: WorktreeAgentTaskStatus.running,
          ),
        ],
        children: [_subagentChild(workflowTaskId: 'task-9')],
      );

      expect(
        plan.eligibility,
        AcceptanceElicitationEligibility.noJudgeableResult,
        reason:
            'the branch is the result the acceptance will rest on, so it '
            'decides whether the task is judgeable yet',
      );
    });
  });

  group('the prompt', () {
    test('names the id the tool takes and offers declining', () {
      final plan = _decide(worktreeChildren: [_worktreeChild()]);
      final prompt = AnabasisAcceptanceElicitationPrompt.build(
        languageCode: 'ja',
        candidates: plan.candidates,
      );

      expect(
        prompt,
        startsWith('@anabasis '),
        reason: 'accept_task refuses every turn that is not the parent\'s',
      );
      expect(prompt, contains('accept_task workflow_task_id: task-1'));
      expect(prompt, contains('do not call the tool'));
      expect(prompt, contains('"ja"'));
    });
  });

  group('the ledger', () {
    test('remembers per conversation and nowhere else', () {
      final ledger = AnabasisAcceptanceElicitationLedger();
      ledger.recordElicited(
        conversationId: 'conversation-1',
        workflowTaskIds: const ['task-1'],
      );

      expect(ledger.elicitedFor('conversation-1'), {'task-1'});
      expect(ledger.elicitedFor('conversation-2'), isEmpty);
    });
  });
}
