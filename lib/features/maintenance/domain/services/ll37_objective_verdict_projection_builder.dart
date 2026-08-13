import '../entities/ll37_objective_verdict_record.dart';
import '../entities/ll37_objective_vote_identity.dart';
import 'll37_objective_verification_panel.dart';
import 'll37_verifier_fidelity_profile.dart';

class Ll37ObjectiveVerdictProjectionBuilder {
  const Ll37ObjectiveVerdictProjectionBuilder();

  Ll37ObjectiveVerdictRecord build({
    required String voteId,
    required int voteIndex,
    required Ll37ObjectiveCandidate candidate,
    required Ll37ObjectivePanelReport report,
    required Ll37VerifierFidelityProfile profile,
    required DateTime recordedAt,
  }) {
    if (report.status != Ll37ObjectivePanelStatus.evaluated ||
        report.verdict == null ||
        report.candidateId != candidate.id) {
      throw const FormatException(
        'only matching evaluated LL37 reports can be persisted',
      );
    }
    final expectedVoteId = Ll37ObjectiveVoteIdentity.build(
      candidateId: candidate.id,
      verifierProfileKey: profile.profileKey,
      fidelityReportSha256: profile.reportSha256,
      voteIndex: voteIndex,
    );
    if (voteId != expectedVoteId) {
      throw const FormatException(
        'LL37 vote identity does not match its immutable slot',
      );
    }
    final verdict = report.verdict!;
    return Ll37ObjectiveVerdictRecord(
      voteId: voteId,
      voteIndex: voteIndex,
      candidateId: candidate.id,
      sourceSurface: candidate.sourceSurface.name,
      objective: candidate.objective.trim(),
      acceptanceCriteria: candidate.acceptanceCriteria
          .map((item) => item.trim())
          .toList(growable: false),
      changedFilePaths: candidate.changedFiles
          .map((file) => file.path.trim())
          .toList(growable: false),
      implementationEvidence: candidate.implementationEvidence
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      verdict: verdict.verdict.name,
      confidence: verdict.confidence,
      blocking: verdict.blocking.name,
      findings: verdict.findings
          .map(
            (finding) => Ll37ObjectiveVerdictFindingRecord(
              kind: finding.kind,
              location: finding.location,
              detail: finding.detail,
            ),
          )
          .toList(growable: false),
      error: verdict.error,
      detail: report.detail,
      requestCount: report.requestCount,
      estimatedInputTokens: report.estimatedInputTokens,
      estimatedOutputTokens: report.estimatedOutputTokens,
      verifierProvider: profile.provider.name,
      verifierBaseUrl: profile.baseUrl,
      verifierModel: profile.model,
      verifierProfileKey: profile.profileKey,
      fidelityReportSchemaVersion: profile.reportSchemaVersion,
      fidelityReportSha256: profile.reportSha256,
      recordedAt: recordedAt.toUtc(),
    );
  }
}
