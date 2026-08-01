import 'dart:convert';

import 'package:caverno/features/chat/domain/services/content_tool_failure_formatter.dart';
import 'package:test/test.dart';

const _formatter = ContentToolFailureFormatter();

void main() {
  group('ContentToolFailureFormatter', () {
    test('uses the exact default error only for a null message', () {
      final encoded = _formatter.format('read_file', null);

      expect(
        encoded,
        '{"toolName":"read_file","error":"Tool execution failed",'
        '"code":"tool_execution_failed"}',
      );
      expect(jsonDecode(encoded), {
        'toolName': 'read_file',
        'error': 'Tool execution failed',
        'code': 'tool_execution_failed',
      });
    });

    test('preserves empty and whitespace-only messages after trimming', () {
      for (final message in ['', ' \n\t ']) {
        final encoded = _formatter.format('edit_file', message);

        expect(
          encoded,
          '{"toolName":"edit_file","error":"",'
          '"code":"tool_execution_failed"}',
        );
        expect(jsonDecode(encoded), {
          'toolName': 'edit_file',
          'error': '',
          'code': 'tool_execution_failed',
        });
      }
    });

    test('trims a nonempty message without changing internal whitespace', () {
      final encoded = _formatter.format(
        'local_execute_command',
        '  Failed  with two spaces.  ',
      );

      expect(
        encoded,
        '{"toolName":"local_execute_command",'
        '"error":"Failed  with two spaces.",'
        '"code":"tool_execution_failed"}',
      );
      expect(jsonDecode(encoded), {
        'toolName': 'local_execute_command',
        'error': 'Failed  with two spaces.',
        'code': 'tool_execution_failed',
      });
    });

    test('classifies every recognized phrase case-insensitively', () {
      final cases = <({String message, String code})>[
        (
          message: 'No matching tool available for this request',
          code: 'tool_not_available',
        ),
        (
          message: 'OLD_TEXT WAS NOT FOUND IN THE TARGET FILE',
          code: 'edit_mismatch',
        ),
        (
          message: 'Operation failed: Permission_Denied',
          code: 'permission_denied',
        ),
        (message: 'Request TIMEOUT while executing', code: 'timeout'),
      ];

      for (final testCase in cases) {
        expect(
          (jsonDecode(_formatter.format('tool', testCase.message))
              as Map<String, dynamic>)['code'],
          testCase.code,
          reason: testCase.message,
        );
      }
    });

    test('uses the current classification precedence for overlaps', () {
      final phrases = [
        'timeout',
        'permission_denied',
        'old_text was not found in the target file',
        'no matching tool available',
      ];

      expect(_code(phrases.join(' / ')), 'tool_not_available');
      expect(_code(phrases.take(3).join(' / ')), 'edit_mismatch');
      expect(_code(phrases.take(2).join(' / ')), 'permission_denied');
    });

    test('does not classify similar but nonmatching wording', () {
      final messages = [
        'No tool was selected',
        'The old text differs from the file',
        'Permission denied',
        'The operation timed out',
      ];

      for (final message in messages) {
        expect(_code(message), 'tool_execution_failed', reason: message);
      }
    });

    test('preserves and JSON-escapes the tool name without classifying it', () {
      final encoded = _formatter.format(
        ' no matching tool available: "custom"\n',
        'failure',
      );

      expect(
        encoded,
        '{"toolName":" no matching tool available: \\"custom\\"\\n",'
        '"error":"failure","code":"tool_execution_failed"}',
      );
      expect(jsonDecode(encoded), {
        'toolName': ' no matching tool available: "custom"\n',
        'error': 'failure',
        'code': 'tool_execution_failed',
      });
    });

    test('uses JSON encoding for control and Unicode content', () {
      final encoded = _formatter.format(
        'read_file',
        'line one\n"quoted" \\ path ☃',
      );

      expect(
        encoded,
        '{"toolName":"read_file","error":'
        '"line one\\n\\"quoted\\" \\\\ path ☃",'
        '"code":"tool_execution_failed"}',
      );
    });
  });
}

String _code(String message) =>
    (jsonDecode(_formatter.format('tool', message))
            as Map<String, dynamic>)['code']
        as String;
