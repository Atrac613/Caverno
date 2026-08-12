import 'dart:math';

const personalEvalBootstrapIterations = 10000;
const personalEvalBootstrapSeed = 0x5eed271b;

/// One task observed under both sides of a Personal Eval bake-off.
///
/// A null pass value means the run was missing or inconclusive and therefore
/// cannot enter the binary paired test. Physical measurements remain usable
/// when both corresponding values are present.
final class PersonalEvalPairedObservation {
  const PersonalEvalPairedObservation({
    required this.incumbentPassed,
    required this.candidatePassed,
    this.incumbentDurationMs,
    this.candidateDurationMs,
    this.incumbentTurnCount,
    this.candidateTurnCount,
    this.incumbentToolCallCount,
    this.candidateToolCallCount,
  });

  final bool? incumbentPassed;
  final bool? candidatePassed;
  final int? incumbentDurationMs;
  final int? candidateDurationMs;
  final int? incumbentTurnCount;
  final int? candidateTurnCount;
  final int? incumbentToolCallCount;
  final int? candidateToolCallCount;
}

/// All paired trial observations belonging to one logical eval task.
final class PersonalEvalPairedTaskObservation {
  const PersonalEvalPairedTaskObservation({
    required this.taskId,
    required this.trials,
  });

  final String taskId;
  final List<PersonalEvalPairedObservation> trials;
}

final class PersonalEvalConfidenceInterval {
  const PersonalEvalConfidenceInterval({
    required this.lower,
    required this.upper,
  });

  final double lower;
  final double upper;

  Map<String, dynamic> toJson() => {'lower': lower, 'upper': upper};
}

/// Task-weighted paired statistics for an incumbent/candidate comparison.
final class PersonalEvalPairedStatistics {
  const PersonalEvalPairedStatistics({
    required this.caseCount,
    required this.completePairCount,
    required this.binaryPairCount,
    required this.excludedBinaryPairCount,
    required this.effectTaskCount,
    required this.repeatedTaskCount,
    required this.pairedTrialCount,
    required this.binaryTrialPairCount,
    required this.excludedBinaryTrialPairCount,
    required this.incumbentPassedCount,
    required this.candidatePassedCount,
    required this.bothPassedCount,
    required this.bothFailedCount,
    required this.incumbentOnlyPassedCount,
    required this.candidateOnlyPassedCount,
    required this.passRateDifference,
    required this.passRateDifference95Ci,
    required this.mcnemarExactPValue,
    required this.medianDurationDifferenceMs,
    required this.medianTurnCountDifference,
    required this.medianToolCallCountDifference,
  });

  factory PersonalEvalPairedStatistics.calculate(
    List<PersonalEvalPairedObservation> observations,
  ) {
    return PersonalEvalPairedStatistics.calculateTasks([
      for (var index = 0; index < observations.length; index += 1)
        PersonalEvalPairedTaskObservation(
          taskId: 'task-$index',
          trials: [observations[index]],
        ),
    ]);
  }

