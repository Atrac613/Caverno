import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/live_personal_eval_case_runner.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTurnDriver implements PersonalEvalReplayTurnDriver {
  _FakeTurnDriver(this.result);

  final PersonalEvalReplayTurnResult result;
  PersonalEvalCase? drivenCase;

  @override
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase) async {
    drivenCase = evalCase;
    return result;
  }
}

class _RecordingVerificationRunner implements PersonalEvalVerificationRunner {
  _RecordingVerificationRunner(this.outcome);

  final PersonalEvalVerificationOutcome outcome;
  String? ranCommand;
  String? ranWorkingDirectory;

  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) async {
    ranCommand = command;
    ranWorkingDirectory = workingDirectory;
    return outcome;
  }
}

void main() {
  PersonalEvalCase evalCase({String? verificationCommand}) {
    return PersonalEvalCase(
      caseId: 'c1',
      prompt: 'do the thing',
      repoStateRef: 'main@abc123',
      consentGranted: true,
      verificationCommand: verificationCommand,
    );
  }

  test(
    'runs verification in the turn working directory and propagates the result',
    () async {
      final driver = _FakeTurnDriver(
        const PersonalEvalReplayTurnResult(
          logPath: '/replay/c1.jsonl',
          logContents: 'log',
          workingDirectory: '/tmp/project',
        ),
      );
      final verification = _RecordingVerificationRunner(
        const PersonalEvalVerificationOutcome(
          result: PersonalEvalVerificationResult.passed,
          exitCode: 0,
        ),
      );
      final runner = LivePersonalEvalCaseRunner(
        turnDriver: driver,
        verificationRunner: verification,
      );

      final outcome = await runner.run(
        evalCase(verificationCommand: 'flutter test'),
      );

      expect(outcome.verificationResult, PersonalEvalVerificationResult.passed);
      expect(outcome.sessionLogContents, 'log');
      expect(outcome.logPath, '/replay/c1.jsonl');
      expect(outcome.error, isNull);
      // Verification runs in the directory the candidate operated in, never the
      // free-text repoStateRef.
      expect(verification.ranCommand, 'flutter test');
      expect(verification.ranWorkingDirectory, '/tmp/project');
    },
  );

  test('a case without a verification command stays inconclusive and skips '
      'verification', () async {
    final driver = _FakeTurnDriver(
      const PersonalEvalReplayTurnResult(
        logPath: '/replay/c1.jsonl',
        workingDirectory: '/tmp/project',
      ),
    );
    final verification = _RecordingVerificationRunner(
      const PersonalEvalVerificationOutcome(
        result: PersonalEvalVerificationResult.passed,
      ),
    );
    final runner = LivePersonalEvalCaseRunner(
      turnDriver: driver,
      verificationRunner: verification,
    );

    final outcome = await runner.run(evalCase());

    expect(
      outcome.verificationResult,
      PersonalEvalVerificationResult.inconclusive,
    );
    expect(verification.ranCommand, isNull);
  });

  test(
    'a soft turn error is carried through and wins over a verification error',
    () async {
      final driver = _FakeTurnDriver(
        const PersonalEvalReplayTurnResult(
          logContents: 'partial',
          workingDirectory: '/tmp/project',
          error: 'transport disconnected',
        ),
      );
      final verification = _RecordingVerificationRunner(
        const PersonalEvalVerificationOutcome.inconclusive(
          error: 'command not found',
        ),
      );
      final runner = LivePersonalEvalCaseRunner(
        turnDriver: driver,
        verificationRunner: verification,
      );

      final outcome = await runner.run(
        evalCase(verificationCommand: 'flutter test'),
      );

      // Verification still ran (the repo may reflect partial work) ...
      expect(verification.ranCommand, 'flutter test');
      expect(
        outcome.verificationResult,
        PersonalEvalVerificationResult.inconclusive,
      );
      // ... but the turn error is the primary diagnostic.
      expect(outcome.error, 'transport disconnected');
    },
  );

  test('connects to the orchestrator to assemble a replay run', () async {
    final driver = _FakeTurnDriver(
      const PersonalEvalReplayTurnResult(
        logPath: '/replay/c1.jsonl',
        workingDirectory: '/tmp/project',
      ),
    );
    final verification = _RecordingVerificationRunner(
      const PersonalEvalVerificationOutcome(
        result: PersonalEvalVerificationResult.failed,
        exitCode: 1,
      ),
    );
    final runner = LivePersonalEvalCaseRunner(
      turnDriver: driver,
      verificationRunner: verification,
    );

    const orchestrator = PersonalEvalReplayOrchestrator();
    final run = await orchestrator.run(
      label: 'candidate',
      cases: [evalCase(verificationCommand: 'flutter test')],
      runner: runner,
    );

    expect(run.caseCount, 1);
    expect(run.failedCount, 1);
    expect(run.cases.single.logPath, '/replay/c1.jsonl');
  });
}
