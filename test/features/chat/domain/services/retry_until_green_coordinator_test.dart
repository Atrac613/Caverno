import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/best_of_n_coordinator.dart';
import 'package:caverno/features/chat/domain/services/retry_until_green_coordinator.dart';

/// Runner that verifies green on the Nth verify call across all rounds.
class _CountingRunner implements BestOfNRunner {
  _CountingRunner({this.greenOnVerifyCall, this.residueAt});

  final int? greenOnVerifyCall; // 1-based; null = never green
  final int? residueAt; // verify-call index that fails to discard

  int verifyCalls = 0;
  int discardCalls = 0;
  int generateCalls = 0;

  @override
  Future<String> generateCandidate(int index) async {
    generateCalls += 1;
    return 'candidate $index';
  }

  @override
  Future<BestOfNVerification> verify(int index) async {
    verifyCalls += 1;
    return BestOfNVerification(passed: verifyCalls == greenOnVerifyCall);
  }

  @override
  Future<void> discardCandidate(int index) async {
    discardCalls += 1;
    if (residueAt == verifyCalls) throw StateError('rollback failed');
  }

  @override
  Future<void> keepCandidate(int index) async {}
}

void main() {
  const coordinator = RetryUntilGreenCoordinator();

  test('stops at the round that goes green', () async {
    // 2 candidates per round; green on the 3rd verify => round 1, candidate 0.
    final runner = _CountingRunner(greenOnVerifyCall: 3);
    final report = await coordinator.run(
      maxRounds: 5,
      candidatesPerRound: 2,
      runner: runner,
    );

    expect(report.foundGreen, isTrue);
    expect(report.winningRound, 1);
    expect(report.roundCount, 2);
    expect(report.rounds.last.winnerIndex, 0);
    // Round 0 (2 candidates) + round 1 (1 candidate, stopped early) = 3.
    expect(report.totalCandidates, 3);
  });

  test('runs every round when no candidate goes green', () async {
    final runner = _CountingRunner(greenOnVerifyCall: null);
    final report = await coordinator.run(
      maxRounds: 3,
      candidatesPerRound: 2,
      runner: runner,
    );

    expect(report.foundGreen, isFalse);
    expect(report.winningRound, isNull);
    expect(report.roundCount, 3);
    expect(report.totalCandidates, 6);
    expect(runner.discardCalls, 6, reason: 'every candidate discarded');
  });

  test('stops early when the wall-clock deadline passes', () async {
    final runner = _CountingRunner(greenOnVerifyCall: null);
    var ticks = 0;
    // Clock: before round 0 it is t=0 (< deadline), before round 1 it is t=10
    // (>= deadline 5), so only one round runs.
    final report = await coordinator.run(
      maxRounds: 10,
      candidatesPerRound: 1,
      runner: runner,
      deadline: DateTime.fromMillisecondsSinceEpoch(5),
      clock: () => DateTime.fromMillisecondsSinceEpoch(ticks++ == 0 ? 0 : 10),
    );

    expect(report.roundCount, 1);
    expect(report.foundGreen, isFalse);
  });

  test('propagates a residue risk into the consolidated report', () async {
    final runner = _CountingRunner(greenOnVerifyCall: null, residueAt: 1);
    final report = await coordinator.run(
      maxRounds: 1,
      candidatesPerRound: 1,
      runner: runner,
    );
    expect(report.hasResidueRisk, isTrue);
  });

  test('rejects non-positive budgets', () async {
    expect(
      () => coordinator.run(
        maxRounds: 0,
        candidatesPerRound: 1,
        runner: _CountingRunner(),
      ),
      throwsArgumentError,
    );
    expect(
      () => coordinator.run(
        maxRounds: 1,
        candidatesPerRound: 0,
        runner: _CountingRunner(),
      ),
      throwsArgumentError,
    );
  });

  test('serializes a consolidated report to json and markdown', () async {
    final runner = _CountingRunner(greenOnVerifyCall: 2);
    final report = await coordinator.run(
      maxRounds: 3,
      candidatesPerRound: 2,
      runner: runner,
    );

    final json = report.toJson();
    expect(json['schemaName'], 'caverno_retry_until_green_report');
    expect(json['foundGreen'], isTrue);
    expect(json['winningRound'], 0);
    expect((json['rounds'] as List), isNotEmpty);

    final markdown = report.toMarkdown();
    expect(markdown, contains('Overnight Retry-Until-Green Run'));
    expect(markdown, contains('green'));
  });
}
