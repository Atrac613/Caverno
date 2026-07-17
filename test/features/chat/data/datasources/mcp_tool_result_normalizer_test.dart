import 'package:caverno/features/chat/data/datasources/mcp_tool_result_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpToolResultNormalizer', () {
    test('constructs direct results without losing provenance or payloads', () {
      final success = McpToolResultNormalizer.success(
        toolName: 'remote_read',
        result: 'unchanged success payload',
        isExternalMcpResult: true,
      );
      final failure = McpToolResultNormalizer.failure(
        toolName: 'remote_write',
        result: 'unchanged failure payload',
        errorMessage: 'exact failure',
        isExternalMcpResult: true,
      );

      expect(success.toolName, 'remote_read');
      expect(success.result, 'unchanged success payload');
      expect(success.isSuccess, isTrue);
      expect(success.errorMessage, isNull);
      expect(success.isExternalMcpResult, isTrue);

      expect(failure.toolName, 'remote_write');
      expect(failure.result, 'unchanged failure payload');
      expect(failure.isSuccess, isFalse);
      expect(failure.errorMessage, 'exact failure');
      expect(failure.isExternalMcpResult, isTrue);
    });

    test('encodes structured failures in caller-provided key order', () {
      final result = McpToolResultNormalizer.structuredFailure(
        toolName: 'run_tests',
        payload: const {
          'error': 'Approval is required.',
          'code': 'approval_required',
        },
        errorMessage: 'Approval is required',
      );

      expect(
        result.result,
        '{"error":"Approval is required.","code":"approval_required"}',
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Approval is required');
    });

    test('preserves legacy ok-payload outcome interpretation', () {
      for (final payload in const [
        'not json',
        '[]',
        '{"ok":true,"error":"ignored"}',
        '{"ok":"false","error":"ignored"}',
      ]) {
        final result = McpToolResultNormalizer.fromOkPayload(
          toolName: 'browser_click',
          result: payload,
          fallbackErrorMessage: 'Browser tool failed',
        );

        expect(result.result, payload);
        expect(result.isSuccess, isTrue, reason: payload);
        expect(result.errorMessage, isNull, reason: payload);
      }

      final explicitError = McpToolResultNormalizer.fromOkPayload(
        toolName: 'browser_click',
        result: '{"ok":false,"error":"Target is missing"}',
        fallbackErrorMessage: 'Browser tool failed',
      );
      final fallbackError = McpToolResultNormalizer.fromOkPayload(
        toolName: 'browser_click',
        result: '{"ok":false}',
        fallbackErrorMessage: 'Browser tool failed',
      );
      final emptyError = McpToolResultNormalizer.fromOkPayload(
        toolName: 'browser_click',
        result: '{"ok":false,"error":""}',
        fallbackErrorMessage: 'Browser tool failed',
        isExternalMcpResult: true,
      );

      expect(explicitError.isSuccess, isFalse);
      expect(explicitError.errorMessage, 'Target is missing');
      expect(fallbackError.isSuccess, isFalse);
      expect(fallbackError.errorMessage, 'Browser tool failed');
      expect(emptyError.isSuccess, isFalse);
      expect(emptyError.errorMessage, isEmpty);
      expect(emptyError.isExternalMcpResult, isTrue);
    });

    test('normalizes command failures without rewriting result payloads', () {
      const cases = <({String payload, String expected})>[
        (
          payload:
              '{"error":"  explicit command error  ","exit_code":7,"stderr":"ignored"}',
          expected: 'explicit command error',
        ),
        (
          payload: '{"exit_code":2,"stderr":"  stderr detail  "}',
          expected: 'Git command exited with code 2: stderr detail',
        ),
        (
          payload: '{"exit_code":3,"stderr":"  ","stdout":"  stdout detail  "}',
          expected: 'Git command exited with code 3: stdout detail',
        ),
        (
          payload: '{"exit_code":4}',
          expected: 'Git command exited with code 4',
        ),
      ];

      for (final testCase in cases) {
        final result = McpToolResultNormalizer.fromCommandPayload(
          toolName: 'git_execute_command',
          result: testCase.payload,
          toolLabel: 'Git command',
        );

        expect(result.result, testCase.payload);
        expect(result.isSuccess, isFalse, reason: testCase.payload);
        expect(result.errorMessage, testCase.expected);
      }
    });

    test('keeps non-failing command payloads successful', () {
      for (final payload in const [
        'not json',
        '[]',
        '{}',
        '{"exit_code":0,"stderr":"ignored"}',
        '{"error":"  ","exit_code":0}',
      ]) {
        final result = McpToolResultNormalizer.fromCommandPayload(
          toolName: 'git_execute_command',
          result: payload,
          toolLabel: 'Git command',
          isExternalMcpResult: true,
        );

        expect(result.result, payload);
        expect(result.isSuccess, isTrue, reason: payload);
        expect(result.errorMessage, isNull, reason: payload);
        expect(result.isExternalMcpResult, isTrue, reason: payload);
      }
    });
  });
}
