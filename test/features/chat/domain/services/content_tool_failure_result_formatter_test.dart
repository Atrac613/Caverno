import 'dart:convert';

import 'package:caverno/features/chat/domain/services/content_tool_failure_result_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload(String block) =>
    jsonDecode(
          block
              .replaceFirst('<tool_result>', '')
              .replaceFirst('</tool_result>', ''),
        )
        as Map<String, dynamic>;

void main() {
  group('ContentToolFailureResultFormatter', () {
    test('marks the call as failed so the transcript can tint it', () {
      final payload = _payload(
        ContentToolFailureResultFormatter.format(
          'execute_command',
          '{"toolName":"execute_command","error":"exit 1",'
              '"code":"tool_execution_failed"}',
        ),
      );

      expect(payload['status'], 'error');
      expect(payload['name'], 'execute_command');
    });

    test('uses the error text as the summary, not a generic label', () {
      final payload = _payload(
        ContentToolFailureResultFormatter.format(
          'execute_command',
          '{"toolName":"execute_command","error":"exit 1: 3 issues found"}',
        ),
      );

      expect(payload['summary'], 'exit 1: 3 issues found');
      expect(payload['summary'], isNot('Completed'));
    });

    test('keeps the envelope fields as details', () {
      final payload = _payload(
        ContentToolFailureResultFormatter.format(
          'read_file',
          '{"error":"no such file","code":"enoent"}',
        ),
      );

      expect(payload['details'], contains('code: enoent'));
    });

    test('falls back to the first line for a non-JSON failure', () {
      final payload = _payload(
        ContentToolFailureResultFormatter.format(
          'read_file',
          'Permission denied\nwhile reading /etc/shadow',
        ),
      );

      expect(payload['summary'], 'Permission denied');
      expect(payload['details'], contains('while reading /etc/shadow'));
    });

    test('labels an empty failure rather than claiming success', () {
      final payload = _payload(
        ContentToolFailureResultFormatter.format('read_file', ''),
      );

      expect(payload['summary'], 'Failed');
      expect(payload['status'], 'error');
    });
  });
}
