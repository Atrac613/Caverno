import 'dart:convert';

import '../../data/datasources/filesystem_tools.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_call_execution_policy.dart';

/// Builds tool deduplication keys from explicit project context.
abstract final class ToolDedupeKeys {
  static const ToolCallExecutionPolicy _policy = ToolCallExecutionPolicy();

  static ProjectPathResolver _resolver(String? projectRoot) =>
      (path) => resolvePath(path, projectRoot: projectRoot);

  static String toolExecution(
    ToolCallInfo toolCall, {
    required String? projectRoot,
    int commandRetryGeneration = 0,
    int stateChangeGeneration = 0,
  }) => _policy.toolExecutionKey(
    toolCall,
    commandRetryGeneration: commandRetryGeneration,
    stateChangeGeneration: stateChangeGeneration,
    resolveProjectPath: _resolver(projectRoot),
  );

  static String toolFailure(
    ToolCallInfo toolCall, {
    required String? projectRoot,
    int commandRetryGeneration = 0,
  }) => _policy.toolFailureKey(
    toolCall,
    commandRetryGeneration: commandRetryGeneration,
    resolveProjectPath: _resolver(projectRoot),
  );

  static String toolCall(
    String name,
    Object? arguments, {
    required String? projectRoot,
  }) => _policy.toolCallDedupKey(
    name,
    arguments,
    resolveProjectPath: _resolver(projectRoot),
  );

  static String toolResult(
    ToolResultInfo toolResult, {
    required String? projectRoot,
  }) => _policy.toolResultDedupKey(
    toolResult,
    resolveProjectPath: _resolver(projectRoot),
  );

  static String contentExecution(String name, Object? arguments) =>
      '$name:${jsonEncode(arguments)}';

  static String resolvePath(String path, {required String? projectRoot}) =>
      FilesystemTools.resolvePath(path, defaultRoot: projectRoot) ?? path;
}
