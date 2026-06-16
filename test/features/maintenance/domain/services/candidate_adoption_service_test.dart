import 'package:caverno/features/maintenance/domain/services/candidate_adoption_service.dart';
import 'package:caverno/features/maintenance/domain/services/harness_proposal_service.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

// A fake runner that always returns a fixed verification result for every case.
class _FixedRunner implements PersonalEvalCaseRunner {
  _FixedRunner(this.result);
  final PersonalEvalVerificationResult result;

  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    return PersonalEvalCaseRunOutcome(verificationResult: result);
  }
}

void main() {
  const service = CandidateAdoptionService();
  const base = ModelHarnessConfig(id: 'p', model: 'm');

  HarnessConfigProposal proposal({
    String surface = 'failureRecoveryInstruction',
  }) {
    return HarnessConfigProposal(
      mechanism: 'stale_old_text',
      surface: surface,
      rationale: 'test',
      proposedConfig: base.copyWith(
        failureRecoveryInstruction: 're-read before retry',
      ),
    );
  }

  PersonalEvalCase evalCase(
    String id, {
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
  }) {
    return PersonalEvalCase(
      caseId: id,
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
      split: split,
    );
  }

  test('adopts when both splits non-regress', () async {
    final persisted = <ModelHarnessConfig>[];
    final outcome = await service.evaluate(
      proposal: proposal(),
      cases: [
        evalCase('a'),
        evalCase('b', split: PersonalEvalCaseSplit.heldOut),
      ],
      // Incumbent and candidate both pass: no regression → adopt.
      incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      candidateRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      persist: (config) async => persisted.add(config),
    );

    expect(outcome.wasAdopted, isTrue);
    expect(outcome.status, CandidateAdoptionStatus.adopted);
    expect(persisted, hasLength(1));
    expect(persisted.first.failureRecoveryInstruction, contains('re-read'));
  });

  test(
    'rejects when candidate introduces a hard regression on held-in',
    () async {
      final persisted = <ModelHarnessConfig>[];
      final outcome = await service.evaluate(
        proposal: proposal(),
        cases: [evalCase('a')],
        // Incumbent passes but candidate fails → hard regression on held-in.
        incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
        candidateRunner: _FixedRunner(PersonalEvalVerificationResult.failed),
        persist: (config) async => persisted.add(config),
      );

      expect(outcome.wasAdopted, isFalse);
      expect(outcome.status, CandidateAdoptionStatus.rejected);
      expect(persisted, isEmpty);
      expect(outcome.report, isNotNull);
      expect(outcome.report!.hardRegressionCount, greaterThan(0));
    },
  );

  test(
    'rejects when candidate introduces a hard regression on held-out',
    () async {
      final persisted = <ModelHarnessConfig>[];
      final outcome = await service.evaluate(
        proposal: proposal(),
        cases: [evalCase('ho', split: PersonalEvalCaseSplit.heldOut)],
        incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
        candidateRunner: _FixedRunner(PersonalEvalVerificationResult.failed),
        persist: (config) async => persisted.add(config),
      );

      expect(outcome.status, CandidateAdoptionStatus.rejected);
      expect(persisted, isEmpty);
      expect(outcome.report!.heldOut.hardRegressionCount, greaterThan(0));
    },
  );

  test('skips when the case list is empty', () async {
    final persisted = <ModelHarnessConfig>[];
    final outcome = await service.evaluate(
      proposal: proposal(),
      cases: const [],
      incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      candidateRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      persist: (config) async => persisted.add(config),
    );

    expect(outcome.status, CandidateAdoptionStatus.skipped);
    expect(persisted, isEmpty);
  });

  test('blocks high-risk surfaces and requires manual review', () async {
    final persisted = <ModelHarnessConfig>[];
    final outcome = await service.evaluate(
      proposal: proposal(surface: 'approvalMode'),
      cases: [evalCase('a')],
      incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      candidateRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      persist: (config) async => persisted.add(config),
    );

    expect(outcome.status, CandidateAdoptionStatus.manualReview);
    expect(persisted, isEmpty);
    expect(outcome.reason, contains('manual review'));
  });

  test('adopts when candidate improves on failing incumbent', () async {
    // Incumbent fails, candidate passes: no regression (improved) → adopt.
    final persisted = <ModelHarnessConfig>[];
    final outcome = await service.evaluate(
      proposal: proposal(),
      cases: [evalCase('a')],
      incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.failed),
      candidateRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
      persist: (config) async => persisted.add(config),
    );

    expect(outcome.wasAdopted, isTrue);
    expect(persisted, hasLength(1));
  });

  test(
    'rejects when both held-in and held-out regress; persist not called',
    () async {
      final persisted = <ModelHarnessConfig>[];
      final outcome = await service.evaluate(
        proposal: proposal(),
        cases: [
          evalCase('a'),
          evalCase('b', split: PersonalEvalCaseSplit.heldOut),
        ],
        incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
        candidateRunner: _FixedRunner(PersonalEvalVerificationResult.failed),
        persist: (config) async => persisted.add(config),
      );

      expect(outcome.status, CandidateAdoptionStatus.rejected);
      expect(persisted, isEmpty);
      expect(outcome.report!.heldIn.nonRegressing, isFalse);
      expect(outcome.report!.heldOut.nonRegressing, isFalse);
    },
  );

  test('high-risk surface set covers approvalMode and shellEnabled', () {
    expect(
      CandidateAdoptionService.highRiskSurfaces,
      containsAll(['approvalMode', 'shellEnabled', 'toolApprovalBypass']),
    );
    // Surfaces the current proposer uses are NOT high-risk.
    expect(
      CandidateAdoptionService.highRiskSurfaces,
      isNot(contains('failureRecoveryInstruction')),
    );
    expect(
      CandidateAdoptionService.highRiskSurfaces,
      isNot(contains('recoveryMiddlewareEnabled')),
    );
  });
}
