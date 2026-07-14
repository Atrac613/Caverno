import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_failure_classifier.dart';

void main() {
  const classifier = ToolFailureClassifier();

  test('classifies structured non-zero command diagnostics as actionable', () {
    final result = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': 'Acceptance criteria failed.',
      'diagnostics': [
        {'code': 'todo_cli_entrypoint'},
      ],
    });

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.actionableCommandFailure,
    );
    expect(
      classifier.lifecycleResultStatus(_commandCall(), result),
      'command_failure',
    );
  });

  test('classifies command output without diagnostics as actionable', () {
    final result = _failure({
      'exit_code': 2,
      'stdout': 'Expected value was missing.',
      'stderr': '',
    });

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.actionableCommandFailure,
    );
  });

  test('keeps approval denial on the operational failure path', () {
    final result = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
    }, errorMessage: 'Auto-review denied this command.');

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.approvalDenied,
    );
    expect(classifier.isApprovalDenial(result), isTrue);
  });

  test('keeps timeout and explicit execution errors operational', () {
    final timeout = _failure({
      'exit_code': 124,
      'stdout': '',
      'stderr': '',
      'timed_out': true,
    });
    final startError = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
      'error': 'Process failed to start.',
    });
    final structuredError = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
      'error': {'code': 'spawn_failed'},
    });

    expect(
      classifier.classify(_commandCall(), timeout),
      ToolResultDisposition.executionFailure,
    );
    expect(
      classifier.classify(_commandCall(), startError),
      ToolResultDisposition.executionFailure,
    );
    expect(
      classifier.classify(_commandCall(), structuredError),
      ToolResultDisposition.executionFailure,
    );
  });

  test('keeps malformed and non-command failures operational', () {
    const malformed = McpToolResult(
      toolName: 'local_execute_command',
      result: 'exit code 1',
      isSuccess: false,
      errorMessage: 'Command failed.',
    );
    final nonCommand = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': 'Read failed.',
    }, toolName: 'read_file');

    expect(
      classifier.classify(_commandCall(), malformed),
      ToolResultDisposition.executionFailure,
    );
    expect(
      classifier.classify(
        ToolCallInfo(
          id: 'read-1',
          name: 'read_file',
          arguments: {'path': 'README.md'},
        ),
        nonCommand,
      ),
      ToolResultDisposition.executionFailure,
    );
  });

  test('classifies successful results before inspecting payloads', () {
    const result = McpToolResult(
      toolName: 'local_execute_command',
      result: '{"exit_code":1,"stderr":"ignored"}',
      isSuccess: true,
    );

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.success,
    );
  });
}

ToolCallInfo _commandCall() {
  return ToolCallInfo(
    id: 'command-1',
    name: 'local_execute_command',
    arguments: {'command': 'dart test'},
  );
}

McpToolResult _failure(
  Map<String, dynamic> payload, {
  String toolName = 'local_execute_command',
  String errorMessage = 'Command exited non-zero.',
}) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode(payload),
    isSuccess: false,
    errorMessage: errorMessage,
  );
}
