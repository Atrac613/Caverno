import 'package:caverno/features/maintenance/domain/entities/ll37_objective_verdict_record.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_vote_identity.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_vote_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const candidateId = 'worktree-agent:task-1';
  const firstRoute = Ll37ObjectiveVoteRoute(
    verifierProfileKey: 'openAiCompatible|http://127.0.0.1:1234/v1|model-35b',
    fidelityReportSha256: 'FIRST123',
  );
  const secondRoute = Ll37ObjectiveVoteRoute(
    verifierProfileKey: 'openAiCompatible|http://127.0.0.1:1234/v1|model-27b',
    fidelityReportSha256: 'SECOND456',
  );
  const thirdRoute = Ll37ObjectiveVoteRoute(
    verifierProfileKey: 'openAiCompatible|http://127.0.0.1:1234/v1|model-third',
    fidelityReportSha256: 'THIRD789',
  );
  const routes = [firstRoute, secondRoute];
  const policy = Ll37ObjectiveVotePolicy();

  test('builds a normalized immutable identity for each bounded slot', () {
    final first = Ll37ObjectiveVoteIdentity.build(
      candidateId: ' $candidateId ',
      verifierProfileKey: ' ${firstRoute.verifierProfileKey} ',
      fidelityReportSha256: firstRoute.fidelityReportSha256,
      voteIndex: 1,
    );
    final equivalent = Ll37ObjectiveVoteIdentity.build(
      candidateId: candidateId,
      verifierProfileKey: firstRoute.verifierProfileKey,
      fidelityReportSha256: firstRoute.fidelityReportSha256.toLowerCase(),
      voteIndex: 1,
    );
    final second = secondRoute.voteId(candidateId: candidateId, voteIndex: 2);

    expect(first, equivalent);
    expect(first, startsWith('ll37-v1-'));
    expect(second, isNot(first));
    expect(
      () => Ll37ObjectiveVoteIdentity.build(
        candidateId: candidateId,
        verifierProfileKey: firstRoute.verifierProfileKey,
        fidelityReportSha256: firstRoute.fidelityReportSha256,
        voteIndex: 4,
      ),
      throwsRangeError,
    );
  });

  test('advances append-only route slots while the aggregate is pending', () {
    final empty = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: const [],
    );
    final oneVote = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: [_record(voteIndex: 1, blocking: 'none', route: firstRoute)],
    );

    expect(empty.shouldRequest, isTrue);
    expect(empty.nextVoteIndex, 1);
    expect(
      empty.nextRoute?.normalizedProfileKey,
      firstRoute.verifierProfileKey,
    );
    expect(oneVote.aggregate.status, Ll37ObjectiveVoteAggregateStatus.pending);
    expect(oneVote.aggregate.maxVoteCount, 2);
    expect(oneVote.nextVoteIndex, 2);
    expect(
      oneVote.nextRoute?.normalizedProfileKey,
      secondRoute.verifierProfileKey,
    );
    expect(
      oneVote.nextVoteId,
      secondRoute.voteId(candidateId: candidateId, voteIndex: 2),
    );
  });

  test('converges after two distinct routes agree', () {
    final refuted = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: [
        _record(voteIndex: 1, blocking: 'contradiction', route: firstRoute),
        _record(voteIndex: 2, blocking: 'contradiction', route: secondRoute),
      ],
    );
    final accepted = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: [
        _record(voteIndex: 1, blocking: 'none', route: firstRoute),
        _record(voteIndex: 2, blocking: 'none', route: secondRoute),
      ],
    );

    expect(refuted.shouldRequest, isFalse);
    expect(
      refuted.aggregate.outcome,
      Ll37ObjectiveVoteAggregateOutcome.refuted,
    );
    expect(refuted.aggregate.blocking, Ll37ObjectiveBlocking.contradiction);
    expect(
      accepted.aggregate.outcome,
      Ll37ObjectiveVoteAggregateOutcome.notRefuted,
    );
    expect(accepted.aggregate.blocking, Ll37ObjectiveBlocking.none);
  });

  test('stalls when distinct routes report the same unverifiable gap', () {
    final plan = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: [
        _record(
          voteIndex: 1,
          blocking: 'unverifiable',
          error: ' Endpoint   offline ',
          route: firstRoute,
        ),
        _record(
          voteIndex: 2,
          blocking: 'unverifiable',
          error: 'endpoint offline',
          route: secondRoute,
        ),
      ],
    );

    expect(plan.shouldRequest, isFalse);
    expect(plan.aggregate.status, Ll37ObjectiveVoteAggregateStatus.stalled);
    expect(
      plan.aggregate.outcome,
      Ll37ObjectiveVoteAggregateOutcome.unverifiable,
    );
  });

  test('caps a two-route disagreement without a same-route tie-break', () {
    final plan = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: [
        _record(voteIndex: 1, blocking: 'none', route: firstRoute),
        _record(voteIndex: 2, blocking: 'contradiction', route: secondRoute),
      ],
    );

    expect(plan.shouldRequest, isFalse);
    expect(plan.nextVoteIndex, isNull);
    expect(plan.aggregate.status, Ll37ObjectiveVoteAggregateStatus.capped);
    expect(
      plan.aggregate.outcome,
      Ll37ObjectiveVoteAggregateOutcome.unverifiable,
    );
    expect(plan.aggregate.blocking, Ll37ObjectiveBlocking.unverifiable);
  });

  test('uses an independently measured third route only when registered', () {
    final pending = policy.plan(
      candidateId: candidateId,
      routes: const [firstRoute, secondRoute, thirdRoute],
      history: [
        _record(voteIndex: 1, blocking: 'none', route: firstRoute),
        _record(voteIndex: 2, blocking: 'contradiction', route: secondRoute),
      ],
    );
    final capped = policy.plan(
      candidateId: candidateId,
      routes: const [firstRoute, secondRoute, thirdRoute],
      history: [
        _record(voteIndex: 1, blocking: 'none', route: firstRoute),
        _record(voteIndex: 2, blocking: 'contradiction', route: secondRoute),
        _record(
          voteIndex: 3,
          blocking: 'unverifiable',
          error: 'insufficient evidence',
          route: thirdRoute,
        ),
      ],
    );

    expect(pending.shouldRequest, isTrue);
    expect(pending.nextVoteIndex, 3);
    expect(
      pending.nextRoute?.normalizedProfileKey,
      thirdRoute.verifierProfileKey,
    );
    expect(capped.shouldRequest, isFalse);
    expect(capped.aggregate.status, Ll37ObjectiveVoteAggregateStatus.capped);
  });

  test('ignores mismatched route slots and tampered identities', () {
    final valid = _record(voteIndex: 1, blocking: 'none', route: firstRoute);
    final repeatedFirstRoute = _record(
      voteIndex: 2,
      blocking: 'none',
      route: firstRoute,
    );
    final wrongFirstSlot = _record(
      voteIndex: 1,
      blocking: 'none',
      route: secondRoute,
    );
    final tampered = _record(
      voteIndex: 2,
      blocking: 'none',
      route: secondRoute,
      voteId: 'tampered',
    );

    final plan = policy.plan(
      candidateId: candidateId,
      routes: routes,
      history: [valid, repeatedFirstRoute, wrongFirstSlot, tampered],
    );

    expect(plan.aggregate.votes, [valid]);
    expect(plan.nextVoteIndex, 2);
    expect(
      plan.nextRoute?.normalizedProfileKey,
      secondRoute.verifierProfileKey,
    );
  });
}

