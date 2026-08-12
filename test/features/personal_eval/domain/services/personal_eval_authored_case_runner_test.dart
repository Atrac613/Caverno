import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/live_personal_eval_case_runner.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_authored_case_runner.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repositoryRoot = Directory.current.path;
  final corpus = PersonalEvalAuthoredCorpus.parse(
    File('tool/personal_eval_corpus/corpus.json').readAsStringSync(),
  );
  final evalCase = corpus.cases.first;

  PersonalEvalAuthoredCaseRunner buildRunner({
    required PersonalEvalReplayTurnDriver Function(String, PersonalEvalCase)
    driverFactory,
    PersonalEvalVerificationRunner? verificationRunner,
  }) => PersonalEvalAuthoredCaseRunner(
    driverFactory: driverFactory,
    verificationRunner: verificationRunner ?? _PassingVerificationRunner(),
    repositoryRoot: repositoryRoot,
    seedRoot: corpus.seedRoot,
  );

  test('drives the candidate inside a materialized workspace', () async {
    final driver = _RecordingDriver();
    final verifier = _RecordingVerificationRunner();
    final runner = buildRunner(
      driverFactory: (dir, _) => driver..workingDirectory = dir,
      verificationRunner: verifier,
    );

    final outcome = await runner.run(evalCase);

    expect(outcome.verificationResult, PersonalEvalVerificationResult.passed);
    expect(driver.observedDirectory, isNotEmpty);
    expect(
      driver.observedDirectory.startsWith(repositoryRoot),
      isFalse,
      reason: 'the candidate must never be pointed at the repository tree',
    );
    // Verification has to run where the candidate actually worked.
    expect(verifier.observedDirectory, driver.observedDirectory);
    expect(verifier.observedCommand, evalCase.verificationCommand);
  });

  test('removes the workspace after the case', () async {
    final driver = _RecordingDriver();
    final runner = buildRunner(
      driverFactory: (dir, _) => driver..workingDirectory = dir,
    );

    await runner.run(evalCase);

    expect(Directory(driver.observedDirectory).existsSync(), isFalse);
  });

  test('removes the workspace even when the drive throws', () async {
    late String captured;
    final runner = buildRunner(
      driverFactory: (dir, _) {
        captured = dir;
        return _ThrowingDriver();
      },
    );

    final outcome = await runner.run(evalCase);

    expect(
      outcome.verificationResult,
      PersonalEvalVerificationResult.inconclusive,
    );
    expect(outcome.error, contains('threw'));
    expect(
      Directory(captured).existsSync(),
      isFalse,
      reason: 'a leaked tree per case is a disk leak across a repeated run',
    );
  });

  test('rejects a pass when the candidate changes the verifier', () async {
    final verifier = _RecordingVerificationRunner();
    final runner = buildRunner(
      driverFactory: (dir, _) => _VerifierReplacingDriver(dir),
      verificationRunner: verifier,
    );

    final outcome = await runner.run(evalCase);

    expect(
      outcome.verificationResult,
      PersonalEvalVerificationResult.inconclusive,
    );
    expect(outcome.error, contains('Verification harness file changed'));
    expect(
      verifier.observedCommand,
      isEmpty,
      reason: 'a modified verifier must never be executed or scored',
    );
  });

  test(
    'a case that could not be prepared is inconclusive, not failed',
    () async {
      final runner = buildRunner(driverFactory: (_, _) => _RecordingDriver());

      final outcome = await runner.run(
        evalCase.copyWith(caseId: 'no_such_seed'),
      );

      // The candidate was never given the task, so scoring it a failure would
      // charge the model for a harness problem.
      expect(
        outcome.verificationResult,
        PersonalEvalVerificationResult.inconclusive,
      );
      expect(outcome.error, contains('Could not prepare a workspace'));
    },
  );

  test(
    'a failing verification after a thrown turn is not a model failure',
    () async {
      final runner = buildRunner(
        driverFactory: (dir, _) => _FailedTurnDriver(dir),
        verificationRunner: const _FixedVerificationRunner(
          PersonalEvalVerificationResult.failed,
        ),
      );

      final outcome = await runner.run(evalCase);

      // The 2026-08-12 pilot scored three proxy 500s as model failures on tasks
      // the same model had already solved in its other trial, and those three
      // drove the entire reported effect.
      expect(
        outcome.verificationResult,
        PersonalEvalVerificationResult.inconclusive,
      );
      expect(outcome.error, contains('proxy error'));
    },
  );

  test('a passing verification after a thrown turn still counts', () async {
    final runner = buildRunner(
      driverFactory: (dir, _) => _FailedTurnDriver(dir),
      verificationRunner: const _FixedVerificationRunner(
        PersonalEvalVerificationResult.passed,
      ),
    );

    final outcome = await runner.run(evalCase);

    // Asymmetric on purpose: a turn can throw after the candidate already
    // fixed the workspace, and demonstrable success is still success.
    expect(outcome.verificationResult, PersonalEvalVerificationResult.passed);
  });

  test('refuses a recorded case instead of replaying it', () async {
    final runner = buildRunner(driverFactory: (_, _) => _RecordingDriver());

    final outcome = await runner.run(
      const PersonalEvalCase(
        caseId: 'recorded-1',
        prompt: 'p',
        repoStateRef: 'abc',
        consentGranted: true,
      ),
    );

    expect(outcome.skipped, isTrue);
    expect(outcome.skipReason, contains('authored fixture cases'));
  });
}

