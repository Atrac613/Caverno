import '../entities/personal_eval_case.dart';
import 'live_personal_eval_case_runner.dart';
import 'personal_eval_authored_workspace.dart';
import 'personal_eval_replay_orchestrator.dart';
import 'personal_eval_verification_runner.dart';

/// Builds the driver that will operate inside [workingDirectory].
///
/// A new driver per case is the point: the existing chat driver fixes its
/// working directory at construction, while every authored case needs its own
/// throwaway copy of the fixture.
typedef PersonalEvalAuthoredDriverFactory =
    PersonalEvalReplayTurnDriver Function(
      String workingDirectory,
      PersonalEvalCase evalCase,
    );

/// Runs one authored fixture case: materialize an isolated workspace, drive the
/// candidate inside it, verify there, and remove it.
///
/// [LivePersonalEvalCaseRunner] cannot do this because the workspace has to
/// outlive the drive (verification runs in it) and be removed afterwards, so
/// the lifetime belongs to the whole case run rather than to the turn.
///
/// The workspace is always removed, including when the drive throws. A leaked
/// temporary tree per case would be a slow disk leak across a repeated
/// comparison, and a reused one would let one case's edits score another.
class PersonalEvalAuthoredCaseRunner implements PersonalEvalCaseRunner {
  const PersonalEvalAuthoredCaseRunner({
    required PersonalEvalAuthoredDriverFactory driverFactory,
    required PersonalEvalVerificationRunner verificationRunner,
    required String repositoryRoot,
    String seedRoot = 'seeds',
  }) : _driverFactory = driverFactory,
       _verificationRunner = verificationRunner,
       _repositoryRoot = repositoryRoot,
       _seedRoot = seedRoot;

  final PersonalEvalAuthoredDriverFactory _driverFactory;
  final PersonalEvalVerificationRunner _verificationRunner;
  final String _repositoryRoot;
  final String _seedRoot;

  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    if (!evalCase.isAuthored) {
      return const PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.inconclusive,
        skipped: true,
        skipReason:
            'This runner only replays authored fixture cases; a recorded case '
            'needs its own repository state.',
      );
    }

    final PersonalEvalAuthoredWorkspace workspace;
    try {
      workspace = PersonalEvalAuthoredWorkspace.prepare(
        evalCase: evalCase,
        repositoryRoot: _repositoryRoot,
        seedRoot: _seedRoot,
      );
    } catch (error) {
      // A workspace that could not be prepared is inconclusive, never a
      // failure: the candidate was never given the task.
      return PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.inconclusive,
        error: 'Could not prepare a workspace for ${evalCase.caseId}: $error',
      );
    }

    try {
      final turn = await _driverFactory(
        workspace.path,
        evalCase,
      ).drive(evalCase);
      if (!evalCase.hasVerificationCommand) {
        return PersonalEvalCaseRunOutcome(
          verificationResult: PersonalEvalVerificationResult.inconclusive,
          sessionLogContents: turn.logContents,
          logPath: turn.logPath,
          error: turn.error,
        );
      }
      final integrityError = workspace.verificationHarnessIntegrityError();
      if (integrityError != null) {
        return PersonalEvalCaseRunOutcome(
          verificationResult: PersonalEvalVerificationResult.inconclusive,
          sessionLogContents: turn.logContents,
          logPath: turn.logPath,
          error: integrityError,
        );
      }
      final verification = await _verificationRunner.run(
        command: evalCase.verificationCommand!,
        // Verification runs where the candidate worked, not where the turn
        // said it worked: a driver that reported a different directory would
        // otherwise verify an untouched copy.
        workingDirectory: workspace.path,
      );
      return PersonalEvalCaseRunOutcome(
        // A turn that threw cannot produce a failure verdict; see
        // resultAfterTurnError.
        verificationResult: resultAfterTurnError(
          turnError: turn.error,
          verificationResult: verification.result,
        ),
        sessionLogContents: turn.logContents,
        logPath: turn.logPath,
        error: turn.error ?? verification.error,
      );
    } catch (error) {
      return PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.inconclusive,
        error: 'Replay of ${evalCase.caseId} threw: $error',
      );
    } finally {
      workspace.dispose();
    }
  }
}
