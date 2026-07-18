import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/workflow_tool_result_failure_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkflowToolResultFailureDetector', () {
    test('ignores empty, malformed, and benign results', () {
      for (final rawResult in [
        '',
        '   ',
        '{malformed',
        'Completed successfully.',
        jsonEncode({'exit_code': 0, 'success': true, 'isSuccess': true}),
        jsonEncode({'exit_code': '1'}),
      ]) {
        expect(
          WorkflowToolResultFailureDetector.containsFailure([
            _result(rawResult),
          ]),
          isFalse,
          reason: rawResult,
        );
      }
    });

    test('detects every structured failure field', () {
      for (final payload in [
        {'exit_code': 1},
        {'exit_code': -1},
        {'success': false},
        {'isSuccess': false},
        {'error': 'write failed'},
        {'errorMessage': 'tool failed'},
      ]) {
        expect(
          WorkflowToolResultFailureDetector.containsFailure([
            _result(jsonEncode(payload)),
          ]),
          isTrue,
          reason: payload.toString(),
        );
      }
    });

    test('detects zero-exit command output issues', () {
      final rawResult = jsonEncode({
        'command': 'python3 weather.py',
        'exit_code': 0,
        'stdout': 'No data found for the requested date.',
        'stderr': '',
      });

      expect(
        WorkflowToolResultFailureDetector.containsFailure([_result(rawResult)]),
        isTrue,
      );
    });

    test('detects every case-insensitive raw failure marker', () {
      for (final rawResult in [
        'Error: unavailable',
        'FAILED TO execute the command',
        'No Matching Tool Available: google',
        'prefix "error": suffix',
        'prefix "isSuccess":false suffix',
        'prefix "success":false suffix',
        'prefix "errorMessage" suffix',
        jsonEncode({'error': ''}),
        jsonEncode({'errorMessage': ''}),
      ]) {
        expect(
          WorkflowToolResultFailureDetector.containsFailure([
            _result(rawResult),
          ]),
          isTrue,
          reason: rawResult,
        );
      }
    });

    test('returns true when a later result fails', () {
      expect(
        WorkflowToolResultFailureDetector.containsFailure([
          _result('Completed successfully.', id: 'first'),
          _result('{malformed', id: 'second'),
          _result(jsonEncode({'exit_code': 2}), id: 'third'),
        ]),
        isTrue,
      );
    });
  });
}

ToolResultInfo _result(String result, {String id = 'result'}) {
  return ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: const {},
    result: result,
  );
}
