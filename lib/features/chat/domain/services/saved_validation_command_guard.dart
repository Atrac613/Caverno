import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../data/datasources/filesystem_tools.dart';
import '../../data/datasources/git_tools.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: saved-validation-command-guard

/// Immutable saved-validation inputs captured from one exact turn owner.
final class SavedValidationCommandInput {
  SavedValidationCommandInput({
    required this.owner,
    required ToolCallInfo toolCall,
    required this.savedCommand,
    required this.ownerProjectRoot,
  }) : toolCall = _freezeToolCall(toolCall);

  final ChatTurnOwner owner;
  final ToolCallInfo toolCall;
  final String? savedCommand;
  final String? ownerProjectRoot;
}

/// Blocks attempts to modify the exact validation command saved for a turn.
final class SavedValidationCommandGuard {
  const SavedValidationCommandGuard();

  static const ToolCallExecutionPolicy _executionPolicy =
      ToolCallExecutionPolicy();

  McpToolResult? evaluate(SavedValidationCommandInput input) {
    final toolCall = input.toolCall;
    if (!_executionPolicy.isCommandExecutionTool(toolCall.name)) return null;
    final validationCommand = input.savedCommand;
    if (validationCommand == null) return null;
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    if (command == null) return null;
    final normalizedCommand = _executionPolicy
        .normalizeToolCommandForComparison(command);
    final normalizedValidationCommand = _executionPolicy
        .normalizeToolCommandForComparison(validationCommand);
    if (normalizedCommand == normalizedValidationCommand) return null;
    if (!looksLikeModifiedSavedValidationCommand(
      command: command,
      validationCommand: validationCommand,
      normalizedCommand: normalizedCommand,
      normalizedValidationCommand: normalizedValidationCommand,
      ownerProjectRoot: input.ownerProjectRoot,
    )) {
      return null;
    }

    final payload = jsonEncode({
      'ok': false,
      'code': 'saved_validation_command_modified',
      ...ToolResultOrigin.refusal.marker,
      'error':
          'A saved validation command was blocked because it was modified '
          'before execution.',
      'saved_validation_command': validationCommand,
      'attempted_command': command,
      'required_action':
          'Run the saved validation command exactly as saved, without '
          'wrappers, shell operators, extra echo commands, or fallback '
          'branches.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Run the saved validation command exactly as saved.',
    );
  }

  bool looksLikeModifiedSavedValidationCommand({
    required String command,
    required String validationCommand,
    required String normalizedCommand,
    required String normalizedValidationCommand,
    required String? ownerProjectRoot,
  }) {
    if (normalizedCommand.startsWith(normalizedValidationCommand)) {
      final suffix = normalizedCommand
          .substring(normalizedValidationCommand.length)
          .trimLeft();
      if (suffix.startsWith('&&') ||
          suffix.startsWith('||') ||
          suffix.startsWith(';') ||
          suffix.startsWith('|')) {
        return true;
      }
    }
    return looksLikePathResolvedSavedValidationCommand(
      command: command,
      validationCommand: validationCommand,
      ownerProjectRoot: ownerProjectRoot,
    );
  }

  bool looksLikePathResolvedSavedValidationCommand({
    required String command,
    required String validationCommand,
    required String? ownerProjectRoot,
  }) {
    final attemptedArgs = simpleCommandSegmentArgs(command);
    final validationArgs = simpleCommandSegmentArgs(validationCommand);
    final attemptedPathIndex = savedValidationPathArgumentIndex(attemptedArgs);
    final validationPathIndex = savedValidationPathArgumentIndex(
      validationArgs,
    );
    if (attemptedPathIndex == null ||
        validationPathIndex == null ||
        attemptedPathIndex != validationPathIndex ||
        attemptedArgs.length != validationArgs.length) {
      return false;
    }
    for (var index = 0; index < validationArgs.length; index += 1) {
      if (index == validationPathIndex) continue;
      if (attemptedArgs[index] != validationArgs[index]) return false;
    }
    final attemptedPath = _normalizePath(
      attemptedArgs[attemptedPathIndex],
      ownerProjectRoot,
    );
    final validationPath = _normalizePath(
      validationArgs[validationPathIndex],
      ownerProjectRoot,
    );
    return attemptedPath != null &&
        validationPath != null &&
        attemptedPath == validationPath;
  }

  List<String> simpleCommandSegmentArgs(String command) {
    final args = GitTools.splitArgs(command.trim());
    final controlIndex = args.indexWhere(isShellControlArgument);
    return controlIndex == -1 ? args : args.take(controlIndex).toList();
  }

  bool isShellControlArgument(String value) {
    return value == '&&' || value == '||' || value == ';' || value == '|';
  }

  int? savedValidationPathArgumentIndex(List<String> args) {
    if (args.length < 2) return null;
    final executable = args.first.split('/').last.toLowerCase();
    if (executable == 'cat' && args.length == 2) return 1;
    if (executable == 'ls' && args.length == 2) return 1;
    if (executable == 'test' && args.length == 3 && args[1] == '-f') return 2;
    if (executable == 'grep' && args.length >= 3) return args.length - 1;
    return null;
  }

  String? _normalizePath(String path, String? ownerProjectRoot) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final resolved = FilesystemTools.resolvePath(
      trimmed,
      defaultRoot: ownerProjectRoot,
    );
    var normalized = (resolved ?? trimmed).replaceAll('\\', '/').trim();
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo source) {
  return ToolCallInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  );
}
