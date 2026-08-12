import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_replay_run.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_session_log_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PersonalEvalReplayCaseResult result({
    required String caseId,
    required PersonalEvalVerificationResult verificationResult,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    PersonalEvalCaseOrigin origin = PersonalEvalCaseOrigin.recorded,
    int tier = 0,
    PersonalEvalPromptStyle promptStyle = PersonalEvalPromptStyle.unclassified,
    int durationMs = 0,
    int toolCallCount = 0,
    int turnCount = 0,
    DateTime? startedAt,
  }) {
    return PersonalEvalReplayCaseResult(
      caseId: caseId,
      split: split,
      origin: origin,
      tier: tier,
      promptStyle: promptStyle,
      verificationResult: verificationResult,
      summary: PersonalEvalSessionLogSummary(
        result: 'complete',
        totalDurationMs: durationMs,
        toolCallCount: toolCallCount,
        turnCount: turnCount,
        startedAt: startedAt,
      ),
    );
  }

  test('aggregates verification counts, totals, and success', () {
    final run = PersonalEvalReplayRun(
      label: 'candidate',
      cases: [
        result(
          caseId: 'a',
          split: PersonalEvalCaseSplit.heldOut,
          origin: PersonalEvalCaseOrigin.authored,
          tier: 2,
          promptStyle: PersonalEvalPromptStyle.unguided,
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
          split: PersonalEvalCaseSplit.heldOut,
          origin: PersonalEvalCaseOrigin.authored,
          tier: 2,
          promptStyle: PersonalEvalPromptStyle.unguided,
          verificationResult: PersonalEvalVerificationResult.passed,
          durationMs: 120,
          toolCallCount: 2,
          turnCount: 3,
          startedAt: DateTime.utc(2026, 6, 15, 3),
        ),
      ],
    );

    final json = run.toReplayRunJson();
    expect(json['schemaName'], 'caverno_personal_eval_replay_run');
    expect(json['schemaVersion'], 5);
    expect(json['generatedAt'], '2026-06-15T04:05:06.000Z');
    expect(json['label'], 'incumbent vs candidate');
    expect(json['model'], 'qwen-test');
    expect(json['caseCount'], 1);
    expect(json['distinctCaseCount'], 1);
    expect(json['trialCount'], 1);
    expect(json['passedCount'], 1);
    expect(json['totalToolCallCount'], 2);

    final cases = json['cases'] as List<dynamic>;
    final entry = cases.single as Map<String, dynamic>;
    expect(entry['caseId'], 'a');
    expect(entry['trialId'], 'trial-1');
    expect(entry['executionOrder'], 1);
    expect(entry['startedAt'], '2026-06-15T03:00:00.000Z');
    expect(entry['split'], 'heldOut');
    expect(entry['origin'], 'authored');
    expect(entry['tier'], 2);
    expect(entry['promptStyle'], 'unguided');
    expect(entry['verificationResult'], 'passed');
    expect(entry['durationMs'], 120);
    expect(entry['turnCount'], 3);
    expect(entry['summaryResult'], 'complete');
  });

  test('counts repeated trials separately from logical cases', () {
    final run = PersonalEvalReplayRun(
      label: 'candidate',
      cases: [
        result(
          caseId: 'a',
          verificationResult: PersonalEvalVerificationResult.passed,
        ).copyWith(trialId: 'trial-1', executionOrder: 2),
        result(
          caseId: 'a',
          verificationResult: PersonalEvalVerificationResult.failed,
        ).copyWith(trialId: 'trial-2', executionOrder: 1),
      ],
    );

    expect(run.caseCount, 2);
    expect(run.distinctCaseCount, 1);
    expect(run.trialCount, 2);
    final entries = run.toReplayRunJson()['cases'] as List<dynamic>;
    expect(entries.first, containsPair('executionOrder', 2));
    expect(entries.last, containsPair('trialId', 'trial-2'));
  });
}
