import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_paired_statistics.dart';

void main() {
  test('calculates an exact paired pass comparison', () {
    final observations = <PersonalEvalPairedObservation>[
      for (var index = 0; index < 12; index += 1)
        _observation(incumbentPassed: false, candidatePassed: true),
      for (var index = 0; index < 2; index += 1)
        _observation(incumbentPassed: true, candidatePassed: false),
      for (var index = 0; index < 5; index += 1)
        _observation(incumbentPassed: true, candidatePassed: true),
      for (var index = 0; index < 3; index += 1)
        _observation(incumbentPassed: false, candidatePassed: false),
    ];

    final statistics = PersonalEvalPairedStatistics.calculate(observations);

    expect(statistics.caseCount, 22);
    expect(statistics.binaryPairCount, 22);
    expect(statistics.excludedBinaryPairCount, 0);
    expect(statistics.candidateOnlyPassedCount, 12);
    expect(statistics.incumbentOnlyPassedCount, 2);
    expect(statistics.discordantPairCount, 14);
    expect(statistics.passRateDifference, closeTo(10 / 22, 1e-12));
    expect(statistics.mcnemarExactPValue, 0.012939453125);
    expect(statistics.passRateDifference95Ci, isNotNull);
    expect(
      statistics.passRateDifference95Ci!.lower,
      lessThan(statistics.passRateDifference!),
    );
    expect(
      statistics.passRateDifference95Ci!.upper,
      greaterThan(statistics.passRateDifference!),
    );
  });

  test('exact test is symmetric when the model labels are swapped', () {
    final forward = PersonalEvalPairedStatistics.calculate([
      for (var index = 0; index < 12; index += 1)
        _observation(incumbentPassed: false, candidatePassed: true),
      for (var index = 0; index < 2; index += 1)
        _observation(incumbentPassed: true, candidatePassed: false),
    ]);
    final reverse = PersonalEvalPairedStatistics.calculate([
      for (var index = 0; index < 12; index += 1)
        _observation(incumbentPassed: true, candidatePassed: false),
      for (var index = 0; index < 2; index += 1)
        _observation(incumbentPassed: false, candidatePassed: true),
    ]);

    expect(reverse.mcnemarExactPValue, forward.mcnemarExactPValue);
    expect(reverse.passRateDifference, -forward.passRateDifference!);
  });

  test('excludes inconclusive and missing pairs from binary statistics', () {
    final statistics = PersonalEvalPairedStatistics.calculate([
      _observation(incumbentPassed: true, candidatePassed: true),
      const PersonalEvalPairedObservation(
        incumbentPassed: true,
        candidatePassed: null,
        incumbentDurationMs: 1000,
        candidateDurationMs: 1500,
        incumbentTurnCount: 2,
        candidateTurnCount: 3,
        incumbentToolCallCount: 4,
        candidateToolCallCount: 6,
      ),
      const PersonalEvalPairedObservation(
        incumbentPassed: false,
        candidatePassed: null,
        incumbentDurationMs: 1000,
        incumbentTurnCount: 2,
        incumbentToolCallCount: 4,
      ),
    ]);

    expect(statistics.caseCount, 3);
    expect(statistics.completePairCount, 2);
    expect(statistics.binaryPairCount, 1);
    expect(statistics.excludedBinaryPairCount, 2);
    expect(statistics.passRateDifference, 0);
    expect(statistics.mcnemarExactPValue, isNull);
    expect(statistics.medianDurationDifferenceMs, 200);
    expect(statistics.medianTurnCountDifference, 0);
    expect(statistics.medianToolCallCountDifference, 0.5);
  });

  test('bootstrap interval is reproducible and declares its configuration', () {
    final observations = [
      _observation(incumbentPassed: false, candidatePassed: true),
      _observation(incumbentPassed: true, candidatePassed: true),
      _observation(incumbentPassed: true, candidatePassed: false),
    ];

    final first = PersonalEvalPairedStatistics.calculate(observations);
    final second = PersonalEvalPairedStatistics.calculate(observations);

    expect(
      first.passRateDifference95Ci?.lower,
      second.passRateDifference95Ci?.lower,
    );
    expect(
      first.passRateDifference95Ci?.upper,
      second.passRateDifference95Ci?.upper,
    );
    expect(
      first.toJson()['bootstrap'],
      containsPair('iterations', personalEvalBootstrapIterations),
    );
    expect(
      first.toJson()['bootstrap'],
      containsPair('seed', personalEvalBootstrapSeed),
    );
  });

  test('weights tasks equally when trial counts differ', () {
    final statistics = PersonalEvalPairedStatistics.calculateTasks([
      PersonalEvalPairedTaskObservation(
        taskId: 'many-trials',
        trials: [
          for (var index = 0; index < 9; index += 1)
            _observation(incumbentPassed: false, candidatePassed: true),
        ],
      ),
      PersonalEvalPairedTaskObservation(
        taskId: 'one-trial',
        trials: [_observation(incumbentPassed: true, candidatePassed: false)],
      ),
    ]);

    expect(statistics.caseCount, 2);
    expect(statistics.effectTaskCount, 2);
    expect(statistics.repeatedTaskCount, 1);
    expect(statistics.pairedTrialCount, 10);
    expect(statistics.binaryTrialPairCount, 10);
    expect(statistics.passRateDifference, 0);
    expect(
      statistics.toJson()['bootstrap'],
      containsPair('method', 'hierarchical_paired_task_percentile'),
    );
  });

  test('excludes mixed repeated tasks from the exact McNemar test', () {
    final statistics = PersonalEvalPairedStatistics.calculateTasks([
      PersonalEvalPairedTaskObservation(
        taskId: 'mixed',
        trials: [
          _observation(incumbentPassed: false, candidatePassed: true),
          _observation(incumbentPassed: true, candidatePassed: false),
        ],
      ),
      PersonalEvalPairedTaskObservation(
        taskId: 'consistent',
        trials: [
          _observation(incumbentPassed: false, candidatePassed: true),
          _observation(incumbentPassed: false, candidatePassed: true),
        ],
      ),
    ]);

    expect(statistics.effectTaskCount, 2);
    expect(statistics.binaryPairCount, 1);
    expect(statistics.excludedBinaryPairCount, 1);
    expect(statistics.candidateOnlyPassedCount, 1);
    expect(statistics.mcnemarExactPValue, 1);
    expect(statistics.passRateDifference, 0.5);
  });
}

PersonalEvalPairedObservation _observation({
  required bool incumbentPassed,
  required bool candidatePassed,
}) {
  return PersonalEvalPairedObservation(
    incumbentPassed: incumbentPassed,
    candidatePassed: candidatePassed,
    incumbentDurationMs: 1000,
    candidateDurationMs: 900,
    incumbentTurnCount: 3,
    candidateTurnCount: 2,
    incumbentToolCallCount: 4,
    candidateToolCallCount: 3,
  );
}