  factory PersonalEvalPairedStatistics.calculateTasks(
    List<PersonalEvalPairedTaskObservation> tasks,
  ) {
    var completePairs = 0;
    var incumbentPassed = 0;
    var candidatePassed = 0;
    var bothPassed = 0;
    var bothFailed = 0;
    var incumbentOnlyPassed = 0;
    var candidateOnlyPassed = 0;
    var repeatedTasks = 0;
    var pairedTrials = 0;
    var binaryTrialPairs = 0;
    final taskPassDifferences = <List<int>>[];
    final taskDurationDifferences = <double>[];
    final taskTurnDifferences = <double>[];
    final taskToolCallDifferences = <double>[];

    for (final task in tasks) {
      if (task.trials.length > 1) repeatedTasks += 1;
      pairedTrials += task.trials.length;
      final passDifferences = <int>[];
      final durationDifferences = <int>[];
      final turnDifferences = <int>[];
      final toolCallDifferences = <int>[];
      final exactIncumbentResults = <bool>[];
      final exactCandidateResults = <bool>[];
      var hasCompleteMeasurements = false;

      for (final observation in task.trials) {
        final incumbentResult = observation.incumbentPassed;
        final candidateResult = observation.candidatePassed;
        if (_hasCompleteMeasurements(observation)) {
          hasCompleteMeasurements = true;
        }
        if (incumbentResult != null && candidateResult != null) {
          binaryTrialPairs += 1;
          exactIncumbentResults.add(incumbentResult);
          exactCandidateResults.add(candidateResult);
          passDifferences.add(
            (candidateResult ? 1 : 0) - (incumbentResult ? 1 : 0),
          );
        }
        _addDifference(
          durationDifferences,
          observation.incumbentDurationMs,
          observation.candidateDurationMs,
        );
        _addDifference(
          turnDifferences,
          observation.incumbentTurnCount,
          observation.candidateTurnCount,
        );
        _addDifference(
          toolCallDifferences,
          observation.incumbentToolCallCount,
          observation.candidateToolCallCount,
        );
      }

      if (hasCompleteMeasurements) {
        completePairs += 1;
      }
      if (passDifferences.isNotEmpty) {
        taskPassDifferences.add(passDifferences);
      }
      final durationMedian = _median(durationDifferences);
      final turnMedian = _median(turnDifferences);
      final toolCallMedian = _median(toolCallDifferences);
      if (durationMedian != null) taskDurationDifferences.add(durationMedian);
      if (turnMedian != null) taskTurnDifferences.add(turnMedian);
      if (toolCallMedian != null) {
        taskToolCallDifferences.add(toolCallMedian);
      }

      final hasExactTaskOutcome =
          exactIncumbentResults.length == task.trials.length &&
          exactIncumbentResults.isNotEmpty &&
          _allEqual(exactIncumbentResults) &&
          _allEqual(exactCandidateResults);
      if (hasExactTaskOutcome) {
        final incumbentResult = exactIncumbentResults.first;
        final candidateResult = exactCandidateResults.first;
        if (incumbentResult) incumbentPassed += 1;
        if (candidateResult) candidatePassed += 1;
        if (incumbentResult && candidateResult) {
          bothPassed += 1;
        } else if (!incumbentResult && !candidateResult) {
          bothFailed += 1;
        } else if (incumbentResult) {
          incumbentOnlyPassed += 1;
        } else {
          candidateOnlyPassed += 1;
        }
      }
    }

    final binaryPairs =
        bothPassed + bothFailed + incumbentOnlyPassed + candidateOnlyPassed;
    final taskEffects = [
      for (final differences in taskPassDifferences) _mean(differences),
    ];
    return PersonalEvalPairedStatistics(
      caseCount: tasks.length,
      completePairCount: completePairs,
      binaryPairCount: binaryPairs,
      excludedBinaryPairCount: tasks.length - binaryPairs,
      effectTaskCount: taskPassDifferences.length,
      repeatedTaskCount: repeatedTasks,
      pairedTrialCount: pairedTrials,
      binaryTrialPairCount: binaryTrialPairs,
      excludedBinaryTrialPairCount: pairedTrials - binaryTrialPairs,
      incumbentPassedCount: incumbentPassed,
      candidatePassedCount: candidatePassed,
      bothPassedCount: bothPassed,
      bothFailedCount: bothFailed,
      incumbentOnlyPassedCount: incumbentOnlyPassed,
      candidateOnlyPassedCount: candidateOnlyPassed,
      passRateDifference: taskEffects.isEmpty ? null : _mean(taskEffects),
      passRateDifference95Ci: _hierarchicalBootstrapMeanInterval(
        taskPassDifferences,
      ),
      mcnemarExactPValue: _mcnemarExactPValue(
        incumbentOnlyPassed,
        candidateOnlyPassed,
      ),
      medianDurationDifferenceMs: _medianDouble(taskDurationDifferences),
      medianTurnCountDifference: _medianDouble(taskTurnDifferences),
      medianToolCallCountDifference: _medianDouble(taskToolCallDifferences),
    );
  }

  final int caseCount;
  final int completePairCount;
  final int binaryPairCount;
  final int excludedBinaryPairCount;
  final int effectTaskCount;
  final int repeatedTaskCount;
  final int pairedTrialCount;
  final int binaryTrialPairCount;
  final int excludedBinaryTrialPairCount;
  final int incumbentPassedCount;
  final int candidatePassedCount;
  final int bothPassedCount;
  final int bothFailedCount;
  final int incumbentOnlyPassedCount;
  final int candidateOnlyPassedCount;
  final double? passRateDifference;
  final PersonalEvalConfidenceInterval? passRateDifference95Ci;
  final double? mcnemarExactPValue;
  final double? medianDurationDifferenceMs;
  final double? medianTurnCountDifference;
  final double? medianToolCallCountDifference;