class _RecordingDriver implements PersonalEvalReplayTurnDriver {
  String workingDirectory = '';
  String observedDirectory = '';

  @override
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase) async {
    observedDirectory = workingDirectory;
    return PersonalEvalReplayTurnResult(
      logPath: '/tmp/log.jsonl',
      logContents: '{}',
      workingDirectory: workingDirectory,
    );
  }
}

class _ThrowingDriver implements PersonalEvalReplayTurnDriver {
  @override
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase) async {
    throw StateError('driver exploded');
  }
}

class _VerifierReplacingDriver implements PersonalEvalReplayTurnDriver {
  const _VerifierReplacingDriver(this.workingDirectory);

  final String workingDirectory;

  @override
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase) async {
    File(
      '$workingDirectory/bin/verify.dart',
    ).writeAsStringSync('void main() {}\n');
    return PersonalEvalReplayTurnResult(
      logPath: '/tmp/log.jsonl',
      logContents: '{}',
      workingDirectory: workingDirectory,
    );
  }
}

class _FailedTurnDriver implements PersonalEvalReplayTurnDriver {
  const _FailedTurnDriver(this.workingDirectory);

  final String workingDirectory;

  @override
  Future<PersonalEvalReplayTurnResult> drive(PersonalEvalCase evalCase) async {
    return PersonalEvalReplayTurnResult(
      logPath: '/tmp/log.jsonl',
      logContents: '{}',
      workingDirectory: workingDirectory,
      error:
          'InternalServerException: proxy error: Failed to read connection '
          '(status: 500)',
    );
  }
}

class _FixedVerificationRunner implements PersonalEvalVerificationRunner {
  const _FixedVerificationRunner(this.result);

  final PersonalEvalVerificationResult result;

  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) async => PersonalEvalVerificationOutcome(result: result, exitCode: 0);
}

class _PassingVerificationRunner implements PersonalEvalVerificationRunner {
  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) async => const PersonalEvalVerificationOutcome(
    result: PersonalEvalVerificationResult.passed,
    exitCode: 0,
  );
}

class _RecordingVerificationRunner implements PersonalEvalVerificationRunner {
  String observedCommand = '';
  String observedDirectory = '';

  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) async {
    observedCommand = command;
    observedDirectory = workingDirectory;
    return const PersonalEvalVerificationOutcome(
      result: PersonalEvalVerificationResult.passed,
      exitCode: 0,
    );
  }
}
