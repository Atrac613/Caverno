import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_replay_run.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_session_log_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PersonalEvalReplayCaseResult result({
    required String caseId,
    required PersonalEvalVerificationResult verificationResult,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    int durationMs = 0,
    int toolCallCount = 0,
    int turnCount = 0,
  }) {
    return PersonalEvalReplayCaseResult(
      caseId: caseId,
      split: split,
      verificationResult: verificationResult,
      summary: PersonalEvalSessionLogSummary(
        result: 'complete',
        totalDurationMs: durationMs,
        toolCallCount: toolCallCount,
        turnCount: turnCount,
      ),
    );
  }

  test('aggregates verification counts, totals, and success', () {
    final run = PersonalEvalReplayRun(
      label: 'candidate',
      cases: [
        result(
          caseId: 'a',
          verificationResult: PersonalEvalVerificationResult.passed,
          durationMs: 100,
          toolCallCount: 2,
        ),
        result(
          caseId: 'b',
          verificationResult: PersonalEvalVerificationResult.failed,
          durationMs: 50,
          toolCallCount: 1,
        ),
        result(
          caseId: 'c',
          verificationResult: PersonalEvalVerificationResult.inconclusive,
        ),
      ],
    );

    expect(run.caseCount, 3);
    expect(run.passedCount, 1);
    expect(run.failedCount, 1);
    expect(run.inconclusiveCount, 1);
    expect(run.totalDurationMs, 150);
    expect(run.totalToolCallCount, 3);
    expect(run.isSuccessful, isFalse);
  });

  test('is successful only when every case passes', () {
    final run = PersonalEvalReplayRun(
      label: 'candidate',
      cases: [
        result(
          caseId: 'a',
          verificationResult: PersonalEvalVerificationResult.passed,
        ),
        result(
          caseId: 'b',
          verificationResult: PersonalEvalVerificationResult.passed,
        ),
      ],
    );
    expect(run.isSuccessful, isTrue);
  });

  test('reports per-split pass counts for the Self-Harness gate', () {
    final run = PersonalEvalReplayRun(
      label: 'candidate',
      cases: [
        result(
          caseId: 'in-pass',
          verificationResult: PersonalEvalVerificationResult.passed,
        ),
        result(
          caseId: 'out-pass',
          split: PersonalEvalCaseSplit.heldOut,
          verificationResult: PersonalEvalVerificationResult.passed,
        ),
        result(
          caseId: 'out-fail',
          split: PersonalEvalCaseSplit.heldOut,
          verificationResult: PersonalEvalVerificationResult.failed,
        ),
      ],
    );

    expect(run.passedCountForSplit(PersonalEvalCaseSplit.heldIn), 1);
    expect(run.passedCountForSplit(PersonalEvalCaseSplit.heldOut), 1);
    expect(
      run.casesForSplit(PersonalEvalCaseSplit.heldOut).map((c) => c.caseId),
      ['out-pass', 'out-fail'],
    );
  });

  test('emits a CLI-compatible replay-run artifact', () {
    final run = PersonalEvalReplayRun(
      label: 'incumbent vs candidate',
      model: 'qwen-test',
      baseUrl: 'http://localhost:1234/v1',
      generatedAt: DateTime.utc(2026, 6, 15, 4, 5, 6),
      manifestPaths: const ['/cases/a.json'],
      cases: [
        result(
          caseId: 'a',
          verificationResult: PersonalEvalVerificationResult.passed,
          durationMs: 120,
          toolCallCount: 2,
          turnCount: 3,
        ),
      ],
    );

    final json = run.toReplayRunJson();
    expect(json['schemaName'], 'caverno_personal_eval_replay_run');
    expect(json['schemaVersion'], 1);
    expect(json['generatedAt'], '2026-06-15T04:05:06.000Z');
    expect(json['label'], 'incumbent vs candidate');
    expect(json['model'], 'qwen-test');
    expect(json['caseCount'], 1);
    expect(json['passedCount'], 1);
    expect(json['totalToolCallCount'], 2);

    final cases = json['cases'] as List<dynamic>;
    final entry = cases.single as Map<String, dynamic>;
    expect(entry['caseId'], 'a');
    expect(entry['verificationResult'], 'passed');
    expect(entry['durationMs'], 120);
    expect(entry['turnCount'], 3);
    expect(entry['summaryResult'], 'complete');
  });
}
