import 'dart:convert';

import '../../data/datasources/git_tools.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: git-tag-format-inspection-guard

/// Immutable owner-resolved inputs for one tag-format inspection decision.
final class GitTagFormatInspectionInput {
  GitTagFormatInspectionInput({
    required ToolCallInfo toolCall,
    required Map<String, dynamic> resolvedArguments,
    required List<ToolResultInfo> executedToolResults,
  }) : toolCall = _freezeToolCall(toolCall),
       resolvedArguments = ImmutableJsonSnapshot.freezeMap(resolvedArguments),
       executedToolResults = List<ToolResultInfo>.unmodifiable(
         executedToolResults.map(_freezeToolResult),
       );

  final ToolCallInfo toolCall;
  final Map<String, dynamic> resolvedArguments;
  final List<ToolResultInfo> executedToolResults;
}

/// Requires a successful owner-repository tag inspection before tag creation.
final class GitTagFormatInspectionGuard {
  const GitTagFormatInspectionGuard();

  static const blockedCode = 'git_tag_format_inspection_required';

  McpToolResult? evaluate(GitTagFormatInspectionInput input) {
    if (input.toolCall.name != 'git_execute_command') {
      return null;
    }
    final rawCommand =
        (input.resolvedArguments['command'] as String?)?.trim() ?? '';
    if (rawCommand.contains('\n') ||
        rawCommand.contains('\r') ||
        GitTools.firstShellControlOperator(rawCommand) != null) {
      return null;
    }
    final command = GitTools.normalizeCommand(rawCommand);
    if (!isTagCreationCommand(command)) {
      return null;
    }

    final workingDirectory =
        (input.resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    final hasTagFormatInspection = input.executedToolResults.any(
      (toolResult) => isSuccessfulTagFormatInspection(
        toolResult,
        workingDirectory: workingDirectory,
      ),
    );
    if (hasTagFormatInspection) {
      return null;
    }

    return McpToolResult(
      toolName: input.toolCall.name,
      result: jsonEncode({
        'error':
            'Git tag creation requires inspecting existing tag names in this '
            'turn before creating a new tag.',
        'code': blockedCode,
        'command': 'git $command',
        'working_directory': workingDirectory,
        'required_action':
            'Run git_execute_command with "tag --list" or '
            '"for-each-ref refs/tags --format=%(refname:short)" first, then '
            'choose a new tag name that matches the existing repository format.',
      }),
      isSuccess: false,
      errorMessage: 'Inspect existing git tag names before creating a new tag.',
    );
  }

  bool isTagCreationCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty || args.first != 'tag' || GitTools.isReadOnly(command)) {
      return false;
    }
    return !args.any((arg) => arg == '-d' || arg == '--delete');
  }

  bool isSuccessfulTagFormatInspection(
    ToolResultInfo toolResult, {
    required String workingDirectory,
  }) {
    if (toolResult.name != 'git_execute_command') {
      return false;
    }
    final command = GitTools.normalizeCommand(
      (toolResult.arguments['command'] as String?)?.trim() ?? '',
    );
    if (!isTagFormatInspectionCommand(command)) {
      return false;
    }
    final decoded = _decodeJsonObject(toolResult.result);
    if (decoded == null || decoded['exit_code'] != 0) {
      return false;
    }
    final resultWorkingDirectory = decoded['working_directory'];
    return workingDirectory.isEmpty ||
        resultWorkingDirectory is! String ||
        resultWorkingDirectory == workingDirectory;
  }

  bool isTagFormatInspectionCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty) {
      return false;
    }
    if (args.first == 'tag' && GitTools.isReadOnly(command)) {
      return true;
    }
    if (args.first == 'for-each-ref' &&
        args.any((arg) => arg == 'refs/tags' || arg.startsWith('refs/tags/'))) {
      return true;
    }
    return args.first == 'show-ref' && args.contains('--tags');
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo source) {
  return ToolCallInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  );
}

ToolResultInfo _freezeToolResult(ToolResultInfo source) {
  return ToolResultInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
    result: source.result,
  );
}

Map<String, dynamic>? _decodeJsonObject(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
