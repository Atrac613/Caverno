import '../entities/personal_eval_case.dart';
import 'personal_eval_replay_orchestrator.dart';
import 'personal_eval_verification_runner.dart';
import '../../../../core/types/workspace_mode.dart';

/// Result of driving a candidate model through one recorded case: where the
/// replay session log was written, its contents (for summary parsing), the
/// directory the candidate operated in (verification runs there), and any soft
/// error that did not abort the turn.
class PersonalEvalReplayTurnResult {
  const PersonalEvalReplayTurnResult({
    this.logPath = '',
    this.logContents = '',
    this.workingDirectory = '',
    this.error,
  });

  final String logPath;
  final String logContents;

  /// The directory the candidate prepared and operated in. Verification runs
  /// here rather than against [PersonalEvalCase.repoStateRef], which is a free
  /// reference string (e.g. a git ref), not a guaranteed path.
  final String workingDirectory;

  final String? error;
}

/// Drives a single case through a candidate model/endpoint end-to-end via the
/// chat datasource (mirroring the live canary harness). The concrete,
/// ChatNotifier-backed implementation is wired in a later slice; isolating it
/// behind this interface keeps [LivePersonalEvalCaseRunner] unit-testable.
abstract interface class PersonalEvalReplayTurnDriver {
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase);
}

/// How a verification result is read when the turn itself threw.
///
/// Verification still runs, because a turn can throw after the candidate has
/// already changed the workspace and that partial work may genuinely pass. But
/// a `failed` is refused: the turn never finished, so the failure could equally
/// be the endpoint's. The 2026-08-12 27B/35B pilot is the case in point -- a
/// proxy returning 500 produced three task-level "model failures" on tasks the
/// same model had solved in its other trial, and those three drove the entire
/// reported effect.
///
/// Deliberately asymmetric: demonstrable success is credited, manufactured
/// failure is not. `turnError` is only ever set by the driver's catch, so this
/// keys off "the turn did not complete" rather than the message text.
PersonalEvalVerificationResult resultAfterTurnError({
  required String? turnError,
  required PersonalEvalVerificationResult verificationResult,
}) {
  if (turnError == null) {
    return verificationResult;
  }
  return verificationResult == PersonalEvalVerificationResult.failed
      ? PersonalEvalVerificationResult.inconclusive
      : verificationResult;
}

/// LL19: the live [PersonalEvalCaseRunner]. Composes a [PersonalEvalReplayTurnDriver]
/// (run the candidate model through the case) with a [PersonalEvalVerificationRunner]
/// (run the recorded verification command), producing the
/// [PersonalEvalCaseRunOutcome] the [PersonalEvalReplayOrchestrator] consumes.
///
/// A case without a reproducible verification command stays inconclusive: the
/// turn still runs and its log is captured, but no pass/fail can be asserted.
class LivePersonalEvalCaseRunner implements PersonalEvalCaseRunner {
  const LivePersonalEvalCaseRunner({
    required PersonalEvalReplayTurnDriver turnDriver,
    required PersonalEvalVerificationRunner verificationRunner,
  }) : _turnDriver = turnDriver,
       _verificationRunner = verificationRunner;

  final PersonalEvalReplayTurnDriver _turnDriver;
  final PersonalEvalVerificationRunner _verificationRunner;

  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    final turn = await _turnDriver.drive(evalCase);

    if (!evalCase.hasVerificationCommand) {
      return PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.inconclusive,
        sessionLogContents: turn.logContents,
        logPath: turn.logPath,
        error: turn.error,
      );
    }

    final command = evalCase.verificationCommand!.trim();
    if (_isCodingWorkspace(evalCase.workspaceMode) &&
        _isAndroidVerificationCommand(command)) {
      return PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.inconclusive,
        sessionLogContents: turn.logContents,
        logPath: turn.logPath,
        skipped: true,
        error:
            'verification command was skipped for coding workspace mode: '
            'android target detected.',
      );
    }

    final verification = await _verificationRunner.run(
      command: command,
      workingDirectory: turn.workingDirectory,
    );

    return PersonalEvalCaseRunOutcome(
      verificationResult: resultAfterTurnError(
        turnError: turn.error,
        verificationResult: verification.result,
      ),
      sessionLogContents: turn.logContents,
      logPath: turn.logPath,
      // Surface the turn's soft error first; otherwise carry any verification
      // launch failure (timeout / missing binary) so the operator can see why
      // a case landed inconclusive.
      error: turn.error ?? verification.error,
    );
  }

  bool _isCodingWorkspace(String? workspaceMode) {
    return workspaceMode?.trim().toLowerCase() == WorkspaceMode.coding.name;
  }

  bool _isAndroidVerificationCommand(String command) {
    final normalized = command.toLowerCase();
    return normalized.contains('flutter build apk') ||
        normalized.contains('flutter build appbundle') ||
        (normalized.contains('flutter run -d') &&
            normalized.contains('android')) ||
        normalized.contains('gradlew') ||
        normalized.contains('/android/') ||
        normalized.contains('adb ');
  }
}
