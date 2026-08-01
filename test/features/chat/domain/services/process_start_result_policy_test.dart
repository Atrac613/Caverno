import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/process_start_result_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = ProcessStartResultPolicy();
  final dispatchedAt = DateTime.utc(2026, 1, 2, 12);

  group('ProcessStartResultPolicy', () {
    test('ignores non-process tools and failed dispatches', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(name: 'process_status'),
          _result(_validPayload(dispatchedAt)),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result(_validPayload(dispatchedAt), isSuccess: false),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('ignores malformed and non-map JSON payloads', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _rawResult('{not-json'),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _rawResult(jsonEncode(['not', 'a', 'map'])),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('requires an explicitly successful payload', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({..._validPayload(dispatchedAt), 'ok': false}),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({..._validPayload(dispatchedAt)..remove('ok')}),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('requires a non-empty parseable start timestamp', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({..._validPayload(dispatchedAt)..remove('started_at')}),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({..._validPayload(dispatchedAt), 'started_at': ' '}),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({
            ..._validPayload(dispatchedAt),
            'started_at': 'not-a-timestamp',
          }),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('allows duplicate existing process results', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({..._validPayload(dispatchedAt), 'duplicate_existing': true}),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('allows a result exactly at the five-second boundary', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({
            ..._validPayload(dispatchedAt),
            'started_at': dispatchedAt
                .subtract(const Duration(seconds: 5))
                .toIso8601String(),
          }),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('allows a fresh result after dispatch', () {
      expect(
        policy.buildStaleGuardResult(
          _toolCall(),
          _result({
            ..._validPayload(dispatchedAt),
            'started_at': dispatchedAt
                .add(const Duration(milliseconds: 1))
                .toIso8601String(),
          }),
          dispatchedAt: dispatchedAt,
        ),
        isNull,
      );
    });

    test('builds the compatible stale-result diagnostic', () {
      final startedAt = dispatchedAt.subtract(
        const Duration(seconds: 5, microseconds: 1),
      );
      final guardResult = policy.buildStaleGuardResult(
        _toolCall(name: ' PROCESS_START '),
        _result({
          'ok': true,
          'status': 'running',
          'job_id': 'proc_old_1',
          'command': 'bash tool/release_ios_macos.sh',
          'working_directory': '/tmp/project',
          'started_at': ' ${startedAt.toIso8601String()} ',
        }),
        dispatchedAt: dispatchedAt,
      );

      expect(guardResult, isNotNull);
      expect(guardResult!.toolName, ' PROCESS_START ');
      expect(guardResult.isSuccess, isFalse);
      expect(guardResult.isExternalMcpResult, isFalse);
      expect(
        guardResult.errorMessage,
        'process_start returned a stale job result.',
      );
      expect(jsonDecode(guardResult.result), {
        'ok': false,
        'code': 'background_process_start_stale_result',
        'error':
            'process_start returned a non-duplicate job result whose started_at '
            'predates this tool call. Treat the start result as stale until the '
            'process state is verified.',
        'job_id': 'proc_old_1',
        'command': 'bash tool/release_ios_macos.sh',
        'working_directory': '/tmp/project',
        'started_at': startedAt.toIso8601String(),
        'tool_dispatched_at': dispatchedAt.toIso8601String(),
        'required_action':
            'Use process_status, process_tail, or process_wait for the job_id '
            'if it should still be monitored. Do not report the command as '
            'newly started from this result.',
      });
    });
  });
}

ToolCallInfo _toolCall({String name = 'process_start'}) {
  return ToolCallInfo(id: 'process-start-1', name: name, arguments: const {});
}

McpToolResult _result(Map<String, dynamic> payload, {bool isSuccess = true}) {
  return _rawResult(jsonEncode(payload), isSuccess: isSuccess);
}

McpToolResult _rawResult(String result, {bool isSuccess = true}) {
  return McpToolResult(
    toolName: 'process_start',
    result: result,
    isSuccess: isSuccess,
    errorMessage: isSuccess ? null : 'dispatch failed',
    isExternalMcpResult: true,
  );
}

Map<String, dynamic> _validPayload(DateTime dispatchedAt) {
  return {
    'ok': true,
    'started_at': dispatchedAt
        .subtract(const Duration(seconds: 6))
        .toIso8601String(),
  };
}
