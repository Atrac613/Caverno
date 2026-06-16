import '../../../personal_eval/domain/entities/personal_eval_bake_off_report.dart';
import '../../../personal_eval/domain/entities/personal_eval_case.dart';
import '../../../personal_eval/domain/services/personal_eval_bake_off_service.dart';
import '../../../personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import '../../../settings/domain/entities/app_settings.dart';
import 'harness_proposal_service.dart';

/// The status of a [CandidateAdoptionOutcome].
enum CandidateAdoptionStatus {
  /// Candidate passed held-in + held-out non-regression; config was persisted.
  adopted,

  /// Candidate introduced a hard regression on at least one split; not adopted.
  rejected,

  /// Precondition not met (no eval cases, empty cases list, etc.); skipped.
  skipped,

  /// The surface requires manual review; never auto-persisted.
  manualReview,
}

/// The outcome of a [CandidateAdoptionService.evaluate] call.
class CandidateAdoptionOutcome {
  const CandidateAdoptionOutcome._(this.status, this.reason, this.report);

  const CandidateAdoptionOutcome.adopted({
    required String reason,
    required PersonalEvalBakeOffReport report,
  }) : this._(CandidateAdoptionStatus.adopted, reason, report);

  const CandidateAdoptionOutcome.rejected({
    required String reason,
    required PersonalEvalBakeOffReport report,
  }) : this._(CandidateAdoptionStatus.rejected, reason, report);

  const CandidateAdoptionOutcome.skipped(String reason)
    : this._(CandidateAdoptionStatus.skipped, reason, null);

  const CandidateAdoptionOutcome.manualReview(String reason)
    : this._(CandidateAdoptionStatus.manualReview, reason, null);

  final CandidateAdoptionStatus status;
  final String reason;
  final PersonalEvalBakeOffReport? report;

  bool get wasAdopted => status == CandidateAdoptionStatus.adopted;
}

/// LL17 eval-gated adoption: validates a proposed [HarnessConfigProposal] by
/// replaying the recorded eval suite against the incumbent and candidate configs,
/// then auto-adopts only when both held-in and held-out splits are non-regressing.
///
/// High-stakes surfaces (tool execution, approval, shell/file write) are blocked
/// from auto-adoption regardless of eval results — they require manual review.
///
/// Kept pure and unit-testable: the eval runners and persist callback are
/// injected by the caller (the maintenance scheduler provider wires them up).
class CandidateAdoptionService {
  const CandidateAdoptionService();

  /// Surfaces that must never be auto-adopted. The current proposal surfaces
  /// (failureRecoveryInstruction, recoveryMiddlewareEnabled) are not in this
  /// set; this guards future surfaces that touch high-stakes execution paths.
  static const Set<String> highRiskSurfaces = {
    'approvalMode',
    'shellEnabled',
    'localShellEnabled',
    'toolApprovalBypass',
    'fullAccessEnabled',
  };

  /// Evaluates [proposal] against [cases] and, when both splits pass, persists
  /// the candidate config via [persist].
  ///
  /// - [incumbentRunner]: runs each case with the current (incumbent) harness.
  /// - [candidateRunner]: runs each case with the proposed candidate harness.
  /// - [persist]: called with the adopted [ModelHarnessConfig] when both splits
  ///   pass; should call `SettingsNotifier.upsertModelHarnessConfig`.
  Future<CandidateAdoptionOutcome> evaluate({
    required HarnessConfigProposal proposal,
    required List<PersonalEvalCase> cases,
    required PersonalEvalCaseRunner incumbentRunner,
    required PersonalEvalCaseRunner candidateRunner,
    required Future<void> Function(ModelHarnessConfig) persist,
  }) async {
    if (highRiskSurfaces.contains(proposal.surface)) {
      return CandidateAdoptionOutcome.manualReview(
        'surface ${proposal.surface} requires manual review before adoption',
      );
    }

    if (cases.isEmpty) {
      return const CandidateAdoptionOutcome.skipped(
        'no recorded eval cases to validate against',
      );
    }

    const orchestrator = PersonalEvalReplayOrchestrator();
    final incumbentRun = await orchestrator.run(
      label: 'incumbent',
      model: proposal.proposedConfig.model,
      baseUrl: proposal.proposedConfig.baseUrl,
      cases: cases,
      runner: incumbentRunner,
    );
    final candidateRun = await orchestrator.run(
      label: 'candidate',
      model: proposal.proposedConfig.model,
      baseUrl: proposal.proposedConfig.baseUrl,
      cases: cases,
      runner: candidateRunner,
    );

    const bakeOff = PersonalEvalBakeOffService();
    final report = bakeOff.compare(
      incumbent: incumbentRun,
      candidate: candidateRun,
      cases: cases,
    );

    final heldIn = report.heldIn;
    final heldOut = report.heldOut;

    if (heldIn.nonRegressing && heldOut.nonRegressing) {
      await persist(proposal.proposedConfig);
      return CandidateAdoptionOutcome.adopted(
        reason:
            'held-in ${heldIn.incumbentPassedCount}->'
            '${heldIn.candidatePassedCount}/${heldIn.caseCount}, '
            'held-out ${heldOut.incumbentPassedCount}->'
            '${heldOut.candidatePassedCount}/${heldOut.caseCount}; '
            'no hard regressions',
        report: report,
      );
    }

    return CandidateAdoptionOutcome.rejected(
      reason:
          'hard regressions: ${report.hardRegressionCount} '
          '(held-in ${heldIn.hardRegressionCount}, '
          'held-out ${heldOut.hardRegressionCount})',
      report: report,
    );
  }
}
