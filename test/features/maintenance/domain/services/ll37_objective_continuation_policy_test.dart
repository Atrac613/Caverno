import 'package:caverno/features/maintenance/domain/entities/ll37_objective_verdict_record.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_continuation_policy.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_vote_policy.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = Ll37ObjectiveContinuationPolicy();

  test('builds a deterministic privacy-filtered anti-ratchet packet', () {
    final forward = policy.review(
      _aggregate([
        _record(voteIndex: 1, detail: 'feature remains false.'),
        _record(voteIndex: 2, detail: ' Feature   remains false. '),
      ]),
    );
    final reversed = policy.review(
      _aggregate([
        _record(voteIndex: 1, detail: ' Feature   remains false. '),
        _record(voteIndex: 2, detail: 'feature remains false.'),
      ]),
    );

    expect(forward.status, Ll37ObjectiveContinuationStatus.repairReview);
    expect(forward.canCopyRepairNudge, isTrue);
    expect(forward.gaps, hasLength(1));
    expect(forward.gaps.single.id, startsWith('ll37-gap-'));
    expect(forward.repairNudge, reversed.repairNudge);
    expect(forward.repairNudge, contains('Frozen objective'));
    expect(forward.repairNudge, contains('Do not change the objective'));
    expect(forward.repairNudge, contains('concrete defect'));
    expect(forward.repairNudge, isNot(contains('changed file contents')));
    expect(forward.repairNudge, isNot(contains('raw verifier response')));
    expect(forward.repairNudge, isNot(contains('secret implementation note')));
  });

  test('deduplicates equivalent gaps and preserves distinct concrete gaps', () {
    final review = policy.review(
      _aggregate([
        _record(voteIndex: 1, detail: ' Feature   remains false. '),
        _record(voteIndex: 2, detail: 'Feature remains false.'),
      ], extraFindings: true),
    );

    expect(review.gaps, hasLength(2));
    expect(review.gaps.map((gap) => gap.id).toSet(), hasLength(2));
    expect(review.repairNudge, contains('config.json'));
    expect(review.repairNudge, contains('verification'));
  });

  test('requires a user decision when the frozen contract disagrees', () {
    final review = policy.review(
      _aggregate([
        _record(voteIndex: 1),
        _record(voteIndex: 2, objective: 'Enable a different feature.'),
      ]),
    );

    expect(review.status, Ll37ObjectiveContinuationStatus.userDecisionRequired);
    expect(review.canCopyRepairNudge, isFalse);
    expect(review.repairNudge, isNull);
    expect(review.detail, contains('frozen objective contract'));
  });

  test('requires the frozen acceptance contract to keep its order', () {
    final review = policy.review(
      _aggregate([
        _record(
          voteIndex: 1,
          acceptanceCriteria: const ['Set the flag.', 'Keep the schema.'],
        ),
        _record(
          voteIndex: 2,
          acceptanceCriteria: const ['Keep the schema.', 'Set the flag.'],
        ),
      ]),
    );

    expect(review.status, Ll37ObjectiveContinuationStatus.userDecisionRequired);
    expect(review.canCopyRepairNudge, isFalse);
  });

  test(
    'does not issue repair work for not-refuted or unverifiable results',
    () {
      final accepted = policy.review(
        _aggregate([
          _record(voteIndex: 1, blocking: 'none'),
          _record(voteIndex: 2, blocking: 'none'),
        ]),
      );
      final split = policy.review(
        _aggregate([
          _record(voteIndex: 1, blocking: 'none'),
          _record(voteIndex: 2),
        ]),
      );

      expect(accepted.status, Ll37ObjectiveContinuationStatus.noAction);
      expect(accepted.canCopyRepairNudge, isFalse);
      expect(
        split.status,
        Ll37ObjectiveContinuationStatus.userDecisionRequired,
      );
      expect(split.canCopyRepairNudge, isFalse);
    },
  );
}

Ll37ObjectiveVoteAggregate _aggregate(
  List<Ll37ObjectiveVerdictRecord> records, {
  bool extraFindings = false,
}) {
  final routed = extraFindings
      ? [
          records.first,
          _record(
            voteIndex: 2,
            detail: records.last.findings.first.detail,
            extraFinding: true,
          ),
        ]
      : records;
  final profiles = Ll37VerifierFidelityRegistry.acceptedProfiles;
  return const Ll37ObjectiveVotePolicy()
      .plan(
        candidateId: 'worktree-agent:task-1',
        routes: profiles.map(
          (profile) => Ll37ObjectiveVoteRoute(
            verifierProfileKey: profile.profileKey,
            fidelityReportSha256: profile.reportSha256,
          ),
        ),
        history: routed,
      )
      .aggregate;
}

Ll37ObjectiveVerdictRecord _record({
  required int voteIndex,
  String blocking = 'contradiction',
  String objective = 'Set the feature flag.',
  List<String> acceptanceCriteria = const ['The flag is true.'],
  String detail = 'Feature remains false.',
  bool extraFinding = false,
}) {
  final profile = Ll37VerifierFidelityRegistry.acceptedProfiles[voteIndex - 1];
  return Ll37ObjectiveVerdictRecord(
    voteId: Ll37ObjectiveVoteRoute(
      verifierProfileKey: profile.profileKey,
      fidelityReportSha256: profile.reportSha256,
    ).voteId(candidateId: 'worktree-agent:task-1', voteIndex: voteIndex),
    voteIndex: voteIndex,
    candidateId: 'worktree-agent:task-1',
    sourceSurface: 'worktreeAgent',
    objective: objective,
    acceptanceCriteria: acceptanceCriteria,
    changedFilePaths: const ['config.json'],
    implementationEvidence: const ['secret implementation note'],
    verdict: blocking == 'none' ? 'notRefuted' : 'refuted',
    confidence: 1,
    blocking: blocking,
    findings: blocking == 'none'
        ? const []
        : [
            Ll37ObjectiveVerdictFindingRecord(
              kind: 'unmet_criterion',
              location: 'config.json',
              detail: detail,
            ),
            if (extraFinding)
              const Ll37ObjectiveVerdictFindingRecord(
                kind: 'verification_failure',
                location: 'verification',
                detail: 'The declared check was not re-run.',
              ),
          ],
    requestCount: 1,
    estimatedInputTokens: 20,
    estimatedOutputTokens: 10,
    verifierProvider: profile.provider.name,
    verifierBaseUrl: profile.baseUrl,
    verifierModel: profile.model,
    verifierProfileKey: profile.profileKey,
    fidelityReportSchemaVersion: profile.reportSchemaVersion,
    fidelityReportSha256: profile.reportSha256,
    recordedAt: DateTime.utc(2026, 8, 13, 0, voteIndex),
  );
}