Ll37ObjectiveVerdictRecord _record({
  required int voteIndex,
  required String blocking,
  required Ll37ObjectiveVoteRoute route,
  String? error,
  String? voteId,
}) {
  const candidateId = 'worktree-agent:task-1';
  final verdict = switch (blocking) {
    'none' => 'notRefuted',
    'contradiction' => 'refuted',
    _ => 'unverifiable',
  };
  return Ll37ObjectiveVerdictRecord(
    voteId:
        voteId ?? route.voteId(candidateId: candidateId, voteIndex: voteIndex),
    voteIndex: voteIndex,
    candidateId: candidateId,
    sourceSurface: 'worktreeAgent',
    objective: 'Set the feature flag.',
    acceptanceCriteria: const ['The flag is true.'],
    changedFilePaths: const ['config.json'],
    implementationEvidence: const ['Verification result: passed'],
    verdict: verdict,
    confidence: 1,
    blocking: blocking,
    findings: blocking == 'contradiction'
        ? const [
            Ll37ObjectiveVerdictFindingRecord(
              kind: 'unmet_criterion',
              location: 'config.json',
              detail: 'The flag remains false.',
            ),
          ]
        : const [],
    error: error,
    requestCount: 1,
    estimatedInputTokens: 20,
    estimatedOutputTokens: 10,
    verifierProvider: 'openAiCompatible',
    verifierBaseUrl: 'http://127.0.0.1:1234/v1',
    verifierModel: route.normalizedProfileKey.split('|').last,
    verifierProfileKey: route.normalizedProfileKey,
    fidelityReportSchemaVersion: 3,
    fidelityReportSha256: route.normalizedReportSha256,
    recordedAt: DateTime.utc(2026, 8, 13, 0, voteIndex),
  );
}
