import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_issue_detector.dart';

void main() {
  const detector = CodingCommandOutputIssueDetector();

  group('CodingCommandOutputIssue', () {
    test('preserves the stable signature and JSON shapes', () {
      const issue = CodingCommandOutputIssue(
        toolName: 'local_execute_command',
        command: 'dart test',
        workingDirectory: '/workspace',
        exitCode: 0,
        source: 'stdout',
        summary: 'summary',
        excerpt: 'excerpt',
      );

      expect(
        issue.signature,
        jsonEncode({
          'tool_name': 'local_execute_command',
          'command': 'dart test',
          'working_directory': '/workspace',
          'source': 'stdout',
          'summary': 'summary',
          'excerpt': 'excerpt',
        }),
      );
      expect(issue.toJson(), {
        'tool_name': 'local_execute_command',
        'command': 'dart test',
        'working_directory': '/workspace',
        'exit_code': 0,
        'source': 'stdout',
        'summary': 'summary',
        'excerpt': 'excerpt',
      });
    });
  });

  group('decoded command results', () {
    test('rejects invalid envelopes, unsupported tools, and nonzero exits', () {
      expect(
        detector.detect(
          ToolResultInfo(
            id: 'invalid',
            name: 'local_execute_command',
            arguments: const {},
            result: 'not-json',
          ),
        ),
        isNull,
      );
      expect(
        detector.detect(
          ToolResultInfo(
            id: 'list',
            name: 'local_execute_command',
            arguments: const {},
            result: '[]',
          ),
        ),
        isNull,
      );
      expect(
        detector.detectFromDecodedCommandResult(
          toolName: 'process_start',
          decoded: const {'exit_code': 0, 'stdout': '# Error'},
        ),
        isNull,
      );
      expect(
        detector.detectFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: const {'exit_code': 1, 'stdout': '# Error'},
        ),
        isNull,
      );
      expect(
        detector.detectFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: const {'exit_code': null, 'stdout': '# Error'},
        ),
        isNull,
      );
    });

    test('uses fallback arguments and normalizes decoded values', () {
      final fallback = detector.detect(
        ToolResultInfo(
          id: 'fallback',
          name: 'local_execute_command',
          arguments: const {
            'command': ' python3 app.py ',
            'working_directory': ' /workspace ',
          },
          result: jsonEncode({'exit_code': '0', 'stdout': 'No data found.'}),
        ),
      );
      final decoded = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: const {
          'exit_code': 0.0,
          'command': 42,
          'working_directory': ' /tmp ',
          'stdout': 'Fatal exception',
        },
      );

      expect(fallback!.command, 'python3 app.py');
      expect(fallback.workingDirectory, '/workspace');
      expect(fallback.exitCode, 0);
      expect(decoded!.command, '42');
      expect(decoded.workingDirectory, '/tmp');
      expect(decoded.summary, 'Output contains a runtime failure signal.');
    });

    test('supports every command-result tool name', () {
      for (final toolName in const [
        'local_execute_command',
        'run_tests',
        'git_execute_command',
        'ssh_execute_command',
      ]) {
        final issue = detector.detectFromDecodedCommandResult(
          toolName: ' $toolName ',
          decoded: const {'exit_code': 0, 'stdout': '# Error\nfailed'},
        );

        expect(issue, isNotNull, reason: toolName);
        expect(issue!.toolName, ' $toolName ');
      }
    });

    test('preserves command issue precedence over stdout and stderr', () {
      final dartCreate = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: const {
          'exit_code': 0,
          'command': 'dart create one two',
          'stdout': '# Error',
          'stderr': 'Traceback (most recent call last)',
        },
      );
      final masked = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: const {
          'exit_code': 0,
          'command': r'first && second; test $? -ne 0',
          'stdout': '# Error',
        },
      );

      expect(dartCreate!.source, 'command');
      expect(dartCreate.summary, contains('multiple target'));
      expect(masked!.source, 'command');
      expect(masked.summary, contains('not evidence'));
    });

    test('checks stdout before stderr and skips blank or clean streams', () {
      final stdoutIssue = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: const {
          'exit_code': 0,
          'stdout': '# Error\nstdout failure',
          'stderr': 'Traceback (most recent call last)',
        },
      );
      final stderrIssue = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: const {
          'exit_code': 0,
          'stdout': 'completed',
          'stderr': 'Unhandled exception',
        },
      );
      final blankStdout = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: const {
          'exit_code': 0,
          'stdout': '   ',
          'stderr': 'Fatal exception',
        },
      );

      expect(stdoutIssue!.source, 'stdout');
      expect(stderrIssue!.source, 'stderr');
      expect(blankStdout!.source, 'stderr');
    });

    test('recognizes localized headings and missing-data variants', () {
      final cjkHeading = '# ${_cjkErrorLabel()}';
      final cjkMissing = '2026-06-02 ${_cjkDataMissing()}.';
      for (final output in [
        cjkHeading,
        cjkMissing,
        'Data not found.',
        'Could not find data.',
        'Required data was not found.',
      ]) {
        expect(
          detector.detectFromDecodedCommandResult(
            toolName: 'local_execute_command',
            decoded: {'exit_code': 0, 'stdout': output},
          ),
          isNotNull,
          reason: output,
        );
      }
    });

    test('recognizes traceback and runtime failure variants', () {
      for (final output in const [
        'Traceback (most recent call last)',
        'Uncaught exception',
        'Unhandled exception',
        'Fatal exception',
      ]) {
        final issue = detector.detectFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: {'exit_code': 0, 'stderr': output},
        );

        expect(issue!.summary, 'Output contains a runtime failure signal.');
      }
    });

    test('returns no issue for clean or expected test output', () {
      expect(
        detector.detectFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: const {
            'exit_code': 0,
            'stdout': 'Ran 3 tests\nOK\nError: expected fixture text.',
            'stderr': '',
          },
        ),
        isNull,
      );
    });

    test('extracts the failing suffix and caps it at 600 characters', () {
      final output = '${'prefix\n' * 4}# Error\n${'x' * 800}';
      final issue = detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: {'exit_code': 0, 'stdout': output},
      );

      expect(issue!.excerpt, startsWith('# Error'));
      expect(issue.excerpt, endsWith('...'));
      expect(issue.excerpt.length, 600);
    });
  });

  group('feedback signatures and raw results', () {
    ToolResultInfo feedback(String name, Object payload) {
      return ToolResultInfo(
        id: 'feedback',
        name: name,
        arguments: const {},
        result: payload is String ? payload : jsonEncode(payload),
      );
    }

    test('requires the exact feedback tool and at least one issue', () {
      expect(
        detector.feedbackSignature(
          feedback('other', const {}),
          feedbackToolName: 'coding_output_feedback',
        ),
        isNull,
      );
      expect(
        detector.feedbackSignature(
          feedback('coding_output_feedback', 'not-json'),
          feedbackToolName: 'coding_output_feedback',
        ),
        isNull,
      );
      expect(
        detector.feedbackSignature(
          feedback('coding_output_feedback', const {'issues': []}),
          feedbackToolName: 'coding_output_feedback',
        ),
        isNull,
      );
    });

    test('builds a stable signature from only compatibility fields', () {
      final signature = detector.feedbackSignature(
        feedback('coding_output_feedback', const {
          'provider': 'command_output_guardrail',
          'validation_status': 'failed',
          'issues': [
            {'summary': 'failed'},
          ],
          'ignored': true,
        }),
        feedbackToolName: 'coding_output_feedback',
      );

      expect(
        signature,
        jsonEncode({
          'provider': 'command_output_guardrail',
          'validation_status': 'failed',
          'issues': [
            {'summary': 'failed'},
          ],
        }),
      );
    });

    test('classifies raw JSON without throwing on invalid input', () {
      expect(detector.commandResultReportsOutputIssue('not-json'), isFalse);
      expect(
        detector.commandResultReportsOutputIssue(
          jsonEncode({'exit_code': 0, 'stdout': 'all good'}),
        ),
        isFalse,
      );
      expect(
        detector.commandResultReportsOutputIssue(
          jsonEncode({'exit_code': 0, 'stdout': 'No data found.'}),
        ),
        isTrue,
      );
    });
  });
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
