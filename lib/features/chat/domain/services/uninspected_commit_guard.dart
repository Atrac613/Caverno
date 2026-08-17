import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'immutable_json_snapshot.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: uninspected-commit-guard

/// Immutable turn facts for one commit decision.
final class UninspectedCommitInput {
  UninspectedCommitInput({
    required ToolCallInfo toolCall,
    required List<ToolResultInfo> executedToolResults,
  }) : toolCall = _freezeToolCall(toolCall),
       executedToolResults = List<ToolResultInfo>.unmodifiable(
         executedToolResults.map(_freezeToolResult),
       );

  final ToolCallInfo toolCall;
  final List<ToolResultInfo> executedToolResults;
}

/// Blocks a commit of changes the turn never looked at.
///
/// Session 96797b74 committed six files under `chore(flutter): Flutter
/// 3.47.0へ更新` after running only `git status --short` and
/// `git diff --stat`. Neither shows content, so the message was inferred from
/// conversation context and applied to changes the turn had not read -- one of
/// them an unrelated `analysis_options.yaml` edit. The bundling may well have
/// been right; the point is that nothing in the turn could tell.
///
/// The guard is deliberately narrow. It stays silent when the turn produced
/// the changes itself, since a model that just wrote the files knows what it
/// is committing; it fires only when a turn commits work it inherited without
/// reading a content diff. `--stat`, `--name-only`, `--numstat` and
/// `--name-status` do not count: those are exactly the forms that report file
/// names while hiding what changed.
final class UninspectedCommitGuard {
  const UninspectedCommitGuard();

  static const blockedCode = 'commit_without_diff_inspection_blocked';
  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _mutationPolicy = FileMutationEvidencePolicy();

  /// Diff flags that summarise without revealing content.
  static const Set<String> _summaryOnlyFlags = {
    '--stat',
    '--shortstat',
    '--numstat',
    '--name-only',
    '--name-status',
    '--dirstat',
    '--summary',
  };

  McpToolResult? evaluate(UninspectedCommitInput input) {
    if (!_isCommitCall(input.toolCall)) {
      return null;
    }
    if (input.executedToolResults.any(_isOwnFileMutation)) {
      return null;
    }
    if (input.executedToolResults.any(_revealsContent)) {
      return null;
    }
    return McpToolResult(
      toolName: input.toolCall.name,
      result: jsonEncode({
        'error':
            'This turn has not read what it is about to commit. Only file '
            'names were inspected, and no file was written here, so the '
            'staged content came from outside this turn and the commit '
            'message would describe changes nobody looked at.',
        'code': blockedCode,
        'required_action':
            'Run git_execute_command with "diff --cached" (or "diff" for '
            'unstaged work) and read the result, then commit. If the diff '
            'turns out to hold unrelated changes, stage them separately or '
            'say so rather than covering them with one message. A summary '
            'form such as --stat or --name-only does not satisfy this: it '
            'reports file names and hides the change.',
      }),
      isSuccess: true,
    );
  }

  bool _isCommitCall(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() != 'git_execute_command') {
      return false;
    }
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return false;
    }
    final args = _argumentsOf(command);
    return args.isNotEmpty && args.first == 'commit';
  }

  bool _isOwnFileMutation(ToolResultInfo result) =>
      _mutationPolicy.isMutationToolName(result.name);

  bool _revealsContent(ToolResultInfo result) {
    if (result.name.trim().toLowerCase() != 'git_execute_command') {
      return false;
    }
    final command = _executionPolicy.toolCommandArgument(result.arguments);
    if (command == null) {
      return false;
    }
    final args = _argumentsOf(command);
    if (args.isEmpty || (args.first != 'diff' && args.first != 'show')) {
      return false;
    }
    return !args
        .skip(1)
        .any((arg) => _summaryOnlyFlags.contains(arg.split('=').first));
  }

  List<String> _argumentsOf(String command) {
    var normalized = command.trim();
    if (normalized.toLowerCase().startsWith('git ')) {
      normalized = normalized.substring(4).trimLeft();
    }
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo source) => ToolCallInfo(
  id: source.id,
  name: source.name,
  arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
);

ToolResultInfo _freezeToolResult(ToolResultInfo source) => ToolResultInfo(
  id: source.id,
  name: source.name,
  arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  result: source.result,
);
