import 'dart:convert';

import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../entities/tool_call_info.dart';

typedef ProjectPathResolver = String? Function(String path);

class ToolCallExecutionPolicy {
  const ToolCallExecutionPolicy();

  String toolExecutionKey(
    ToolCallInfo toolCall, {
    int commandRetryGeneration = 0,
    ProjectPathResolver? resolveProjectPath,
  }) {
    final baseKey = toolCallDedupKey(
      toolCall.name,
      toolCall.arguments,
      resolveProjectPath: resolveProjectPath,
    );
    if (isRepeatableCommandTool(toolCall)) {
      return '$baseKey#commandRetryGeneration=$commandRetryGeneration';
    }
    return baseKey;
  }

  String toolCallDedupKey(
    String name,
    Object? arguments, {
    ProjectPathResolver? resolveProjectPath,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedArguments = _normalizeToolArgumentsForDedup(
      normalizedName,
      arguments,
      resolveProjectPath: resolveProjectPath,
    );
    return '$normalizedName:${_normalizeToolExecutionValue(normalizedArguments)}';
  }

  String toolResultDedupKey(
    ToolResultInfo toolResult, {
    ProjectPathResolver? resolveProjectPath,
  }) {
    return toolCallDedupKey(
      toolResult.name,
      toolResult.arguments,
      resolveProjectPath: resolveProjectPath,
    );
  }

  bool toolResultMatchesToolCall(
    ToolResultInfo toolResult,
    ToolCallInfo toolCall, {
    ProjectPathResolver? resolveProjectPath,
  }) {
    return toolResultDedupKey(
          toolResult,
          resolveProjectPath: resolveProjectPath,
        ) ==
        toolCallDedupKey(
          toolCall.name,
          toolCall.arguments,
          resolveProjectPath: resolveProjectPath,
        );
  }

  bool isRepeatableCommandTool(ToolCallInfo toolCall) {
    return toolCall.name == 'local_execute_command' ||
        toolCall.name == 'run_tests' ||
        toolCall.name == 'git_execute_command';
  }

  bool advancesCommandRetryGeneration(ToolCallInfo toolCall) {
    final normalizedName = toolCall.name.trim().toLowerCase();
    return normalizedName == 'write_file' ||
        normalizedName == 'edit_file' ||
        normalizedName == 'rollback_last_file_change' ||
        normalizedName.startsWith('write_') ||
        normalizedName.startsWith('edit_');
  }

  bool shouldAllowRepeatedToolExecution(ToolCallInfo toolCall) {
    return toolCall.name == 'read_file' ||
        isRepeatableBackgroundProcessInspectionTool(toolCall) ||
        isRepeatableProcessMonitorToolCall(toolCall);
  }

  bool isRepeatableBackgroundProcessInspectionTool(ToolCallInfo toolCall) {
    switch (toolCall.name.trim().toLowerCase()) {
      case 'process_status':
      case 'process_tail':
      case 'process_wait':
      case 'process_list':
        return true;
    }
    return false;
  }

  bool isRepeatableProcessMonitorToolCall(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() != 'local_execute_command') {
      return false;
    }
    final command = toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return false;
    }
    final normalized = command.trim().toLowerCase();
    return RegExp(
      r'^sleep\s+\d+(?:\.\d+)?\s*(?:&&|;)\s*(?:ps|pgrep)\b',
    ).hasMatch(normalized);
  }

  bool isCommandExecutionTool(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'local_execute_command':
      case 'process_start':
      case 'process_status':
      case 'process_wait':
      case 'run_tests':
      case 'git_execute_command':
      case 'ssh_execute_command':
        return true;
    }
    return false;
  }

  String? toolCommandArgument(Map<String, dynamic> arguments) {
    final command = arguments['command']?.toString().trim();
    return command == null || command.isEmpty ? null : command;
  }

  bool toolResultHasSuccessfulExit(ToolResultInfo result) {
    if (!isCommandExecutionTool(result.name)) {
      return false;
    }
    final name = result.name.trim().toLowerCase();
    if (name == 'process_start' ||
        name == 'process_status' ||
        name == 'process_wait') {
      final decoded = tryDecodeMap(result.result);
      return decoded?['ok'] == true &&
          decoded?['status'] == 'exited' &&
          exitCodeValue(decoded?['exit_code']) == 0;
    }
    if (toolResultTimedOut(result)) {
      return false;
    }
    final decoded = tryDecodeMap(result.result);
    final exitCode = decoded?['exit_code'];
    if (exitCode is num) {
      return exitCode == 0;
    }
    if (exitCode is String) {
      return int.tryParse(exitCode.trim()) == 0;
    }
    return RegExp(
      r'^exit_code:\s*0\s*$',
      multiLine: true,
    ).hasMatch(result.result);
  }

  int? exitCodeValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  bool toolResultTimedOut(ToolResultInfo result) {
    if (!isCommandExecutionTool(result.name)) {
      return false;
    }
    final decoded = tryDecodeMap(result.result);
    if (decoded?['timed_out'] == true) {
      return true;
    }
    final error = decoded?['error']?.toString().toLowerCase() ?? '';
    return error.contains('timed out');
  }

  String? toolResultErrorText(ToolResultInfo result) {
    final decoded = tryDecodeMap(result.result);
    return decoded?['error']?.toString();
  }

  bool toolResultCommandMatches(
    ToolResultInfo result, {
    required String normalizedCommand,
  }) {
    final argumentCommand = toolCommandArgument(result.arguments);
    if (argumentCommand != null &&
        normalizeToolCommandForComparison(argumentCommand) ==
            normalizedCommand) {
      return true;
    }
    final decoded = tryDecodeMap(result.result);
    final resultCommand = decoded?['command']?.toString().trim();
    return resultCommand != null &&
        resultCommand.isNotEmpty &&
        normalizeToolCommandForComparison(resultCommand) == normalizedCommand;
  }

  bool toolCommandMatchesSavedValidation({
    required ToolResultInfo result,
    required String command,
    required String normalizedValidationCommand,
  }) {
    final normalizedCommand = normalizeToolCommandForComparison(command);
    if (normalizedCommand == normalizedValidationCommand) {
      return true;
    }
    final isValidationWrapper = normalizedCommand.startsWith(
      '$normalizedValidationCommand && ',
    );
    if (!isValidationWrapper) {
      return false;
    }
    if (toolResultOutputSuggestsValidationFailure(result)) {
      return false;
    }
    if (!normalizedCommand.contains(' || ')) {
      return true;
    }
    if (toolResultOutputText(result).trim().isEmpty) {
      return false;
    }
    return !toolResultOutputSuggestsValidationFailure(result);
  }

  bool toolResultOutputSuggestsValidationFailure(ToolResultInfo result) {
    final output = toolResultOutputText(result).toLowerCase();
    return output.contains('validation failed') ||
        output.contains('validation failure');
  }

  String toolResultOutputText(ToolResultInfo result) {
    final decoded = tryDecodeMap(result.result);
    return [
      decoded?['stdout']?.toString(),
      decoded?['stderr']?.toString(),
    ].whereType<String>().join('\n');
  }

  String normalizeToolCommandForComparison(String command) {
    return LocalShellTools.normalizeCommand(
      command,
    ).replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  String? runTestsPathArgument(Map<String, dynamic> arguments) {
    final testPath = arguments['test_path']?.toString().trim();
    if (testPath != null && testPath.isNotEmpty) {
      return testPath;
    }
    final path = arguments['path']?.toString().trim();
    return path == null || path.isEmpty ? null : path;
  }

  bool runTestsMatchesSavedValidation({
    required Map<String, dynamic> arguments,
    required String normalizedValidationCommand,
  }) {
    final normalizedValidation = normalizedValidationCommand.replaceAll(
      RegExp("[\"']"),
      '',
    );
    final testPath = runTestsPathArgument(arguments);
    if (testPath == null) {
      return normalizedValidation.contains('run_tests') ||
          normalizedValidation.contains('flutter test') ||
          normalizedValidation.contains('dart test');
    }

    final normalizedPath = normalizeToolCommandForComparison(
      testPath,
    ).replaceAll(RegExp("[\"']"), '');
    return normalizedPath.isNotEmpty &&
        (normalizedValidation.contains(normalizedPath) ||
            normalizedValidation.contains('run_tests'));
  }

  bool isReadOnlyInspectionTool(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'list_directory':
      case 'read_file':
      case 'inspect_file':
      case 'find_files':
      case 'search_files':
      case 'process_status':
      case 'process_tail':
      case 'process_wait':
      case 'process_list':
        return true;
    }
    return false;
  }

  bool isReadOnlyInspectionToolCall(ToolCallInfo toolCall) {
    if (isReadOnlyInspectionTool(toolCall.name)) {
      return true;
    }
    if (toolCall.name.trim().toLowerCase() != 'local_execute_command') {
      return false;
    }
    final command = toolCommandArgument(toolCall.arguments);
    return command != null && LocalShellTools.isReadOnly(command);
  }

  bool isReadOnlyCommandExecutionToolCall(ToolCallInfo toolCall) {
    final command = toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return false;
    }
    return switch (toolCall.name.trim().toLowerCase()) {
      'local_execute_command' => LocalShellTools.isReadOnly(command),
      'git_execute_command' => GitTools.isReadOnly(command),
      _ => false,
    };
  }

  Map<String, dynamic>? tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Object? _normalizeToolArgumentsForDedup(
    String toolName,
    Object? arguments, {
    ProjectPathResolver? resolveProjectPath,
  }) {
    if (arguments is! Map) {
      return arguments;
    }
    final normalized = <String, dynamic>{...arguments};
    if (_usesProjectScopedPathArgument(toolName)) {
      final normalizedPath = _normalizeToolPathForDedup(
        normalized['path'],
        resolveProjectPath: resolveProjectPath,
      );
      if (normalizedPath != null) {
        normalized['path'] = normalizedPath;
      }
    }
    return normalized;
  }

  bool _usesProjectScopedPathArgument(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'list_directory':
      case 'read_file':
      case 'inspect_file':
      case 'find_files':
      case 'search_files':
      case 'write_file':
      case 'edit_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
  }

  String? _normalizeToolPathForDedup(
    Object? rawPath, {
    ProjectPathResolver? resolveProjectPath,
  }) {
    if (rawPath is! String) {
      return null;
    }
    final trimmed = rawPath.trim();
    return resolveProjectPath?.call(trimmed) ?? trimmed;
  }

  String _normalizeToolExecutionValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      final normalized = <String, String>{};
      for (final entry in entries) {
        normalized[entry.key.toString()] = _normalizeToolExecutionValue(
          entry.value,
        );
      }
      return jsonEncode(normalized);
    }

    if (value is List) {
      return jsonEncode(
        value.map(_normalizeToolExecutionValue).toList(growable: false),
      );
    }

    return jsonEncode(value);
  }
}
