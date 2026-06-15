import 'dart:io';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Real process execution mirrors how an agent shell call would run the
  // recorded command. The POSIX `sh` invocations are skipped on Windows.
  group('ProcessPersonalEvalVerificationRunner', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('personal_eval_verify_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    ProcessPersonalEvalVerificationRunner buildRunner({Duration? timeout}) {
      return ProcessPersonalEvalVerificationRunner(
        timeout: timeout ?? const Duration(seconds: 30),
        // Avoid spawning the login shell in tests; inherit the parent env.
        environmentProvider: () async => null,
      );
    }

    test('exit code 0 maps to passed', () async {
      final outcome = await buildRunner().run(
        command: 'exit 0',
        workingDirectory: tempDir.path,
      );

      expect(outcome.result, PersonalEvalVerificationResult.passed);
      expect(outcome.exitCode, 0);
      expect(outcome.timedOut, isFalse);
      expect(outcome.error, isNull);
    });

    test('a non-zero exit code maps to failed', () async {
      final outcome = await buildRunner().run(
        command: 'exit 3',
        workingDirectory: tempDir.path,
      );

      expect(outcome.result, PersonalEvalVerificationResult.failed);
      expect(outcome.exitCode, 3);
    });

    test('runs in the given working directory and captures stdout', () async {
      final outcome = await buildRunner().run(
        command: 'echo marker > produced.txt && echo hello',
        workingDirectory: tempDir.path,
      );

      expect(outcome.result, PersonalEvalVerificationResult.passed);
      expect(outcome.stdout, contains('hello'));
      expect(
        File('${tempDir.path}/produced.txt').existsSync(),
        isTrue,
        reason: 'command should execute inside the working directory',
      );
    });

    test('a timeout maps to inconclusive', () async {
      final outcome = await buildRunner(
        timeout: const Duration(milliseconds: 200),
      ).run(command: 'sleep 5', workingDirectory: tempDir.path);

      expect(outcome.result, PersonalEvalVerificationResult.inconclusive);
      expect(outcome.timedOut, isTrue);
      expect(outcome.error, contains('timed out'));
    });
  }, skip: Platform.isWindows);

  group('ProcessPersonalEvalVerificationRunner guards', () {
    ProcessPersonalEvalVerificationRunner buildRunner() {
      return ProcessPersonalEvalVerificationRunner(
        environmentProvider: () async => null,
      );
    }

    test(
      'a blank command is inconclusive without launching a process',
      () async {
        final outcome = await buildRunner().run(
          command: '   ',
          workingDirectory: Directory.systemTemp.path,
        );

        expect(outcome.result, PersonalEvalVerificationResult.inconclusive);
        expect(outcome.error, contains('empty'));
      },
    );

    test('a missing working directory is inconclusive', () async {
      final outcome = await buildRunner().run(
        command: 'exit 0',
        workingDirectory: '/nonexistent/personal_eval/path',
      );

      expect(outcome.result, PersonalEvalVerificationResult.inconclusive);
      expect(outcome.error, contains('not found'));
    });
  });
}
