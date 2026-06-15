import 'package:caverno/features/personal_eval/domain/entities/personal_eval_bake_off_report.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_replay_run.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_session_log_summary.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_bake_off_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PersonalEvalBakeOffService();

  PersonalEvalCase evalCase(
    String id, {
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    int expectedToolCalls = 0,
  }) {
    return PersonalEvalCase(
      caseId: id,
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
      split: split,
      sessionLogSummary: PersonalEvalSessionLogSummary(
        toolCallCount: expectedToolCalls,
      ),
    );
  }

  PersonalEvalReplayCaseResult result(
    String id, {
    required PersonalEvalVerificationResult verification,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    int durationMs = 100,
    int toolCallCount = 0,
    int turnCount = 1,
  }) {
    return PersonalEvalReplayCaseResult(
      caseId: id,
      split: split,
      verificationResult: verification,
      summary: PersonalEvalSessionLogSummary(
        totalDurationMs: durationMs,
        toolCallCount: toolCallCount,
        turnCount: turnCount,
      ),
    );
  }

  PersonalEvalReplayRun run(
    String label,
    String model,
    List<PersonalEvalReplayCaseResult> cases,
  ) {
    return PersonalEvalReplayRun(label: label, model: model, cases: cases);
  }

  test('recommends the candidate when no case hard-regresses', () async {
    final cases = [
      evalCase('a'),
      evalCase('b', split: PersonalEvalCaseSplit.heldOut),
    ];
    final report = service.compare(
      incumbent: run('incumbent', 'old', [
        result('a', verification: PersonalEvalVerificationResult.failed),
        result(
          'b',
          verification: PersonalEvalVerificationResult.passed,
          split: PersonalEvalCaseSplit.heldOut,
        ),
      ]),
      candidate: run('candidate', 'new', [
        // a improves failed -> passed, b stays passed.
        result('a', verification: PersonalEvalVerificationResult.passed),
        result(
          'b',
          verification: PersonalEvalVerificationResult.passed,
          split: PersonalEvalCaseSplit.heldOut,
        ),
      ]),
      cases: cases,
    );

    expect(
      report.recommendation,
      PersonalEvalBakeOffRecommendation.candidateReady,
    );
    expect(report.hardRegressionCount, 0);
    expect(report.improvementCount, greaterThan(0));
    expect(report.incumbentModel, 'old');
    expect(report.candidateModel, 'new');
  });

  test('rejects the candidate on a verification regression', () async {
    final cases = [evalCase('a')];
    final report = service.compare(
      incumbent: run('incumbent', 'old', [
        result('a', verification: PersonalEvalVerificationResult.passed),
      ]),
      candidate: run('candidate', 'new', [
        result('a', verification: PersonalEvalVerificationResult.failed),
      ]),
      cases: cases,
    );

    expect(
      report.recommendation,
      PersonalEvalBakeOffRecommendation.rejectCandidate,
    );
    expect(report.hardRegressionCount, 1);
    expect(report.entries.single.status, PersonalEvalBakeOffStatus.regressed);
  });

  test('reports held-in and held-out scores separately', () async {
    final cases = [
      evalCase('in', split: PersonalEvalCaseSplit.heldIn),
      evalCase('out', split: PersonalEvalCaseSplit.heldOut),
    ];
    final report = service.compare(
      incumbent: run('incumbent', 'old', [
        result('in', verification: PersonalEvalVerificationResult.failed),
        result(
          'out',
          verification: PersonalEvalVerificationResult.passed,
          split: PersonalEvalCaseSplit.heldOut,
        ),
      ]),
      candidate: run('candidate', 'new', [
        result('in', verification: PersonalEvalVerificationResult.passed),
        result(
          'out',
          verification: PersonalEvalVerificationResult.failed,
          split: PersonalEvalCaseSplit.heldOut,
        ),
      ]),
      cases: cases,
    );

    expect(report.heldIn.caseCount, 1);
    expect(report.heldIn.candidatePassedCount, 1);
    expect(report.heldIn.nonRegressing, isTrue);
    expect(report.heldOut.caseCount, 1);
    expect(report.heldOut.candidatePassedCount, 0);
    // The held-out regression is what blocks adoption.
    expect(report.heldOut.nonRegressing, isFalse);
    expect(
      report.recommendation,
      PersonalEvalBakeOffRecommendation.rejectCandidate,
    );
  });

  test('a missing candidate result is a hard regression', () async {
    final cases = [evalCase('a')];
    final report = service.compare(
      incumbent: run('incumbent', 'old', [
        result('a', verification: PersonalEvalVerificationResult.passed),
      ]),
      candidate: run('candidate', 'new', const []),
      cases: cases,
    );

    expect(report.hardRegressionCount, 1);
    expect(
      report.recommendation,
      PersonalEvalBakeOffRecommendation.rejectCandidate,
    );
  });
}
