import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/task_acceptance_audit.dart';
import 'package:test/test.dart';

const _audit = TaskAcceptanceAudit();

WorktreeAgentTask _worktreeTask({
  String verificationCommand = 'dart test',
  bool verifiedGreen = true,
  List<WorktreeAgentChangedFileEvidence> changedFiles = const [
    WorktreeAgentChangedFileEvidence(path: 'lib/sync/engine.dart'),
  ],
  bool truncated = false,
}) {
  return WorktreeAgentTask(
    id: 'task-1',
    title: 'Build the sync engine',
    branchName: 'anabasis/build-sync',
    worktreePath: '/tmp/worktrees/build-sync',
    createdAt: DateTime(2026, 9, 4),
    updatedAt: DateTime(2026, 9, 4),
    verificationCommand: verificationCommand,
    verifiedGreen: verifiedGreen,
    changedFiles: changedFiles,
    changedFileEvidenceTruncated: truncated,
  );
}

void main() {
  group('a worktree child', () {
    test('green tests and real files pass the two derivable levels', () {
      final verdict = _audit.auditWorktreeResult(_worktreeTask());

      expect(verdict.passed, {
        AcceptanceLevel.mechanical,
        AcceptanceLevel.evidence,
      });
    });

    test('a failing verification owes the mechanical level', () {
      final verdict = _audit.auditWorktreeResult(
        _worktreeTask(verifiedGreen: false),
      );

      expect(verdict.outstanding, contains(AcceptanceLevel.mechanical));
      expect(verdict.passed, isNot(contains(AcceptanceLevel.mechanical)));
    });

    test('no verification command owes nothing and proves nothing', () {
      final verdict = _audit.auditWorktreeResult(
        _worktreeTask(verificationCommand: '', verifiedGreen: false),
      );

      expect(
        verdict.notApplicable,
        contains(AcceptanceLevel.mechanical),
        reason:
            'Nothing was claimed mechanically, so nothing is owed — which is '
            'not the same as having passed, and keeping the two apart is the '
            'whole reason the third set exists.',
      );
      expect(verdict.passed, isNot(contains(AcceptanceLevel.mechanical)));
      expect(verdict.outstanding, isNot(contains(AcceptanceLevel.mechanical)));
    });

    test('a child that changed nothing owes the evidence level', () {
      final verdict = _audit.auditWorktreeResult(
        _worktreeTask(changedFiles: const []),
      );

      expect(
        verdict.outstanding,
        contains(AcceptanceLevel.evidence),
        reason:
            'A worktree child was routed there because the work changes files. '
            'Green tests over an unchanged tree is the shape of a claim '
            'without a result.',
      );
    });

    test('truncated evidence is not evidence', () {
      final verdict = _audit.auditWorktreeResult(
        _worktreeTask(truncated: true),
      );

      expect(
        verdict.outstanding,
        contains(AcceptanceLevel.evidence),
        reason:
            'A partial list cannot show the artifacts match the claim, only '
            'that some of them might.',
      );
    });
  });

  group('an inspecting child', () {
    test('is not asked for files it was never going to change', () {
      final verdict = _audit.auditSubagentResult(
        const SubagentTask(
          id: 'sub-1',
          resultSummary: 'The index is inverted.',
        ),
      );

      expect(verdict.notApplicable, {
        AcceptanceLevel.mechanical,
        AcceptanceLevel.evidence,
      });
    });

    test('but a child that reported nothing owes the evidence level', () {
      final verdict = _audit.auditSubagentResult(
        const SubagentTask(id: 'sub-1'),
      );

      expect(
        verdict.outstanding,
        contains(AcceptanceLevel.evidence),
        reason:
            'An empty summary leaves the parent nothing to judge, so the level '
            'is owed rather than inapplicable.',
      );
    });
  });

  group('what nothing here decides', () {
    test('the semantic and user levels always stay outstanding', () {
      for (final verdict in [
        _audit.auditWorktreeResult(_worktreeTask()),
        _audit.auditSubagentResult(
          const SubagentTask(id: 'sub-1', resultSummary: 'Done.'),
        ),
      ]) {
        expect(verdict.outstanding, contains(AcceptanceLevel.semantic));
        expect(verdict.outstanding, contains(AcceptanceLevel.user));
        expect(
          verdict.isAccepted,
          isFalse,
          reason:
              'Nothing derives a judgement or a person\'s decision, so nothing '
              'here can accept a result. That is the honest answer while the '
              'parent has no way to record one, and it is what stops "the '
              'tests are green" being read as "the goal is met".',
        );
      }
    });
  });

  group('what the parent may accept', () {
    test('a green, evidenced result may be accepted', () {
      expect(
        _audit.mayParentAccept(_audit.auditWorktreeResult(_worktreeTask())),
        isTrue,
        reason:
            'Levels 1 and 2 are settled; level 3 is what the parent is about '
            'to supply by judging.',
      );
    });

    test('a failing verification cannot be judged past', () {
      expect(
        _audit.mayParentAccept(
          _audit.auditWorktreeResult(_worktreeTask(verifiedGreen: false)),
        ),
        isFalse,
        reason:
            'A confident rationale cannot stand in for a test that did not '
            'pass. That asymmetry is what "only evidence promotes it" means.',
      );
    });

    test('a result with no artifacts cannot be judged past either', () {
      expect(
        _audit.mayParentAccept(
          _audit.auditWorktreeResult(_worktreeTask(changedFiles: const [])),
        ),
        isFalse,
      );
    });

    test('a lapsed premise bars acceptance on its own', () {
      expect(
        _audit.mayParentAccept(
          _audit.auditWorktreeResult(_worktreeTask()),
          lapsedPremises: const ['Existing entities have stable UUIDs'],
        ),
        isFalse,
        reason:
            "ANA2's contradiction policy arriving where it decides something: "
            'the child is never stopped, the promotion is.',
      );
    });

    test('an inspecting child that reported something may be accepted', () {
      expect(
        _audit.mayParentAccept(
          _audit.auditSubagentResult(
            const SubagentTask(
              id: 'sub-1',
              resultSummary: 'The index is FTS5.',
            ),
          ),
        ),
        isTrue,
        reason:
            'Both derivable levels are inapplicable to an inspection, so '
            'nothing mechanical is owed and the judgement is the whole test.',
      );
    });

    test('an inspecting child that reported nothing may not', () {
      expect(
        _audit.mayParentAccept(
          _audit.auditSubagentResult(const SubagentTask(id: 'sub-1')),
        ),
        isFalse,
      );
    });
  });
}
