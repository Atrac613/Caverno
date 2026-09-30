import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';

typedef ToolCallPredicate = bool Function(ToolCallInfo toolCall);
typedef ToolCallPathExtractor = String? Function(Object? arguments);
typedef ToolCallKeyBuilder =
    String Function(ToolCallInfo toolCall, int commandRetryGeneration);
typedef ToolResultKeyBuilder = String Function(ToolResultInfo toolResult);

class ToolLoopRecoveryPolicy {
  const ToolLoopRecoveryPolicy();

  bool toolResultsContainFailedCommandValidation(
    List<ToolResultInfo> toolResults,
  ) => toolResults.any((toolResult) {
    final normalizedName = toolResult.name.trim().toLowerCase();
    if (normalizedName != 'local_execute_command' &&
        normalizedName != 'process_start' &&
        normalizedName != 'process_status' &&
        normalizedName != 'process_wait' &&
        normalizedName != 'run_tests' &&
        normalizedName != 'git_execute_command' &&
        normalizedName != 'ssh_execute_command') {
      return false;
    }
    final normalizedResult = toolResult.result.toLowerCase();
    return RegExp(
          r'"exit_code"\s*:\s*(?!0\b)-?\d+',
        ).hasMatch(normalizedResult) ||
        RegExp(r'exit_code:\s*(?!0\b)-?\d+').hasMatch(normalizedResult);
  });

  bool toolResultsMentionExactNonZeroExitCodeExpectation(
    List<ToolResultInfo> toolResults,
  ) => toolResults.any((toolResult) {
    final normalized = toolResult.result.toLowerCase();
    return normalized.contains('expected exit code') ||
        RegExp(r'returned\s+-?\d+,\s*expected\s+-?\d+').hasMatch(normalized);
  });

  bool containsOnlyReadOnlyInspectionToolCalls(
    List<ToolCallInfo> toolCalls, {
    required ToolCallPredicate isReadOnlyInspectionToolCall,
  }) {
    if (toolCalls.isEmpty) {
      return false;
    }
    return toolCalls.every(isReadOnlyInspectionToolCall);
  }

  bool hasUnseenReadOnlyInspectionToolCalls(
    List<ToolCallInfo> toolCalls,
    Set<String> executedToolCallKeys, {
    required int commandRetryGeneration,
    required ToolCallPredicate isReadOnlyInspectionToolCall,
    required ToolCallKeyBuilder toolCallKey,
  }) {
    if (!containsOnlyReadOnlyInspectionToolCalls(
      toolCalls,
      isReadOnlyInspectionToolCall: isReadOnlyInspectionToolCall,
    )) {
      return false;
    }
    return toolCalls.any((toolCall) {
      return !executedToolCallKeys.contains(
        toolCallKey(toolCall, commandRetryGeneration),
      );
    });
  }

  bool shouldRequestExhaustionRecovery({
    required List<ToolCallInfo> pendingToolCalls,
    required List<ToolResultInfo> currentToolResults,
    required ToolCallPredicate isWriteGitCommandToolCall,
  }) {
    if (pendingToolCalls.isEmpty || currentToolResults.isEmpty) {
      return false;
    }
    return !pendingToolCalls.any(isWriteGitCommandToolCall);
  }

