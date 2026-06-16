import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/best_of_n_coordinator.dart';

/// Scripted runner: [greenAt] is the candidate index that verifies green (null
/// = none). Optional hooks make a candidate throw on generate/verify or fail to
/// discard. Records the call sequence for assertions.
class _ScriptedRunner implements BestOfNRunner {
  _ScriptedRunner({
    this.greenAt,
    this.throwGenerateAt,
    this.throwVerifyAt,
    this.failDiscardAt,
  });

  final int? greenAt;
  final int? throwGenerateAt;
  final int? throwVerifyAt;
  final int? failDiscardAt;

  final List<String> calls = [];
  int generateCount = 0;
  final List<int> discarded = [];
  final List<int> kept = [];

  @override
  Future<String> generateCandidate(int index) async {
    generateCount += 1;
    calls.add('generate:$index');
    if (throwGenerateAt == index) throw StateError('gen failed $index');
    return 'changed file for candidate $index';
  }

  @override
  Future<BestOfNVerification> verify(int index) async {
    calls.add('verify:$index');
    if (throwVerifyAt == index) throw StateError('verify failed $index');
    return BestOfNVerification(
      passed: greenAt == index,
      summary: 'tests for $index',
    );
  }

  @override
  Future<void> discardCandidate(int index) async {
    calls.add('discard:$index');
    if (failDiscardAt == index) throw StateError('rollback failed $index');
    discarded.add(index);
  }

  @override
  Future<void> keepCandidate(int index) async {
    calls.add('keep:$index');
    kept.add(index);
  }
}

void main() {
  const coordinator = BestOfNCoordinator();

  test('keeps the first green candidate and stops early', () async {
    final runner = _ScriptedRunner(greenAt: 1);
    final report = await coordinator.run(maxCandidates: 5, runner: runner);

    expect(report.foundGreen, isTrue);
    expect(report.winnerIndex, 1);
    expect(runner.generateCount, 2, reason: 'stops after the first green');
    expect(runner.kept, [1]);
    // Candidate 0 failed verification and was discarded; the winner is kept.
    expect(runner.discarded, [0]);
    expect(report.candidateCount, 2);
    expect(report.attempts.first.isWinner, isFalse);
    expect(report.attempts.last.isWinner, isTrue);
  });

  test('discards every non-winning candidate so no residue remains', () async {
    final runner = _ScriptedRunner(greenAt: null);
    final report = await coordinator.run(maxCandidates: 3, runner: runner);

    expect(report.foundGreen, isFalse);
    expect(report.winnerIndex, isNull);
    expect(runner.discarded, [0, 1, 2]);
    expect(runner.kept, isEmpty);
    expect(report.hasResidueRisk, isFalse);
    expect(report.candidateCount, 3);
  });

  test(
    'treats a generation error as a discarded failure and continues',
    () async {
      final runner = _ScriptedRunner(greenAt: 2, throwGenerateAt: 0);
      final report = await coordinator.run(maxCandidates: 3, runner: runner);

      expect(report.winnerIndex, 2);
      final first = report.attempts.first;
      expect(first.generated, isFalse);
      expect(first.error, contains('gen failed 0'));
      // A failed generation is still discarded to remove partial residue.
      expect(runner.calls.contains('discard:0'), isTrue);
      expect(runner.calls.contains('verify:0'), isFalse);
    },
  );

  test(
    'treats a verification error as a discarded failure and continues',
    () async {
      final runner = _ScriptedRunner(greenAt: 1, throwVerifyAt: 0);
      final report = await coordinator.run(maxCandidates: 2, runner: runner);

      expect(report.winnerIndex, 1);
      final first = report.attempts.first;
      expect(first.generated, isTrue);
      expect(first.verified, isFalse);
      expect(first.error, contains('verify failed 0'));
      expect(runner.discarded.contains(0), isTrue);
    },
  );

  test('captures a discard failure as a residue risk', () async {
    final runner = _ScriptedRunner(greenAt: null, failDiscardAt: 0);
    final report = await coordinator.run(maxCandidates: 2, runner: runner);

    expect(report.foundGreen, isFalse);
    expect(report.hasResidueRisk, isTrue);
    expect(report.attempts.first.discardError, contains('rollback failed 0'));
  });

  test('rejects a non-positive candidate count', () async {
    expect(
      () => coordinator.run(maxCandidates: 0, runner: _ScriptedRunner()),
      throwsArgumentError,
    );
  });

  test('report serializes to json and markdown', () async {
    final runner = _ScriptedRunner(greenAt: 0);
    final report = await coordinator.run(maxCandidates: 2, runner: runner);

    final json = report.toJson();
    expect(json['schemaName'], 'caverno_best_of_n_report');
    expect(json['foundGreen'], isTrue);
    expect(json['winnerIndex'], 0);
    expect((json['attempts'] as List), hasLength(1));

    final markdown = report.toMarkdown();
    expect(markdown, contains('Best-of-N Verification Run'));
    expect(markdown, contains('green'));
  });
}
