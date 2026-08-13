import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_worktree_agent_candidate_adapter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = Ll37WorktreeAgentCandidateAdapter();

  test('adapts complete mechanically-green evidence in newest-first order', () {
    final older = _eligibleTask(id: 'older', minute: 1);
    final newer = _eligibleTask(id: 'newer', minute: 2);

    final candidates = adapter.adapt([older, newer]);

    expect(candidates.map((candidate) => candidate.id), [
      'worktree-agent:newer',
      'worktree-agent:older',
    ]);
    final candidate = candidates.first;
    expect(candidate.sourceSurface, Ll37ObjectiveSourceSurface.worktreeAgent);
    expect(candidate.attended, isFalse);
    expect(candidate.ll34OutcomeSettled, isFalse);
    expect(candidate.objective, 'Update the greeting implementation.');
    expect(candidate.acceptanceCriteria, ['lib/greeting.dart returns hello.']);
    expect(candidate.changedFiles.single.path, 'lib/greeting.dart');
    expect(candidate.changedFiles.single.content, contains('hello'));
    expect(candidate.implementationEvidence, hasLength(2));
  });

  test('keeps only the newest record for a duplicate task id', () {
    final older = _eligibleTask(id: 'same', minute: 1);
    final newerInvalid = _eligibleTask(
      id: 'same',
      minute: 2,
    ).copyWith(verifiedGreen: false);

    final candidates = adapter.adapt([older, newerInvalid]);

    expect(candidates, isEmpty);
  });

  test('rejects incomplete or mechanically unsettled task records', () {
    final base = _eligibleTask();
    final invalid = [
      base.copyWith(status: WorktreeAgentTaskStatus.failed),
      base.copyWith(verifiedGreen: false),
      base.copyWith(changedFileEvidenceTruncated: true),
      base.copyWith(prompt: ''),
      base.copyWith(verificationCommand: ''),
      base.copyWith(objectiveAcceptanceCriteria: const []),
      base.copyWith(verificationSummary: ''),
      base.copyWith(changedFiles: const []),
      base.copyWith(
        changedFiles: [base.changedFiles.single.copyWith(truncated: true)],
      ),
    ];

    for (final task in invalid) {
      expect(adapter.adapt([task]), isEmpty);
    }
  });

  test('rejects unsafe duplicated size or hash-inconsistent file evidence', () {
    final base = _eligibleTask();
    final file = base.changedFiles.single;
    final invalid = [
      base.copyWith(changedFiles: [file.copyWith(path: '../secret.txt')]),
      base.copyWith(changedFiles: [file.copyWith(path: '/tmp/secret.txt')]),
      base.copyWith(changedFiles: [file.copyWith(byteSize: 1)]),
      base.copyWith(changedFiles: [file.copyWith(contentHash: 'wrong')]),
      base.copyWith(
        changedFiles: [
          file,
          file.copyWith(path: './lib/greeting.dart'),
        ],
      ),
      base.copyWith(
        changedFiles: [
          file.copyWith(deleted: true, content: 'still present', byteSize: 13),
        ],
      ),
    ];

    for (final task in invalid) {
      expect(adapter.adapt([task]), isEmpty);
    }
  });

  test('normalizes safe paths and admits internally consistent deletions', () {
    final base = _eligibleTask();
    final task = base.copyWith(
      changedFiles: const [
        WorktreeAgentChangedFileEvidence(
          path: r'lib\legacy.dart',
          deleted: true,
        ),
      ],
    );

    final file = adapter.adapt([task]).single.changedFiles.single;

    expect(file.path, 'lib/legacy.dart');
    expect(file.content, isEmpty);
  });

  test('session ledger records stable candidate ids once', () {
    final ledger = Ll37ObjectiveAttemptLedger();

    expect(ledger.record(' worktree-agent:task-1 '), isTrue);
    expect(ledger.record('worktree-agent:task-1'), isFalse);
    expect(ledger.record(''), isFalse);
    expect(ledger.contains('worktree-agent:task-1'), isTrue);
    expect(ledger.length, 1);
  });
}

WorktreeAgentTask _eligibleTask({String id = 'task-1', int minute = 1}) {
  const content = "String greeting() => 'hello';\n";
  final bytes = utf8.encode(content);
  final now = DateTime.utc(2026, 8, 13, 0, minute);
  return WorktreeAgentTask(
    id: id,
    status: WorktreeAgentTaskStatus.completed,
    title: 'Update greeting',
    prompt: 'Update the greeting implementation.',
    branchName: 'feature/ll13-$id',
    worktreePath: '/tmp/caverno-worktrees/$id',
    verificationCommand: 'dart test',
    objectiveAcceptanceCriteria: const ['lib/greeting.dart returns hello.'],
    createdAt: now.subtract(const Duration(minutes: 1)),
    updatedAt: now,
    finishedAt: now,
    resultSummary: 'Updated the greeting implementation.',
    verifiedGreen: true,
    verificationSummary: 'Verification passed: dart test (exit code 0).',
    changedFiles: [
      WorktreeAgentChangedFileEvidence(
        path: 'lib/greeting.dart',
        content: content,
        contentHash: sha256.convert(bytes).toString(),
        byteSize: bytes.length,
      ),
    ],
  );
}
