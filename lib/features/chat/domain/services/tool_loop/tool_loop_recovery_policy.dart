import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:path/path.dart' as path;

import '../../../data/datasources/filesystem_path_resolver.dart';
import '../../entities/tool_call_info.dart';
import '../files/file_mutation_evidence_policy.dart';
import '../verification/reconciled_command_failure.dart';
import 'tool_call_execution_policy.dart';

typedef ToolCallPredicate = bool Function(ToolCallInfo toolCall);
typedef ToolCallPathExtractor = String? Function(Object? arguments);
typedef ToolCallKeyBuilder =
    String Function(ToolCallInfo toolCall, int commandRetryGeneration);
typedef ToolResultKeyBuilder = String Function(ToolResultInfo toolResult);

class ToolLoopRecoveryPolicy {
  const ToolLoopRecoveryPolicy();
  static const _mutationPolicy = FileMutationEvidencePolicy();
  static const _executionPolicy = ToolCallExecutionPolicy();

  bool toolResultsContainFailedCommandValidation(
    List<ToolResultInfo> toolResults,
  ) => ReconciledCommandFailure.any(toolResults);

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
    return !pendingToolCalls.any(
      (call) =>
          isWriteGitCommandToolCall(call) ||
          call.name.trim().toLowerCase() == 'read_file' ||
          _executionPolicy.isCommandExecutionTool(call.name),
    );
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
    String? projectRoot,
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
    final failedPaths = previousToolResults
        .where((result) => toolResultsContainEditMismatch([result]))
        .map((result) => _mutationPolicy.argumentPath(result.arguments))
        .whereType<String>()
        .map((value) => _normalizePath(value, projectRoot))
        .toSet();
    final freshReads = _freshReads(
      previousToolResults,
      failedPaths,
      _mutationPolicy.argumentPath,
      projectRoot,
    );
    final hasMatchingReadContext =
        failedPaths.isNotEmpty && freshReads.length == failedPaths.length;
    return [
      'You hit the bounded tool loop limit while working on the current saved task.',
      if (pendingToolNames.isNotEmpty)
        'Pending tool calls at the limit: $pendingToolNames.',
      'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.',
      'Use the latest tool results and finish the current saved task now.',
      if (hasEditMismatch)
        'A recent edit_file failed because old_text did not match the current file.',
      if (hasEditMismatch && hasMatchingReadContext)
        'A current read_file result for each failed edit path is provided below. Copy old_text from the inspected range, not from an older snapshot or the desired replacement.',
      if (hasEditMismatch && hasMatchingReadContext)
        'If the required anchor is outside the inspected range, read that missing range with offset and limit before editing.',
      if (hasEditMismatch && !hasMatchingReadContext)
        'No current read has been established for every failed edit path. Read the affected file or exact missing range before retrying; earlier snapshots may predate a successful edit.',
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
    String? projectRoot,
  }) {
    final recoveryToolResults = <ToolResultInfo>[];
    if (toolResultsContainEditMismatch(currentToolResults)) {
      final pendingPaths = pendingToolCalls
          .map((toolCall) => pathFromArguments(toolCall.arguments))
          .whereType<String>()
          .map((value) => _normalizePath(value, projectRoot))
          .toSet();
      if (pendingPaths.isNotEmpty) {
        recoveryToolResults.addAll(
          _freshReads(
            executedToolResults,
            pendingPaths,
            pathFromArguments,
            projectRoot,
          ).map(
            (result) => ToolResultInfo(
              id: result.id,
              name: result.name,
              arguments: result.arguments,
              result: result.result,
              outcome: result.outcome,
              fromEarlierLoop: true,
              changesSinceCapture: result.changesSinceCapture,
            ),
          ),
        );
      }
    }
    recoveryToolResults.addAll(currentToolResults);
    return dedupeRecoveryToolResults(
      recoveryToolResults,
      toolResultKey: toolResultKey,
    );
  }

  List<ToolResultInfo> _freshReads(
    List<ToolResultInfo> results,
    Set<String> requestedPaths,
    ToolCallPathExtractor pathFromArguments,
    String? projectRoot,
  ) {
    final seenPaths = <String>{};
    final invalidatedPaths = <String>{};
    final reads = <ToolResultInfo>[];
    for (final result in results.reversed) {
      final payload = _executionPolicy.tryDecodeMap(result.result);
      if (ToolResultOrigin.fromPayload(payload) != null) continue;
      final call = ToolCallInfo(
        id: result.id,
        name: result.name,
        arguments: result.arguments,
      );
      if (_mutationPolicy.isMutationToolName(result.name)) {
        if (toolResultsContainEditMismatch([result]) ||
            !_mutationPolicy.isSuccessfulResult(result) ||
            result.outcome?.effectiveFileChanged == false ||
            payload?['changed'] == false) {
          continue;
        }
        final rawPaths = <String>[
          if (pathFromArguments(result.arguments) case final String value)
            value,
          for (final mutation in result.outcome?.fileMutations ?? const [])
            if (mutation.changed != false) mutation.path,
        ];
        if (rawPaths.isEmpty) break;
        invalidatedPaths.addAll(
          rawPaths.map((value) => _normalizePath(value, projectRoot)),
        );
        continue;
      }
      if (_executionPolicy.isCommandExecutionTool(result.name) &&
          !_executionPolicy.isReadOnlyCommandExecutionToolCall(call) &&
          !_executionPolicy.isRepeatableBackgroundProcessInspectionTool(call)) {
        // A command can change files without declaring their paths.
        break;
      }
      if (result.name != 'read_file') continue;
      final rawPath = pathFromArguments(result.arguments);
      if (rawPath == null) continue;
      final readPath = _normalizePath(rawPath, projectRoot);
      final observedPath = payload?['path'];
      if (!requestedPaths.contains(readPath) ||
          !seenPaths.add(readPath) ||
          invalidatedPaths.contains(readPath) ||
          (observedPath is String &&
              invalidatedPaths.contains(
                _normalizePath(observedPath, projectRoot),
              )) ||
          result.changesSinceCapture.isNotEmpty ||
          payload?['error'] != null ||
          (payload != null && payload['content'] is! String) ||
          result.result.trim().isEmpty ||
          result.result.trimLeft().startsWith('Error:')) {
        continue;
      }
      reads.insert(0, result);
    }
    return reads;
  }

  String _normalizePath(String value, String? projectRoot) => path.normalize(
    FilesystemPathResolver.resolve(value, defaultRoot: projectRoot) ?? value,
  );

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
