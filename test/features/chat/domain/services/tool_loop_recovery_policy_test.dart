import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_recovery_policy.dart';

void main() {
  const policy = ToolLoopRecoveryPolicy();

  String keyFor(ToolCallInfo toolCall, int generation) {
    return '${toolCall.name}:$generation:${jsonEncode(toolCall.arguments)}';
  }

  String? pathFromArguments(Object? arguments) {
    if (arguments is Map) {
      final rawPath = arguments['path'];
      if (rawPath is String && rawPath.trim().isNotEmpty) {
        return rawPath.trim();
      }
    }
    return null;
  }

  String resultKey(ToolResultInfo result) {
    return '${result.name}:${jsonEncode(result.arguments)}';
  }

  test('detects unseen read-only inspection calls at the loop limit', () {
    final readCall = ToolCallInfo(
      id: 'read-1',
      name: 'read_file',
      arguments: const {'path': 'lib/main.dart'},
    );
    final writeCall = ToolCallInfo(
      id: 'write-1',
      name: 'write_file',
      arguments: const {'path': 'lib/main.dart'},
    );

    expect(
      policy.hasUnseenReadOnlyInspectionToolCalls(
        [readCall],
        <String>{},
        commandRetryGeneration: 0,
        isReadOnlyInspectionToolCall: (toolCall) =>
            toolCall.name == 'read_file',
        toolCallKey: keyFor,
      ),
      isTrue,
    );
    expect(
      policy.hasUnseenReadOnlyInspectionToolCalls(
        [readCall],
        {keyFor(readCall, 0)},
        commandRetryGeneration: 0,
        isReadOnlyInspectionToolCall: (toolCall) =>
            toolCall.name == 'read_file',
        toolCallKey: keyFor,
      ),
      isFalse,
    );
    expect(
      policy.hasUnseenReadOnlyInspectionToolCalls(
        [writeCall],
        <String>{},
        commandRetryGeneration: 0,
        isReadOnlyInspectionToolCall: (toolCall) =>
            toolCall.name == 'read_file',
        toolCallKey: keyFor,
      ),
      isFalse,
    );
  });

  test('blocks exhaustion recovery for pending write git commands', () {
    final writeGitCall = ToolCallInfo(
      id: 'git-1',
      name: 'git_execute_command',
      arguments: const {'command': 'commit -m "ship"'},
    );
    final currentResult = ToolResultInfo(
      id: 'read-1',
      name: 'read_file',
      arguments: const {'path': 'lib/main.dart'},
      result: 'content',
    );

    expect(
      policy.shouldRequestExhaustionRecovery(
        pendingToolCalls: [writeGitCall],
        currentToolResults: [currentResult],
        isWriteGitCommandToolCall: (toolCall) =>
            toolCall.name == 'git_execute_command',
      ),
      isFalse,
    );
    expect(
      policy.shouldRequestExhaustionRecovery(
        pendingToolCalls: [
          ToolCallInfo(
            id: 'read-2',
            name: 'read_file',
            arguments: const {'path': 'lib/main.dart'},
          ),
        ],
        currentToolResults: [currentResult],
        isWriteGitCommandToolCall: (toolCall) =>
            toolCall.name == 'git_execute_command',
      ),
      isTrue,
    );
  });

  test('adds matching read context before edit mismatch recovery results', () {
    final previousRead = ToolResultInfo(
      id: 'read-1',
      name: 'read_file',
      arguments: const {'path': 'lib/main.dart'},
      result: 'current file body',
    );
    final unrelatedRead = ToolResultInfo(
      id: 'read-2',
      name: 'read_file',
      arguments: const {'path': 'lib/other.dart'},
      result: 'other body',
    );
    final editMismatch = ToolResultInfo(
      id: 'edit-1',
      name: 'edit_file',
      arguments: const {'path': 'lib/main.dart'},
      result: '{"code":"edit_mismatch"}',
    );

    final results = policy.buildRecoveryToolResults(
      currentToolResults: [editMismatch],
      executedToolResults: [unrelatedRead, previousRead],
      pendingToolCalls: [
        ToolCallInfo(
          id: 'edit-2',
          name: 'edit_file',
          arguments: const {'path': 'lib/main.dart'},
        ),
      ],
      pathFromArguments: pathFromArguments,
      toolResultKey: resultKey,
    );

    expect(results.map((result) => result.id), ['read-1', 'edit-1']);
  });

  test('builds edit mismatch recovery guidance from prior results', () {
    final prompt = policy.buildExhaustionRecoveryPrompt(
      [
        ToolCallInfo(
          id: 'edit-1',
          name: 'edit_file',
          arguments: const {'path': 'lib/main.dart'},
        ),
      ],
      previousToolResults: [
        ToolResultInfo(
          id: 'read-1',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'current body',
        ),
        ToolResultInfo(
          id: 'edit-1',
          name: 'edit_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'old_text was not found in the target file',
        ),
      ],
    );

    expect(prompt, contains('Pending tool calls at the limit: edit_file.'));
    expect(prompt, contains('old_text did not match the current file'));
    expect(prompt, contains('Do not call read_file again'));
  });

  test('records only unseen pending tool calls as unexecuted', () {
    final seenCall = ToolCallInfo(
      id: 'read-1',
      name: 'read_file',
      arguments: const {'path': 'lib/main.dart'},
    );
    final unseenCall = ToolCallInfo(
      id: 'read-2',
      name: 'read_file',
      arguments: const {'path': 'lib/next.dart'},
    );

    final results = policy.buildUnexecutedPendingToolResults(
      toolCalls: [seenCall, unseenCall],
      executedToolCallKeys: {keyFor(seenCall, 0)},
      commandRetryGeneration: 0,
      toolCallKey: keyFor,
    );

    expect(results, hasLength(1));
    expect(results.single.id, 'read-2');
    expect(jsonDecode(results.single.result), {
      'code': 'tool_call_not_executed',
      'error':
          'Tool call was requested after the bounded tool loop stopped and was not executed before the final answer.',
      'reason': 'bounded_tool_loop_exhausted',
      'tool_name': 'read_file',
    });
  });
}
