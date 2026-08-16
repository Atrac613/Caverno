import '../../data/datasources/filesystem_path_resolver.dart';
import '../entities/tool_call_info.dart';
import 'duplicate_tool_result_reuse_payload.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: duplicate-tool-result-recovery

/// Captures immutable tool-call snapshots for duplicate recovery.
final class DuplicateToolResultRecoveryInput {
  DuplicateToolResultRecoveryInput({
    required List<ToolCallInfo> currentToolCalls,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> fallbackToolResults,
    required this.projectRoot,
  }) : currentToolCalls = List<ToolCallInfo>.unmodifiable(
         currentToolCalls.map(_freezeToolCall),
       ),
       executedToolResults = List<ToolResultInfo>.unmodifiable(
         executedToolResults.map(_freezeToolResult),
       ),
       fallbackToolResults = List<ToolResultInfo>.unmodifiable(
         fallbackToolResults.map(_freezeToolResult),
       );

  final List<ToolCallInfo> currentToolCalls;
  final List<ToolResultInfo> executedToolResults;
  final List<ToolResultInfo> fallbackToolResults;
  final String? projectRoot;

  static ToolCallInfo _freezeToolCall(ToolCallInfo call) => ToolCallInfo(
    id: call.id,
    name: call.name,
    arguments: _freezeArguments(call.arguments),
  );

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) =>
      ToolResultInfo(
        id: result.id,
        name: result.name,
        arguments: _freezeArguments(result.arguments),
        result: result.result,
        outcome: result.outcome,
      );

  static Map<String, dynamic> _freezeArguments(
    Map<String, dynamic> arguments,
  ) => Map<String, dynamic>.unmodifiable({
    for (final entry in arguments.entries) entry.key: _freezeValue(entry.value),
  });

  static Object? _freezeValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return _freezeArguments(value);
    }
    if (value is Map) {
      return Map<Object?, Object?>.unmodifiable({
        for (final entry in value.entries) entry.key: _freezeValue(entry.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_freezeValue));
    }
    if (value is Set) {
      return Set<Object?>.unmodifiable(value.map(_freezeValue));
    }
    return value;
  }
}

final class DuplicateToolResultRecovery {
  const DuplicateToolResultRecovery();
  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _reusePayload = DuplicateToolResultReusePayload();

  List<ToolResultInfo> recover(DuplicateToolResultRecoveryInput input) {
    final resolveProjectPath = _projectPathResolver(input.projectRoot);
    final recoveryToolResults = <ToolResultInfo>[];
    for (final toolCall in input.currentToolCalls) {
      final matchingResult = _latestMatchingResult(
        toolCall: toolCall,
        executedToolResults: input.executedToolResults,
        resolveProjectPath: resolveProjectPath,
      );
      if (matchingResult == null) {
        continue;
      }
      recoveryToolResults.add(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: _reusePayload.build(
            matchingResult,
            currentToolCallId: toolCall.id,
          ),
          outcome: matchingResult.outcome,
        ),
      );
    }

    for (final fallbackResult in input.fallbackToolResults) {
      final matchesCurrentCall = input.currentToolCalls.any(
        (toolCall) =>
            _executionKeyForResult(
              fallbackResult,
              resolveProjectPath: resolveProjectPath,
            ) ==
            _executionPolicy.toolExecutionKey(
              toolCall,
              resolveProjectPath: resolveProjectPath,
            ),
      );
      if (!matchesCurrentCall) {
        recoveryToolResults.add(fallbackResult);
      }
    }

    return _dedupe(recoveryToolResults, resolveProjectPath: resolveProjectPath);
  }

  ToolResultInfo? _latestMatchingResult({
    required ToolCallInfo toolCall,
    required List<ToolResultInfo> executedToolResults,
    required ProjectPathResolver resolveProjectPath,
  }) {
    final currentKey = _executionPolicy.toolExecutionKey(
      toolCall,
      resolveProjectPath: resolveProjectPath,
    );
    for (final toolResult in executedToolResults.reversed) {
      if (_executionKeyForResult(
            toolResult,
            resolveProjectPath: resolveProjectPath,
          ) ==
          currentKey) {
        return toolResult;
      }
    }
    return null;
  }

  String _executionKeyForResult(
    ToolResultInfo toolResult, {
    required ProjectPathResolver resolveProjectPath,
  }) => _executionPolicy.toolExecutionKey(
    ToolCallInfo(
      id: toolResult.id,
      name: toolResult.name,
      arguments: toolResult.arguments,
    ),
    resolveProjectPath: resolveProjectPath,
  );

  List<ToolResultInfo> _dedupe(
    List<ToolResultInfo> toolResults, {
    required ProjectPathResolver resolveProjectPath,
  }) {
    final deduped = <ToolResultInfo>[];
    final seenKeys = <String>{};
    for (final toolResult in toolResults) {
      final identity = _executionPolicy.toolResultDedupKey(
        toolResult,
        resolveProjectPath: resolveProjectPath,
      );
      if (seenKeys.add('$identity:${toolResult.result}')) {
        deduped.add(toolResult);
      }
    }
    return deduped;
  }

  ProjectPathResolver _projectPathResolver(String? projectRoot) =>
      (path) =>
          FilesystemPathResolver.resolve(path, defaultRoot: projectRoot) ??
          path;
}
