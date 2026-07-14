import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_call_batch_executor.dart';
import 'package:caverno/features/chat/domain/services/tool_call_execution_policy.dart';

void main() {
  const executor = ToolCallBatchExecutor();
  const policy = ToolCallExecutionPolicy();

  group('ToolCallBatchExecutor', () {
    test('executes fresh tool calls and records successful keys', () async {
      final executedKeys = <String>{};
      final failures = <String, int>{};
      final calls = [
        _toolCall('read_file', {'path': 'README.md'}),
      ];

      final result = await executor.execute(
        toolCalls: calls,
        dispatchToolCall: (toolCall) async => _success(toolCall, 'contents'),
        executedToolCallKeys: executedKeys,
        toolFailureCounts: failures,
      );

      expect(result.abortLoop, isFalse);
      expect(result.toolResults.single.result, 'contents');
      expect(executedKeys, contains(policy.toolExecutionKey(calls.single)));
      expect(failures, isEmpty);
    });

    test('skips duplicate tool calls before dispatch', () async {
      final call = _toolCall('read_file', {'path': 'README.md'});
      final executedKeys = {policy.toolExecutionKey(call)};
      var dispatchCount = 0;

      final result = await executor.execute(
        toolCalls: [call],
        dispatchToolCall: (toolCall) async {
          dispatchCount += 1;
          return _success(toolCall, 'contents');
        },
        executedToolCallKeys: executedKeys,
        toolFailureCounts: <String, int>{},
      );

      expect(result.toolResults, isEmpty);
      expect(dispatchCount, 0);
    });

    test('uses error text when a failed tool result has no payload', () async {
      final call = _toolCall('external_tool');

      final result = await executor.execute(
        toolCalls: [call],
        dispatchToolCall: (_) async => McpToolResult(
          toolName: call.name,
          result: '',
          isSuccess: false,
          errorMessage: 'No server',
        ),
        executedToolCallKeys: <String>{},
        toolFailureCounts: <String, int>{},
      );

      expect(result.abortLoop, isFalse);
      expect(result.toolResults.single.result, 'Error: No server');
    });

    test('aborts after the same tool call fails twice', () async {
      final call = _toolCall('external_tool');
      final key = policy.toolExecutionKey(call);
      final failures = {key: 1};
      final secondCall = _toolCall('read_file', {'path': 'README.md'});
      var dispatchCount = 0;

      final result = await executor.execute(
        toolCalls: [call, secondCall],
        dispatchToolCall: (toolCall) async {
          dispatchCount += 1;
          return McpToolResult(
            toolName: toolCall.name,
            result: 'failure',
            isSuccess: false,
            errorMessage: 'failed',
          );
        },
        executedToolCallKeys: <String>{},
        toolFailureCounts: failures,
      );

      expect(result.abortLoop, isTrue);
      expect(result.toolResults.single.name, 'external_tool');
      expect(dispatchCount, 1);
      expect(failures[key], 2);
    });

    test('aborts a denied command retried under a reworded reason', () async {
      // Regression: a model that re-issues the same denied command while
      // rewording `reason` must still trip the consecutive-failure abort.
      // Previously each re-narration minted a fresh key, so the count never
      // reached 2 and the loop re-issued the denied command indefinitely.
      final firstAttempt = _toolCall('local_execute_command', {
        'command': 'python3 hello.py',
        'reason': 'output hello world',
      });
      final secondAttempt = _toolCall('local_execute_command', {
        'command': 'python3 hello.py',
        'reason': 'run hello.py to print Hello World',
      });
      final failures = <String, int>{};

      final result = await executor.execute(
        toolCalls: [firstAttempt, secondAttempt],
        dispatchToolCall: (toolCall) async => McpToolResult(
          toolName: toolCall.name,
          result: 'Auto-review denied this action.',
          isSuccess: false,
          errorMessage: 'Auto-review denied: not authorized',
        ),
        executedToolCallKeys: <String>{},
        toolFailureCounts: failures,
      );

      expect(result.abortLoop, isTrue);
      expect(failures[policy.toolFailureKey(firstAttempt)], 2);
    });

    test(
      'keeps repeated structured command failures as repair feedback',
      () async {
        final call = _toolCall('local_execute_command', {
          'command': 'dart run tool/verify.dart',
        });
        final failures = <String, int>{};
        var dispatchCount = 0;

        final result = await executor.execute(
          toolCalls: [
            call,
            ToolCallInfo(
              id: 'tool-command-retry',
              name: call.name,
              arguments: call.arguments,
            ),
          ],
          dispatchToolCall: (toolCall) async {
            dispatchCount += 1;
            return McpToolResult(
              toolName: toolCall.name,
              result:
                  '{"exit_code":1,"stdout":"","stderr":"Tests failed.","diagnostics":[{"code":"test_failure"}]}',
              isSuccess: false,
              errorMessage: 'Verifier found one issue.',
            );
          },
          executedToolCallKeys: <String>{},
          toolFailureCounts: failures,
        );

        expect(result.abortLoop, isFalse);
        expect(result.toolResults, hasLength(2));
        expect(dispatchCount, 2);
        expect(failures, isEmpty);
      },
    );
  });
}

ToolCallInfo _toolCall(
  String name, [
  Map<String, dynamic> arguments = const {},
]) {
  return ToolCallInfo(id: 'tool-$name', name: name, arguments: arguments);
}

McpToolResult _success(ToolCallInfo toolCall, String result) {
  return McpToolResult(
    toolName: toolCall.name,
    result: result,
    isSuccess: true,
  );
}