  int get discordantPairCount =>
      incumbentOnlyPassedCount + candidateOnlyPassedCount;

  Map<String, dynamic> toJson() {
    return {
      'unit': 'distinct_task',
      'differenceDirection': 'candidate_minus_incumbent',
      'caseCount': caseCount,
      'completePairCount': completePairCount,
      'binaryPairCount': binaryPairCount,
      'excludedBinaryPairCount': excludedBinaryPairCount,
      'effectTaskCount': effectTaskCount,
      'repeatedTaskCount': repeatedTaskCount,
      'pairedTrialCount': pairedTrialCount,
      'binaryTrialPairCount': binaryTrialPairCount,
      'excludedBinaryTrialPairCount': excludedBinaryTrialPairCount,
      'incumbentPassedCount': incumbentPassedCount,
      'candidatePassedCount': candidatePassedCount,
      'bothPassedCount': bothPassedCount,
      'bothFailedCount': bothFailedCount,
      'incumbentOnlyPassedCount': incumbentOnlyPassedCount,
      'candidateOnlyPassedCount': candidateOnlyPassedCount,
      'discordantPairCount': discordantPairCount,
      'passRateDifference': passRateDifference,
      'passRateDifference95Ci': passRateDifference95Ci?.toJson(),
      'mcnemarExactPValue': mcnemarExactPValue,
      'medianDurationDifferenceMs': medianDurationDifferenceMs,
      'medianTurnCountDifference': medianTurnCountDifference,
      'medianToolCallCountDifference': medianToolCallCountDifference,
      'bootstrap': {
        'method': 'hierarchical_paired_task_percentile',
        'iterations': personalEvalBootstrapIterations,
        'seed': personalEvalBootstrapSeed,
      },
    };
  }
}

bool _allEqual(List<bool> values) =>
    values.skip(1).every((value) => value == values.first);

double _mean(List<num> values) =>
    values.fold<double>(0, (sum, value) => sum + value) / values.length;

bool _hasCompleteMeasurements(PersonalEvalPairedObservation observation) {
  return observation.incumbentDurationMs != null &&
      observation.candidateDurationMs != null &&
      observation.incumbentTurnCount != null &&
      observation.candidateTurnCount != null &&
      observation.incumbentToolCallCount != null &&
      observation.candidateToolCallCount != null;
}

void _addDifference(List<int> target, int? incumbent, int? candidate) {
  if (incumbent != null && candidate != null) {
    target.add(candidate - incumbent);
  }
}

double? _median(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double? _medianDouble(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

PersonalEvalConfidenceInterval? _hierarchicalBootstrapMeanInterval(
  List<List<int>> taskValues,
) {
  if (taskValues.isEmpty) return null;
  final random = Random(personalEvalBootstrapSeed);
  final estimates = List<double>.generate(personalEvalBootstrapIterations, (_) {
    var taskMeanSum = 0.0;
    for (var taskIndex = 0; taskIndex < taskValues.length; taskIndex += 1) {
      final trials = taskValues[random.nextInt(taskValues.length)];
      var trialSum = 0;
      for (var trialIndex = 0; trialIndex < trials.length; trialIndex += 1) {
        trialSum += trials[random.nextInt(trials.length)];
      }
      taskMeanSum += trialSum / trials.length;
    }
    return taskMeanSum / taskValues.length;
  })..sort();
  return PersonalEvalConfidenceInterval(
    lower: _percentile(estimates, 0.025),
    upper: _percentile(estimates, 0.975),
  );
}

double _percentile(List<double> sorted, double probability) {
  final index = ((sorted.length - 1) * probability).floor();
  return sorted[index];
}

double? _mcnemarExactPValue(int incumbentWins, int candidateWins) {
  final discordant = incumbentWins + candidateWins;
  if (discordant == 0) return null;
  final tail = min(incumbentWins, candidateWins);
  var combination = BigInt.one;
  var cumulative = BigInt.zero;
  for (var index = 0; index <= tail; index += 1) {
    cumulative += combination;
    combination =
        combination * BigInt.from(discordant - index) ~/ BigInt.from(index + 1);
  }
  final denominator = BigInt.one << discordant;
  final numerator = _minBigInt(cumulative * BigInt.from(2), denominator);
  const precision = 1 << 53;
  final scaled = numerator * BigInt.from(precision) ~/ denominator;
  return scaled.toDouble() / precision;
}

BigInt _minBigInt(BigInt left, BigInt right) => left < right ? left : right;
