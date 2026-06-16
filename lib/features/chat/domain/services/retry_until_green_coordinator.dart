import 'best_of_n_coordinator.dart';

/// Consolidated result of a bounded retry-until-green run: every Best-of-N round
/// plus the round that first produced a green candidate.
class RetryUntilGreenReport {
  const RetryUntilGreenReport({
    required this.rounds,
    required this.winningRound,
  });

  final List<BestOfNReport> rounds;
  final int? winningRound;

  bool get foundGreen => winningRound != null;
  int get roundCount => rounds.length;

  int get totalCandidates =>
      rounds.fold(0, (sum, round) => sum + round.candidateCount);

  /// True when any round left residue it could not discard.
  bool get hasResidueRisk => rounds.any((round) => round.hasResidueRisk);

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_retry_until_green_report',
      'schemaVersion': 1,
      'foundGreen': foundGreen,
      'winningRound': ?winningRound,
      'roundCount': roundCount,
      'totalCandidates': totalCandidates,
      'hasResidueRisk': hasResidueRisk,
      'rounds': [for (final round in rounds) round.toJson()],
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Overnight Retry-Until-Green Run')
      ..writeln()
      ..writeln('- Rounds run: `$roundCount`')
      ..writeln('- Candidates total: `$totalCandidates`')
      ..writeln(
        '- Result: ${foundGreen ? '`green` (round $winningRound)' : '`no green candidate`'}',
      );
    if (hasResidueRisk) {
      buffer.writeln('- ⚠️ Residue risk: a candidate failed to discard');
    }
    buffer
      ..writeln()
      ..writeln('| Round | candidates | result |')
      ..writeln('| ---: | ---: | --- |');
    for (var index = 0; index < rounds.length; index += 1) {
      final round = rounds[index];
      final result = round.foundGreen
          ? 'green (candidate ${round.winnerIndex})'
          : 'no green';
      buffer.writeln('| $index | ${round.candidateCount} | $result |');
    }
    return buffer.toString();
  }
}

/// LL7 overnight retry-until-green coordinator.
///
/// Repeats Best-of-N rounds until one yields a green candidate or the budget
/// (round count and an optional wall-clock deadline) is exhausted, then returns
/// a single consolidated report. Designed for unattended Routines runs: each
/// round's candidate generation goes through the non-interactive agent
/// (RoutineToolPolicy, no approval prompts), and non-winning candidates are
/// discarded by the runner, so a long overnight run never blocks on input and
/// never accumulates residue.
class RetryUntilGreenCoordinator {
  const RetryUntilGreenCoordinator({this.bestOfN = const BestOfNCoordinator()});

  final BestOfNCoordinator bestOfN;

  Future<RetryUntilGreenReport> run({
    required int maxRounds,
    required int candidatesPerRound,
    required BestOfNRunner runner,
    DateTime? deadline,
    DateTime Function() clock = DateTime.now,
  }) async {
    if (maxRounds <= 0) {
      throw ArgumentError.value(maxRounds, 'maxRounds', 'must be > 0');
    }
    if (candidatesPerRound <= 0) {
      throw ArgumentError.value(
        candidatesPerRound,
        'candidatesPerRound',
        'must be > 0',
      );
    }

    final rounds = <BestOfNReport>[];
    for (var round = 0; round < maxRounds; round += 1) {
      // Stop before a round if the wall-clock budget is exhausted.
      if (deadline != null && !clock().isBefore(deadline)) break;

      final report = await bestOfN.run(
        maxCandidates: candidatesPerRound,
        runner: runner,
      );
      rounds.add(report);
      if (report.foundGreen) {
        return RetryUntilGreenReport(rounds: rounds, winningRound: round);
      }
    }
    return RetryUntilGreenReport(rounds: rounds, winningRound: null);
  }
}
