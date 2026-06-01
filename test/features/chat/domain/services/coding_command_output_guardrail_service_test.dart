import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';

void main() {
  group('CodingCommandOutputGuardrailService', () {
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