  List<ToolResultInfo> buildUnexecutedPendingToolResults({
    required List<ToolCallInfo> toolCalls,
    required Set<String> executedToolCallKeys,
    required int commandRetryGeneration,
    required ToolCallKeyBuilder toolCallKey,
  }) {
    if (toolCalls.isEmpty) {
      return const [];
    }

    final pending = <ToolResultInfo>[];
    for (final toolCall in toolCalls) {
      if (executedToolCallKeys.contains(
        toolCallKey(toolCall, commandRetryGeneration),
      )) {
        continue;
      }
      pending.add(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: jsonEncode({
            'code': 'tool_call_not_executed',
            ...ToolResultOrigin.harness.marker,
            'error':
                'Tool call was requested after the bounded tool loop stopped and was not executed before the final answer.',
            'reason': 'bounded_tool_loop_exhausted',
            'tool_name': toolCall.name,
          }),
        ),
      );
    }
    return pending;
  }

  String buildExhaustionRecoveryPrompt(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
    bool readOnlyReview = false,
  }) {
    final pendingToolNames = toolCalls
        .map((toolCall) => toolCall.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(', ');
    // A review has no saved task to finish and nothing to edit, so none of the
    // lines below apply; session e3a9f3f0 received them anyway.
    if (readOnlyReview) {
      return [
        'You hit the bounded tool loop limit during a read-only review.',
        if (pendingToolNames.isNotEmpty)
          'Pending tool calls at the limit: $pendingToolNames.',
        'Do not edit files or change Git state.',
        'Write the review now from the latest tool results, and name anything you could not inspect as a verification limit.',
      ].join('\n');
    }
    final hasEditMismatch = toolResultsContainEditMismatch(previousToolResults);
    final hasMatchingReadContext = previousToolResults.any(
      (toolResult) => toolResult.name == 'read_file',
    );
    return [
      'You hit the bounded tool loop limit while working on the current saved task.',
      if (pendingToolNames.isNotEmpty)
        'Pending tool calls at the limit: $pendingToolNames.',
      'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.',
      'Use the latest tool results and finish the current saved task now.',
      if (hasEditMismatch)
        'A recent edit_file failed because old_text did not match the current file.',
      if (hasEditMismatch && hasMatchingReadContext)
        'A recent read_file result for the same path is already provided below. Use that exact file content and return only one edit_file call for the same file, or a brief blocker statement if the edit is unsafe.',
      if (hasEditMismatch && hasMatchingReadContext)
        'Do not call read_file again for the same path in this turn.',
      if (hasEditMismatch && !hasMatchingReadContext)
        'If the latest tool result reports code=edit_mismatch, read that exact file once and then retry edit_file with the exact current file content as old_text.',
      'If one final tool call is still required, return only the single most important tool call for the current saved task.',
      'Otherwise reply with a brief completion or blocker statement for the current saved task.',
    ].join('\n');
  }

  List<ToolResultInfo> buildRecoveryToolResults({
    required List<ToolResultInfo> currentToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolCallInfo> pendingToolCalls,
    required ToolCallPathExtractor pathFromArguments,
    required ToolResultKeyBuilder toolResultKey,
  }) {
    final recoveryToolResults = <ToolResultInfo>[];
    if (toolResultsContainEditMismatch(currentToolResults)) {
      final pendingPaths = pendingToolCalls
          .map((toolCall) => pathFromArguments(toolCall.arguments))
          .whereType<String>()
          .toSet();
      if (pendingPaths.isNotEmpty) {
        final seenPaths = <String>{};
        for (final toolResult in executedToolResults.reversed) {
          if (toolResult.name != 'read_file') {
            continue;
          }
          final toolPath = pathFromArguments(toolResult.arguments);
          if (toolPath == null ||
              !pendingPaths.contains(toolPath) ||
              !seenPaths.add(toolPath)) {
            continue;
          }
          recoveryToolResults.insert(0, toolResult);
        }
      }
    }
    recoveryToolResults.addAll(currentToolResults);
    return dedupeRecoveryToolResults(
      recoveryToolResults,
      toolResultKey: toolResultKey,
    );
  }

  List<ToolResultInfo> dedupeRecoveryToolResults(
    List<ToolResultInfo> toolResults, {
    required ToolResultKeyBuilder toolResultKey,
  }) {
    final deduped = <ToolResultInfo>[];
    final seenKeys = <String>{};
    for (final toolResult in toolResults) {
      final key = '${toolResultKey(toolResult)}:${toolResult.result}';
      if (seenKeys.add(key)) {
        deduped.add(toolResult);
      }
    }
    return deduped;
  }

  bool toolResultsContainEditMismatch(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      final normalized = toolResult.result.toLowerCase();
      return normalized.contains('"code":"edit_mismatch"') ||
          normalized.contains('old_text was not found in the target file');
    });
  }
}
