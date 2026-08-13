import 'package:caverno/features/maintenance/domain/services/ll37_objective_verdict_projection_builder.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_vote_identity.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const candidate = Ll37ObjectiveCandidate(
    id: 'worktree-agent:task-1',
    sourceSurface: Ll37ObjectiveSourceSurface.worktreeAgent,
    attended: false,
    ll34OutcomeSettled: false,
    objective: 'Set the feature flag.',
    acceptanceCriteria: ['The flag is true.'],
    changedFiles: [
      Ll37ObjectiveChangedFile(
        path: 'config.json',
        content: 'changed file contents',
      ),
    ],
    implementationEvidence: ['Verification result: passed'],
  );
  const report = Ll37ObjectivePanelReport(
    status: Ll37ObjectivePanelStatus.evaluated,
    candidateId: 'worktree-agent:task-1',
    requestCount: 1,
    estimatedInputTokens: 20,
    estimatedOutputTokens: 10,
    verdict: Ll37ObjectivePanelVerdict(
      verdict: Ll37ObjectiveVerdict.refuted,
      confidence: 0.9,
      blocking: Ll37ObjectiveBlocking.contradiction,
      findings: [
        Ll37ObjectiveFinding(
          kind: 'unmet_criterion',
          location: 'config.json',
          detail: 'The flag remains false.',
        ),
      ],
    ),
    detail: 'objective verification completed',
  );
  const profile = Ll37VerifierFidelityProfile(
    provider: LlmProvider.openAiCompatible,
    baseUrl: 'http://127.0.0.1:1234/v1',
    model: 'verifier-model',
    gate: Ll37VerifierFidelityGate.go,
    reportSchemaVersion: 3,
    reportSha256: 'report-sha',
    measuredAt: '2026-08-13T00:00:00Z',
    correctCaseCount: 5,
    brokenCaseCount: 5,
    distinctObjectiveCount: 5,
    sourceSurfaceCount: 2,
    falseRefuteRate: 0,
    brokenRecall: 1,
    invalidOrUnverifiableCount: 0,
  );

  test('builds a review projection without changed-file contents', () {
    final record = const Ll37ObjectiveVerdictProjectionBuilder().build(
      voteId: Ll37ObjectiveVoteIdentity.build(
        candidateId: candidate.id,
        verifierProfileKey: profile.profileKey,
        fidelityReportSha256: profile.reportSha256,
        voteIndex: 1,
      ),
      voteIndex: 1,
      candidate: candidate,
      report: report,
      profile: profile,
      recordedAt: DateTime.utc(2026, 8, 13, 3),
    );

    expect(record.candidateId, candidate.id);
    expect(record.changedFilePaths, ['config.json']);
    expect(record.verdict, 'refuted');
    expect(record.blocking, 'contradiction');
    expect(record.findings.single.detail, 'The flag remains false.');
    expect(record.fidelityReportSha256, 'report-sha');
    expect(
      record.toJson().toString(),
      isNot(contains('changed file contents')),
    );
  });

  test('rejects skipped or mismatched reports', () {
    const skipped = Ll37ObjectivePanelReport(
      status: Ll37ObjectivePanelStatus.skipped,
      candidateId: 'worktree-agent:task-1',
      requestCount: 0,
      estimatedInputTokens: 0,
      estimatedOutputTokens: 0,
    );
    final builder = const Ll37ObjectiveVerdictProjectionBuilder();

    expect(
      () => builder.build(
        voteId: Ll37ObjectiveVoteIdentity.build(
          candidateId: candidate.id,
          verifierProfileKey: profile.profileKey,
          fidelityReportSha256: profile.reportSha256,
          voteIndex: 1,
        ),
        voteIndex: 1,
        candidate: candidate,
        report: skipped,
        profile: profile,
        recordedAt: DateTime.utc(2026, 8, 13),
      ),
      throwsFormatException,
    );
    expect(
      () => builder.build(
        voteId: Ll37ObjectiveVoteIdentity.build(
          candidateId: candidate.id,
          verifierProfileKey: profile.profileKey,
          fidelityReportSha256: profile.reportSha256,
          voteIndex: 1,
        ),
        voteIndex: 1,
        candidate: candidate,
        report: const Ll37ObjectivePanelReport(
          status: Ll37ObjectivePanelStatus.evaluated,
          candidateId: 'other',
          requestCount: 1,
          estimatedInputTokens: 1,
          estimatedOutputTokens: 1,
          verdict: Ll37ObjectivePanelVerdict(
            verdict: Ll37ObjectiveVerdict.notRefuted,
            confidence: 1,
            blocking: Ll37ObjectiveBlocking.none,
            findings: [],
          ),
        ),
        profile: profile,
        recordedAt: DateTime.utc(2026, 8, 13),
      ),
      throwsFormatException,
    );
  });
}
