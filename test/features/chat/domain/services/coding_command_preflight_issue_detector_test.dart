import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/coding_command_preflight_issue_detector.dart';

void main() {
  const detector = CodingCommandPreflightIssueDetector();

  group('CodingCommandPreflightIssue', () {
    test('serializes every public field without changing names', () {
      const issue = CodingCommandPreflightIssue(
        code: 'code',
        command: 'command',
        workingDirectory: '/workspace',
        segment: 'segment',
        summary: 'summary',
        instruction: 'instruction',
        targets: ['one', 'two'],
      );

      expect(issue.toJson(), {
        'code': 'code',
        'command': 'command',
        'working_directory': '/workspace',
        'segment': 'segment',
        'summary': 'summary',
        'instruction': 'instruction',
        'targets': ['one', 'two'],
      });
    });
  });

  group('Dart create preflight', () {
    test('filters unsupported tools and blank commands', () {
      expect(
        detector.detect(
          toolName: 'run_tests',
          command: 'dart create one two',
          workingDirectory: '/tmp',
        ),
        isNull,
      );
      expect(
        detector.detect(
          toolName: ' process_start ',
          command: '   ',
          workingDirectory: '/tmp',
        ),
        isNull,
      );
      expect(
        detector.detect(
          toolName: ' LOCAL_EXECUTE_COMMAND ',
          command: ' echo ready ',
          workingDirectory: '/tmp',
        ),
        isNull,
      );
    });

    test('reports multiple targets with byte-compatible fields', () {
      final issue = detector.detect(
        toolName: 'local_execute_command',
        command: ' cd /tmp && dart create --force . sample ',
        workingDirectory: '/tmp',
      );

      expect(issue, isNotNull);
      expect(issue!.toJson(), {
        'code': 'dart_create_multiple_targets',
        'command': 'cd /tmp && dart create --force . sample',
        'working_directory': '/tmp',
        'segment': 'dart create --force . sample',
        'summary': 'Dart create command specifies multiple target directories.',
        'instruction':
            'Run dart create with exactly one target directory. Use '
            '"dart create --force prime_numbers_pkg" from the parent '
            'directory, or create the directory first and run '
            '"dart create --force ." inside it.',
        'targets': ['.', 'sample'],
      });
    });

    test('reports separated, missing, and equals-style type options', () {
      final separated = detector.detect(
        toolName: 'local_execute_command',
        command: 'dart create --type package .',
        workingDirectory: '/tmp/project',
      );
      final missing = detector.detect(
        toolName: 'local_execute_command',
        command: 'dart create --type',
        workingDirectory: '/tmp/project',
      );
      final emptyEquals = detector.detect(
        toolName: 'local_execute_command',
        command: 'dart create --type= sample',
        workingDirectory: '/tmp/project',
      );
      final fvm = detector.detect(
        toolName: 'process_start',
        command: 'fvm dart create --type=package sample',
        workingDirectory: '/tmp',
      );

      expect(
        separated!.instruction,
        'Replace "--type package" with '
        '"--template package".',
      );
      expect(separated.targets, ['.']);
      expect(
        missing!.instruction,
        'Replace "--type" with '
        '"--template <template>".',
      );
      expect(missing.targets, isEmpty);
      expect(
        emptyEquals!.instruction,
        'Replace "--type" with '
        '"--template <template>".',
      );
      expect(emptyEquals.targets, ['sample']);
      expect(
        fvm!.instruction,
        'Replace "--type package" with '
        '"--template package".',
      );
      expect(fvm.targets, ['sample']);
    });

    test('accepts value options, equals options, and one target', () {
      for (final command in const [
        'dart create --force .',
        'dart create --template console-full sample',
        'dart create --template=console sample',
        'dart create -t console sample',
        'dart create --description sample-app sample',
        'fvm dart create --sample cli sample',
      ]) {
        expect(
          detector.detect(
            toolName: 'local_execute_command',
            command: command,
            workingDirectory: '/tmp',
          ),
          isNull,
          reason: command,
        );
      }
    });

    test('treats arguments after the option terminator as targets', () {
      final issue = detector.detect(
        toolName: 'local_execute_command',
        command: 'dart create -- first second',
        workingDirectory: '/tmp',
      );

      expect(issue!.code, 'dart_create_multiple_targets');
      expect(issue.targets, ['first', 'second']);
    });

    test(
      'parses escaped quotes, spaces, and backslashes deterministically',
      () {
        final quoted = detector.detect(
          toolName: 'local_execute_command',
          command: r'dart create \"first\\ target\" second',
          workingDirectory: '/tmp',
        );
        final escaped = detector.detect(
          toolName: 'local_execute_command',
          command: r'dart create first\\\\target second',
          workingDirectory: '/tmp',
        );
        final segmented = detector.detect(
          toolName: 'local_execute_command',
          command:
              "echo 'a\\;b'; echo escaped\\;value ||\n"
              'fvm dart create first second',
          workingDirectory: '/tmp',
        );

        expect(quoted!.targets, ['first target', 'second']);
        expect(escaped!.targets, ['first\\target', 'second']);
        expect(segmented!.segment, 'fvm dart create first second');
      },
    );
  });

  group('masked exit status', () {
    const observedCommand =
        'rm -f state.json && dart run bin/todo.dart list '
        '&& dart run bin/todo.dart add task '
        r'&& dart run bin/todo.dart done missing; test $? -ne 0';

    test('returns exact failure evidence for a status-swallowing tail', () {
      final issue = detector.detectMaskedExitStatusIssue(
        command: observedCommand,
        workingDirectory: '/tmp/todo',
      );

      expect(issue, isNotNull);
      expect(issue!.code, 'masked_exit_status');
      expect(issue.command, observedCommand);
      expect(issue.workingDirectory, '/tmp/todo');
      expect(issue.segment, r'test $? -ne 0');
      expect(issue.summary, contains('not evidence'));
      expect(issue.instruction, contains('drop the trailing'));
    });

    test('detects every supported non-failing tail', () {
      for (final tail in const [
        'true',
        ':',
        'exit 0',
        r'echo $?',
        r'test $? != 0',
        r'[ $? -ne 0 ]',
      ]) {
        expect(
          detector.detectMaskedExitStatusIssue(
            command: 'first && second; $tail',
          ),
          isNotNull,
          reason: tail,
        );
      }
    });

    test('ignores blank, short, and failure-propagating chains', () {
      for (final command in const [
        '',
        'true',
        r'command; test $? -ne 0',
        'first && second && third',
        r'first; second; test $? -eq 0',
      ]) {
        expect(
          detector.detectMaskedExitStatusIssue(command: command),
          isNull,
          reason: command,
        );
      }
    });
  });
}
