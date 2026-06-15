import '../entities/personal_eval_case.dart';
import '../entities/personal_eval_replay_run.dart';
import '../entities/personal_eval_session_log_summary.dart';

/// The outcome of replaying one case through a candidate model: the replay
/// session log contents (summarized by the orchestrator), the explicit
/// verification result, and where the log was written.
class PersonalEvalCaseRunOutcome {
  const PersonalEvalCaseRunOutcome({
    required this.verificationResult,
    this.sessionLogContents = '',
    this.logPath = '',
    this.error,
  });

  final PersonalEvalVerificationResult verificationResult;
  final String sessionLogContents;
  final String logPath;
  final String? error;
}

/// Drives a single case through a candidate model/endpoint. The live
/// implementation (chat datasource + verification) is injected so the
/// orchestrator stays pure and unit-testable.
abstract interface class PersonalEvalCaseRunner {
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase);
}

/// LL19: assembles a [PersonalEvalReplayRun] by running each case through a
/// [PersonalEvalCaseRunner] and summarizing its replay log.
///
/// A failing case never aborts the run: it is recorded as an inconclusive
/// result carrying the error, so a single broken case cannot poison the
/// comparison or the Self-Harness gate.
class PersonalEvalReplayOrchestrator {
  const PersonalEvalReplayOrchestrator();

  Future<PersonalEvalReplayRun> run({
    required String label,
    required List<PersonalEvalCase> cases,
    required PersonalEvalCaseRunner runner,
    String? model,
    String? baseUrl,
    List<String> manifestPaths = const [],
    DateTime? generatedAt,
  }) async {
    final results = <PersonalEvalReplayCaseResult>[];
    for (final evalCase in cases) {
      results.add(await _runCase(evalCase, runner));
    }
    return PersonalEvalReplayRun(
      label: label,
      model: model,
      baseUrl: baseUrl,
      manifestPaths: manifestPaths,
      generatedAt: generatedAt,
      cases: results,
    );
  }

  Future<PersonalEvalReplayCaseResult> _runCase(
    PersonalEvalCase evalCase,
    PersonalEvalCaseRunner runner,
  ) async {
    try {
      final outcome = await runner.run(evalCase);
      return PersonalEvalReplayCaseResult(
        caseId: evalCase.caseId,
        title: evalCase.title,
        split: evalCase.split,
        logPath: outcome.logPath,
        verificationResult: outcome.verificationResult,
        summary: PersonalEvalSessionLogSummary.parseLogContents(
          outcome.sessionLogContents,
        ),
        error: outcome.error,
      );
    } catch (error) {
      return PersonalEvalReplayCaseResult(
        caseId: evalCase.caseId,
        title: evalCase.title,
        split: evalCase.split,
        verificationResult: PersonalEvalVerificationResult.inconclusive,
        error: error.toString(),
      );
    }
  }
}
