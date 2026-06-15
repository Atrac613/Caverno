import '../entities/personal_eval_bake_off_report.dart';
import '../entities/personal_eval_case.dart';
import '../entities/personal_eval_replay_run.dart';

/// LL19 bake-off: compares a candidate replay run against the incumbent over
/// the recorded suite and produces a single model-swap recommendation.
///
/// The per-case comparison mirrors the offline
/// `tool/personal_eval_suite_report.dart` thresholds so an in-app verdict
/// matches the CLI bundle the offline pipeline emits.
class PersonalEvalBakeOffService {
  const PersonalEvalBakeOffService();

  PersonalEvalBakeOffReport compare({
    required PersonalEvalReplayRun incumbent,
    required PersonalEvalReplayRun candidate,
    required List<PersonalEvalCase> cases,
    String? label,
  }) {
    final incumbentById = {
      for (final result in incumbent.cases) result.caseId: result,
    };
    final candidateById = {
      for (final result in candidate.cases) result.caseId: result,
    };

    final entries = cases
        .map(
          (evalCase) => _compareCase(
            evalCase: evalCase,
            incumbent: incumbentById[evalCase.caseId],
            candidate: candidateById[evalCase.caseId],
          ),
        )
        .toList(growable: false);

    return PersonalEvalBakeOffReport(
      label: label ?? '${incumbent.label} vs ${candidate.label}',
      incumbentModel: incumbent.model,
      candidateModel: candidate.model,
      entries: entries,
    );
  }

  PersonalEvalBakeOffCaseEntry _compareCase({
    required PersonalEvalCase evalCase,
    required PersonalEvalReplayCaseResult? incumbent,
    required PersonalEvalReplayCaseResult? candidate,
  }) {
    final hardRegressions = <String>[];
    final watchSignals = <String>[];
    final improvements = <String>[];
    final expectedToolCallCount =
        evalCase.sessionLogSummary?.toolCallCount ?? 0;

    if (incumbent == null) {
      hardRegressions.add('missing incumbent result');
    }
    if (candidate == null) {
      hardRegressions.add('missing candidate result');
    }

    if (incumbent != null && candidate != null) {
      _compareVerificationResult(
        incumbent: incumbent,
        candidate: candidate,
        hardRegressions: hardRegressions,
        improvements: improvements,
      );
      _compareDuration(
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
      _compareTurns(
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
      _compareToolCallFidelity(
        expectedToolCallCount: expectedToolCallCount,
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
    }

    return PersonalEvalBakeOffCaseEntry(
      caseId: evalCase.caseId,
      title: evalCase.title,
      split: evalCase.split,
      status: _entryStatus(hardRegressions, watchSignals, improvements),
      expectedToolCallCount: expectedToolCallCount,
      incumbent: incumbent,
      candidate: candidate,
      hardRegressions: List.unmodifiable(hardRegressions),
      watchSignals: List.unmodifiable(watchSignals),
      improvements: List.unmodifiable(improvements),
    );
  }

  void _compareVerificationResult({
    required PersonalEvalReplayCaseResult incumbent,
    required PersonalEvalReplayCaseResult candidate,
    required List<String> hardRegressions,
    required List<String> improvements,
  }) {
    final incumbentRank = _verificationRank(incumbent.verificationResult);
    final candidateRank = _verificationRank(candidate.verificationResult);
    if (candidateRank < incumbentRank) {
      hardRegressions.add(
        'verification result regressed '
        '${incumbent.verificationResult.name}->'
        '${candidate.verificationResult.name}',
      );
    } else if (candidateRank > incumbentRank) {
      improvements.add(
        'verification result improved '
        '${incumbent.verificationResult.name}->'
        '${candidate.verificationResult.name}',
      );
    }
  }

  void _compareDuration({
    required PersonalEvalReplayCaseResult incumbent,
    required PersonalEvalReplayCaseResult candidate,
    required List<String> watchSignals,
    required List<String> improvements,
  }) {
    if (incumbent.durationMs <= 0 || candidate.durationMs <= 0) {
      return;
    }
    final increase = candidate.durationMs - incumbent.durationMs;
    if (increase > 1000 && candidate.durationMs > incumbent.durationMs * 1.1) {
      watchSignals.add(
        'duration increased ${incumbent.durationMs}->${candidate.durationMs} ms',
      );
    } else if (candidate.durationMs < incumbent.durationMs) {
      improvements.add(
        'duration decreased ${incumbent.durationMs}->${candidate.durationMs} ms',
      );
    }
  }

  void _compareTurns({
    required PersonalEvalReplayCaseResult incumbent,
    required PersonalEvalReplayCaseResult candidate,
    required List<String> watchSignals,
    required List<String> improvements,
  }) {
    if (candidate.turnCount > incumbent.turnCount + 1) {
      watchSignals.add(
        'turn count increased ${incumbent.turnCount}->${candidate.turnCount}',
      );
    } else if (candidate.turnCount < incumbent.turnCount) {
      improvements.add(
        'turn count decreased ${incumbent.turnCount}->${candidate.turnCount}',
      );
    }
  }

  void _compareToolCallFidelity({
    required int expectedToolCallCount,
    required PersonalEvalReplayCaseResult incumbent,
    required PersonalEvalReplayCaseResult candidate,
    required List<String> watchSignals,
    required List<String> improvements,
  }) {
    final incumbentDelta = (incumbent.toolCallCount - expectedToolCallCount)
        .abs();
    final candidateDelta = (candidate.toolCallCount - expectedToolCallCount)
        .abs();
    if (candidateDelta > incumbentDelta) {
      watchSignals.add(
        'tool-call fidelity delta increased $incumbentDelta->$candidateDelta',
      );
    } else if (candidateDelta < incumbentDelta) {
      improvements.add(
        'tool-call fidelity delta decreased $incumbentDelta->$candidateDelta',
      );
    }
  }

  int _verificationRank(PersonalEvalVerificationResult result) {
    return switch (result) {
      PersonalEvalVerificationResult.failed => 0,
      PersonalEvalVerificationResult.inconclusive => 1,
      PersonalEvalVerificationResult.passed => 2,
    };
  }

  PersonalEvalBakeOffStatus _entryStatus(
    List<String> hardRegressions,
    List<String> watchSignals,
    List<String> improvements,
  ) {
    if (hardRegressions.isNotEmpty) {
      return PersonalEvalBakeOffStatus.regressed;
    }
    if (watchSignals.isNotEmpty) {
      return improvements.isEmpty
          ? PersonalEvalBakeOffStatus.watch
          : PersonalEvalBakeOffStatus.mixed;
    }
    if (improvements.isNotEmpty) {
      return PersonalEvalBakeOffStatus.improved;
    }
    return PersonalEvalBakeOffStatus.unchanged;
  }
}
