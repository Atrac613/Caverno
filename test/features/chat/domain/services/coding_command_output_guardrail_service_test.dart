import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';

void main() {
  group('masked exit status', () {
    // The command a live run actually issued: the chain broke at the id
    // extraction, yet it reported exit 0 because it ended in an assertion that
    // the previous command had failed — and the model read that 0 as "every
    // acceptance criterion verified".
    const observedCommand =
        'rm -f todo_state.json && dart run bin/todo.dart list '
        '&& dart run bin/todo.dart add "task one" '
        '&& ID1=\$(dart run bin/todo.dart list | sed -n \'1p\' | awk \'{print \$1}\') '
        '&& dart run bin/todo.dart done "\$ID1" '
        '&& dart run bin/todo.dart done missing-id; test \$? -ne 0';

    test('refuses a chain that ends by asserting the previous failure', () {
      final issue =
          CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue(
            command: observedCommand,
          );

      expect(issue, isNotNull);
      expect(issue!.code, 'masked_exit_status');
      expect(issue.segment, 'test \$? -ne 0');
      expect(issue.instruction, contains('drop the trailing'));
    });

    test('a masked chain that exited 0 is not usable evidence', () {
      final issue =
          CodingCommandOutputGuardrailService.detectIssueFromDecodedCommandResult(
            toolName: 'local_execute_command',
            decoded: {
              'command': observedCommand,
              'working_directory': '/tmp/todo',
              'exit_code': 0,
              'stdout': 'No tasks.',
              'stderr': '',
            },
          );

      expect(issue, isNotNull);
      expect(issue!.exitCode, 0);
      expect(issue.source, 'command');
      expect(issue.summary, contains('not evidence'));
    });

    test('flags the other status-swallowing endings', () {
      for (final tail in [
        '|| true',
        '; true',
        '; :',
        '; exit 0',
        '; echo \$?',
      ]) {
        expect(
          CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue(
            command: 'dart analyze && dart test $tail',
          ),
          isNotNull,
          reason: 'a chain ending in "$tail" cannot report an earlier failure',
        );
      }
    });

    test('a single command plus an assertion is a real negative check', () {
      expect(
        CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue(
          command: 'dart run bin/todo.dart done 999; test \$? -ne 0',
        ),
        isNull,
        reason:
            'the assertion is the check itself: exit 0 means that command '
            'failed as the acceptance criterion requires',
      );
    });

    test('leaves chains that propagate a failure alone', () {
      const propagating = [
        'dart analyze && dart test',
        'dart run bin/todo.dart list; test \$? -eq 0',
        'rm -f state.json && dart run bin/todo.dart list',
        'test -f pubspec.yaml && dart analyze bin/todo.dart',
      ];
      for (final command in propagating) {
        expect(
          CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue(
            command: command,
          ),
          isNull,
          reason: '"$command" still fails when a step fails',
        );
      }
    });

    test('a bare non-failing command masks nothing on its own', () {
      expect(
        CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue(
          command: 'true',
        ),
        isNull,
      );
    });
  });

  group('CodingCommandOutputGuardrailService', () {
    test('builds feedback from a zero-exit artifact error replay', () {
      final fixture = _loadReplayFixture(
        'coding_zero_exit_artifact_error_replay.json',
      );
      final feedback = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(
            toolResults: fixture.toolResults,
            now: DateTime.fromMicrosecondsSinceEpoch(42),
          );

      expect(feedback, isNotNull);
      expect(feedback!.id, 'coding_output_feedback_42');
      expect(feedback.name, fixture.expectedFeedbackToolName);

      final payload = jsonDecode(feedback.result) as Map<String, dynamic>;
      expect(payload['schema'], CodingCommandOutputGuardrailService.schemaName);
      expect(payload['success'], isFalse);
      expect(payload['validation_status'], fixture.expectedValidationStatus);
      final issues = payload['issues'] as List<dynamic>;
      expect(issues, hasLength(1));
      expect(issues.single, containsPair('command', fixture.expectedCommand));
      expect(issues.single, containsPair('source', 'stdout'));
      expect(
        issues.single,
        containsPair('summary', fixture.expectedIssueSummary),
      );
      expect(
        CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
          fixture.toolResults.single.result,
        ),
        isTrue,
      );
    });

    test(
      'builds feedback when a successful command prints an error artifact',
      () {
        final feedback = const CodingCommandOutputGuardrailService()
            .buildFeedbackToolResult(
              toolResults: [
                ToolResultInfo(
                  id: 'call-1',
                  name: 'local_execute_command',
                  arguments: const {
                    'command': 'python3 get_weather.py',
                    'working_directory': '/tmp/weather',
                  },
                  result: jsonEncode({
                    'command': 'python3 get_weather.py',
                    'working_directory': '/tmp/weather',
                    'exit_code': 0,
                    'stdout':
                        'Saved file\n\n# ${_cjkErrorLabel()}\n\n2026-06-02 ${_cjkDataMissing()}.\n',
                    'stderr': '',
                  }),
                ),
              ],
              now: DateTime.fromMicrosecondsSinceEpoch(7),
            );

        expect(feedback, isNotNull);
        expect(feedback!.id, 'coding_output_feedback_7');
        expect(feedback.name, CodingCommandOutputGuardrailService.toolName);

        final payload = jsonDecode(feedback.result) as Map<String, dynamic>;
        expect(
          payload['schema'],
          CodingCommandOutputGuardrailService.schemaName,
        );
        expect(payload['success'], isFalse);
        expect(payload['validation_status'], 'failed');
        final issues = payload['issues'] as List<dynamic>;
        expect(issues, hasLength(1));
        expect(
          issues.single,
          containsPair('command', 'python3 get_weather.py'),
        );
        expect(
          issues.single,
          containsPair('summary', 'Output contains a Markdown error heading.'),
        );
      },
    );

    test('ignores expected error text from a passing test command', () {
      final feedback = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(
            toolResults: [
              ToolResultInfo(
                id: 'call-1',
                name: 'local_execute_command',
                arguments: const {'command': 'python3 test_ping.py'},
                result: jsonEncode({
                  'command': 'python3 test_ping.py',
                  'exit_code': 0,
                  'stdout':
                      'Ran 3 tests in 0.001s\n\nOK\nError: ping command not found.\n',
                  'stderr': '',
                }),
              ),
            ],
          );

      expect(feedback, isNull);
    });

    test('detects missing data output with a zero exit code', () {
      final rawResult = jsonEncode({
        'command': 'python3 get_weather.py',
        'exit_code': 0,
        'stdout': 'No data found for 2026-06-02.',
        'stderr': '',
      });

      expect(
        CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
          rawResult,
        ),
        isTrue,
      );
    });

    test('detects a dart create command with multiple targets', () {
      final issue = CodingCommandOutputGuardrailService.detectPreflightIssue(
        toolName: 'local_execute_command',
        command:
            'cd /Users/noguwo/Documents/Workspace/tmp && dart create --force . prime_numbers_pkg',
        workingDirectory: '/Users/noguwo/Documents/Workspace/tmp',
      );

      expect(issue, isNotNull);
      expect(issue!.code, 'dart_create_multiple_targets');
      expect(issue.segment, 'dart create --force . prime_numbers_pkg');
      expect(issue.targets, ['.', 'prime_numbers_pkg']);
    });

    test('reports dart create type as an unsupported option', () {
      final issue = CodingCommandOutputGuardrailService.detectPreflightIssue(
        toolName: 'local_execute_command',
        command: 'dart create --type package .',
        workingDirectory: '/tmp/project',
      );

      expect(issue, isNotNull);
      expect(issue!.code, 'dart_create_unsupported_option');
      expect(issue.segment, 'dart create --type package .');
      expect(
        issue.summary,
        'Dart create does not support the "--type" option.',
      );
      expect(
        issue.instruction,
        'Replace "--type package" with "--template package".',
      );
      expect(issue.targets, ['.']);
    });

    test('reports an equals-style dart create type option', () {
      final issue = CodingCommandOutputGuardrailService.detectPreflightIssue(
        toolName: 'process_start',
        command: 'fvm dart create --type=package sample_pkg',
        workingDirectory: '/tmp',
      );

      expect(issue, isNotNull);
      expect(issue!.code, 'dart_create_unsupported_option');
      expect(
        issue.instruction,
        'Replace "--type package" with "--template package".',
      );
      expect(issue.targets, ['sample_pkg']);
    });

    test('allows dart create with a single target directory', () {
      final service = CodingCommandOutputGuardrailService.detectPreflightIssue;

      expect(
        service(
          toolName: 'local_execute_command',
          command: 'dart create --force .',
          workingDirectory: '/tmp/project',
        ),
        isNull,
      );
      expect(
        service(
          toolName: 'local_execute_command',
          command: 'dart create --template console-full prime_numbers_pkg',
          workingDirectory: '/tmp',
        ),
        isNull,
      );
      expect(
        service(
          toolName: 'local_execute_command',
          command: 'fvm dart create --template=console prime_numbers_pkg',
          workingDirectory: '/tmp',
        ),
        isNull,
      );
    });

    test('builds feedback from a zero-exit malformed dart create command', () {
      final feedback = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(
            toolResults: [
              ToolResultInfo(
                id: 'call-1',
                name: 'local_execute_command',
                arguments: const {
                  'command':
                      'cd /Users/noguwo/Documents/Workspace/tmp && dart create --force . prime_numbers_pkg',
                  'working_directory': '/Users/noguwo/Documents/Workspace/tmp',
                },
                result: jsonEncode({
                  'command':
                      'cd /Users/noguwo/Documents/Workspace/tmp && dart create --force . prime_numbers_pkg',
                  'working_directory': '/Users/noguwo/Documents/Workspace/tmp',
                  'exit_code': 0,
                  'stdout':
                      'Creating tmp using template console...\n'
                      'Created project tmp in .!\n',
                  'stderr': '',
                }),
              ),
            ],
            now: DateTime.fromMicrosecondsSinceEpoch(11),
          );

      expect(feedback, isNotNull);
      final payload = jsonDecode(feedback!.result) as Map<String, dynamic>;
      final issues = payload['issues'] as List<dynamic>;
      expect(issues, hasLength(1));
      expect(issues.single, containsPair('source', 'command'));
      expect(
        issues.single,
        containsPair(
          'summary',
          'Dart create command specifies multiple target directories.',
        ),
      );
    });
  });
}

