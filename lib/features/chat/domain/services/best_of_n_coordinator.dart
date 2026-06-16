/// Verification verdict for a Best-of-N candidate.
class BestOfNVerification {
  const BestOfNVerification({required this.passed, this.summary});

  final bool passed;
  final String? summary;
}

/// Drives one Best-of-N candidate end to end. The coordinator owns the
/// keep-first-green policy; the runner owns the actual work (generating and
/// applying a candidate, verifying, and undoing) so the coordinator stays a
/// pure, unit-testable policy.
///
/// Each candidate must be self-contained: [generateCandidate] applies its
/// changes within its own LL2 checkpoint so [discardCandidate] can fully undo
/// them, leaving the working tree exactly as it was before the candidate ran.
abstract interface class BestOfNRunner {
  /// Generates and applies candidate [index] (e.g. runs the agent tool loop so
  /// it edits the working tree), returning a short summary of what changed.
  /// Throwing marks the candidate as a generation failure; it is still
  /// discarded so it leaves no residue.
  Future<String> generateCandidate(int index);

  /// Verifies the working tree after candidate [index] was applied.
  Future<BestOfNVerification> verify(int index);

  /// Undoes candidate [index]'s changes, restoring the tree to its pre-candidate
  /// state. Called for every non-winning candidate.
  Future<void> discardCandidate(int index);

  /// Keeps candidate [index]'s changes — the winner. May be a no-op.
  Future<void> keepCandidate(int index);
}

/// One candidate's outcome in a Best-of-N run.
class BestOfNAttempt {
  const BestOfNAttempt({
    required this.index,
    required this.generated,
    required this.verified,
    required this.passed,
    required this.isWinner,
    this.summary,
    this.error,
    this.discardError,
  });

  final int index;

  /// Whether [BestOfNRunner.generateCandidate] completed without throwing.
  final bool generated;

  /// Whether verification ran (only attempted when [generated]).
  final bool verified;

  /// Whether verification was green.
  final bool passed;

  final bool isWinner;
  final String? summary;

  /// A generation or verification error, when one occurred.
  final String? error;

  /// A discard (rollback) error. Non-null means the candidate may have left
  /// residue in the working tree despite being non-winning.
  final String? discardError;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'generated': generated,
      'verified': verified,
      'passed': passed,
      'isWinner': isWinner,
      'summary': ?summary,
      'error': ?error,
      'discardError': ?discardError,
    };
  }
}

/// Consolidated Best-of-N result: every candidate's outcome plus the winner.
class BestOfNReport {
  const BestOfNReport({required this.attempts, required this.winnerIndex});

  final List<BestOfNAttempt> attempts;
  final int? winnerIndex;

  int get candidateCount => attempts.length;
  bool get foundGreen => winnerIndex != null;

  /// True when a non-winning candidate failed to discard, i.e. residue may
  /// remain in the working tree. The orchestrator should surface this loudly.
  bool get hasResidueRisk =>
      attempts.any((a) => !a.isWinner && a.discardError != null);

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_best_of_n_report',
      'schemaVersion': 1,
      'candidateCount': candidateCount,
      'foundGreen': foundGreen,
      'winnerIndex': ?winnerIndex,
      'hasResidueRisk': hasResidueRisk,
      'attempts': [for (final attempt in attempts) attempt.toJson()],
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Best-of-N Verification Run')
      ..writeln()
      ..writeln('- Candidates run: `$candidateCount`')
      ..writeln(
        '- Result: ${foundGreen ? '`green` (candidate $winnerIndex)' : '`no green candidate`'}',
      );
    if (hasResidueRisk) {
      buffer.writeln(
        '- ⚠️ Residue risk: a non-winning candidate failed to discard',
      );
    }
    buffer
      ..writeln()
      ..writeln('| Candidate | generated | verified | passed | winner | note |')
      ..writeln('| ---: | :--: | :--: | :--: | :--: | --- |');
    for (final attempt in attempts) {
      final note = attempt.discardError != null
          ? 'discard failed: ${attempt.discardError}'
          : (attempt.error ?? attempt.summary ?? '');
      buffer.writeln(
        '| ${attempt.index} | ${_yn(attempt.generated)} | '
        '${_yn(attempt.verified)} | ${_yn(attempt.passed)} | '
        '${_yn(attempt.isWinner)} | $note |',
      );
    }
    return buffer.toString();
  }

  static String _yn(bool value) => value ? 'yes' : 'no';
}

/// LL7 Best-of-N coordinator.
///
/// Runs up to N candidates one at a time, keeps the first one that verifies
/// green, and discards every non-winning candidate so the working tree never
/// accumulates residue. Tokens are free locally, so generating several
/// candidates and keeping the first green one trades compute for output quality.
///
/// Sequential by design: N agent runs editing one working tree cannot safely run
/// in parallel — that requires isolated git worktrees (LL13). Per-endpoint slot
/// concurrency (LL20) applies to a future parallel-completion variant.
class BestOfNCoordinator {
  const BestOfNCoordinator();

  Future<BestOfNReport> run({
    required int maxCandidates,
    required BestOfNRunner runner,
  }) async {
    if (maxCandidates <= 0) {
      throw ArgumentError.value(
        maxCandidates,
        'maxCandidates',
        'must be greater than zero',
      );
    }

    final attempts = <BestOfNAttempt>[];

    for (var index = 0; index < maxCandidates; index += 1) {
      String summary;
      try {
        summary = await runner.generateCandidate(index);
      } catch (error) {
        attempts.add(
          BestOfNAttempt(
            index: index,
            generated: false,
            verified: false,
            passed: false,
            isWinner: false,
            error: error.toString(),
            discardError: await _discard(runner, index),
          ),
        );
        continue;
      }

      BestOfNVerification verification;
      try {
        verification = await runner.verify(index);
      } catch (error) {
        attempts.add(
          BestOfNAttempt(
            index: index,
            generated: true,
            verified: false,
            passed: false,
            isWinner: false,
            summary: summary,
            error: error.toString(),
            discardError: await _discard(runner, index),
          ),
        );
        continue;
      }

      if (verification.passed) {
        await runner.keepCandidate(index);
        attempts.add(
          BestOfNAttempt(
            index: index,
            generated: true,
            verified: true,
            passed: true,
            isWinner: true,
            summary: verification.summary ?? summary,
          ),
        );
        return BestOfNReport(attempts: attempts, winnerIndex: index);
      }

      attempts.add(
        BestOfNAttempt(
          index: index,
          generated: true,
          verified: true,
          passed: false,
          isWinner: false,
          summary: verification.summary ?? summary,
          discardError: await _discard(runner, index),
        ),
      );
    }

    return BestOfNReport(attempts: attempts, winnerIndex: null);
  }

  /// Discards a non-winning candidate, capturing (not throwing) any rollback
  /// error so the run continues and the residue risk is reported.
  Future<String?> _discard(BestOfNRunner runner, int index) async {
    try {
      await runner.discardCandidate(index);
      return null;
    } catch (error) {
      return error.toString();
    }
  }
}