_ReplayFixture _loadReplayFixture(String fixtureName) {
  final fixture =
      jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
          as Map<String, dynamic>;
  final expected = fixture['expected'] as Map<String, dynamic>;
  return _ReplayFixture(
    toolResults: (fixture['toolResults'] as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => ToolResultInfo(
            id: item['id'] as String,
            name: item['name'] as String,
            arguments: item['arguments'] as Map<String, dynamic>,
            result: item['result'] as String,
          ),
        )
        .toList(growable: false),
    expectedCommand: expected['command'] as String,
    expectedFeedbackToolName: expected['feedbackToolName'] as String,
    expectedValidationStatus: expected['validationStatus'] as String,
    expectedIssueSummary: expected['issueSummary'] as String,
  );
}

class _ReplayFixture {
  const _ReplayFixture({
    required this.toolResults,
    required this.expectedCommand,
    required this.expectedFeedbackToolName,
    required this.expectedValidationStatus,
    required this.expectedIssueSummary,
  });

  final List<ToolResultInfo> toolResults;
  final String expectedCommand;
  final String expectedFeedbackToolName;
  final String expectedValidationStatus;
  final String expectedIssueSummary;
}

String _cjkErrorLabel() {
  return String.fromCharCodes([0x30a8, 0x30e9, 0x30fc]);
}

String _cjkDataMissing() {
  return String.fromCharCodes([
    0x30c7,
    0x30fc,
    0x30bf,
    0x304c,
    0x898b,
    0x3064,
    0x304b,
    0x308a,
    0x307e,
    0x305b,
    0x3093,
  ]);
}
