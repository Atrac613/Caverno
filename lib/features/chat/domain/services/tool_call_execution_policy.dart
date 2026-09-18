import 'dart:convert';

import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'tool_outcome_shadow_comparison.dart';

typedef ProjectPathResolver = String? Function(String path);

class ToolCallExecutionPolicy {
  const ToolCallExecutionPolicy();

  static const _fileMutationEvidencePolicy = FileMutationEvidencePolicy();

  /// Argument keys that carry model-authored narration rather than execution
  /// semantics. Stripped from the consecutive-failure key ([toolFailureKey])
  /// and from [ToolApprovalCache], so a model that re-issues the *same*
  /// failing/denied command while rewording `reason` is still counted as
  /// repeating one action. [toolExecutionKey] keeps narration only for calls
  /// [shouldAllowRepeatedToolExecution] already admits -- a re-narrated
  /// read-only inspection may legitimately re-run -- and strips it everywhere
  /// else, so rewording cannot bypass side-effect deduplication. Sharing the
  /// set keeps the derivations from drifting apart; the allow-list keeps a
  /// newly added side-effecting tool protected by default rather than exposed
  /// until someone remembers to name it.
  static const Set<String> nonSemanticArgumentKeys = {'reason'};

  String toolExecutionKey(
    ToolCallInfo toolCall, {
    int commandRetryGeneration = 0,
    int stateChangeGeneration = 0,
    ProjectPathResolver? resolveProjectPath,
  }) {
    final baseKey = toolCallDedupKey(
      toolCall.name,
      toolCall.arguments,
      resolveProjectPath: resolveProjectPath,
      // Narration survives the key only where re-running is already admitted.
      // Naming the *protected* tools instead -- this read
      // `isFileMutationToolCall` -- left every consequential tool that is not
      // a file write exposed by default, which is how `browser_submit` came to
      // re-execute under a reworded `reason` while `ToolApprovalCache`, which
      // strips narration for everything, reported the call already approved
      // and raised no second prompt.
      //
      // Command execution tools are carved out and keep today's behaviour.
      // `isReadOnlyCommandExecutionToolCall` does not recognise `git status`,
      // `git tag --list` or `gh pr checks` as read-only, so stripping
      // narration here would stop the very inspections the loop depends on
      // from re-running -- session 96e27118 ended a turn mid-task that way.
      // That leaves a reworded *mutating* `local_execute_command` still able
      // to re-execute; closing it needs a read-only command classifier worth
      // trusting, which is its own change.
      excludeNonSemanticKeys:
          !shouldAllowRepeatedToolExecution(toolCall) &&
          !isRepeatableCommandTool(toolCall),
    );
    if (!isRepeatableCommandTool(toolCall)) {
      return baseKey;
    }
    final key = '$baseKey#commandRetryGeneration=$commandRetryGeneration';
    if (!isReadOnlyCommandExecutionToolCall(toolCall)) {
      return key;
    }
    // An observation is only valid for the state it observed. `git status`
    // before a `gh pr checkout` and `git status` after it are different
    // questions, so replaying the first as the answer to the second reports a
    // branch the workspace already left. Scoping the generation to read-only
    // calls keeps side-effect deduplication intact: a repeated mutating
    // command still collides with its own earlier key.
    return '$key#stateChangeGeneration=$stateChangeGeneration';
  }

  /// Whether executing [toolCall] invalidates earlier workspace observations.
  ///
  /// A command tool that is not read-only can move the branch, the working
  /// tree, or any other state a previous inspection reported.
  bool advancesStateChangeGeneration(ToolCallInfo toolCall) =>
      isRepeatableCommandTool(toolCall) &&
      !isReadOnlyCommandExecutionToolCall(toolCall);

  /// Key for consecutive-failure tracking, distinct from [toolExecutionKey].
  ///
  /// [toolExecutionKey] keeps model narration for command execution and for
  /// calls [shouldAllowRepeatedToolExecution] admits, so a re-narrated
  /// inspection (e.g. `git status` after a commit, then after a revert) can
  /// legitimately re-run. Failure tracking needs the
  /// opposite: a model that retries the *same* failing/denied command under
  /// reworded `reason` text is repeating one action, so
  /// [nonSemanticArgumentKeys] are stripped here.
  /// Without this, the `toolFailureCounts >= 2` abort never fires against a
  /// model that varies its narration on each retry.
  String toolFailureKey(
    ToolCallInfo toolCall, {
    int commandRetryGeneration = 0,
    ProjectPathResolver? resolveProjectPath,
  }) {
    final baseKey = toolCallDedupKey(
      toolCall.name,
      toolCall.arguments,
      resolveProjectPath: resolveProjectPath,
      excludeNonSemanticKeys: true,
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
    bool excludeNonSemanticKeys = false,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedArguments = _normalizeToolArgumentsForDedup(
      normalizedName,
      arguments,
      resolveProjectPath: resolveProjectPath,
      excludeNonSemanticKeys: excludeNonSemanticKeys,
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
        normalizedName == 'delete_file' ||
        normalizedName == 'rollback_last_file_change' ||
        normalizedName.startsWith('write_') ||
        normalizedName.startsWith('edit_');
  }

  bool isFileMutationToolCall(ToolCallInfo toolCall) =>
      _fileMutationEvidencePolicy.isMutationToolName(toolCall.name);

  /// Whether [toolCall] may run again after an identical call this turn.
  ///
  /// Read-only commands are admitted because the loop gives the model no other
  /// way back to their output: a follow-up request carries only the current
  /// batch's results, and `ToolLoopContextDigest` names the command and its
  /// exit status while stating that the output is not carried. Refusing the
  /// re-run made that instruction a trap -- session 96e27118 re-issued
  /// `git tag --list --sort=-version:refname` to recover the tag list, the
  /// guard skipped it, and the empty batch ended the turn mid-task.
  ///
  /// This is an allowance, not a licence to spin: `ReadOnlyCommandRepeatBudget`
  /// caps how many times one such call may run per generation, and a mutating
  /// command still collides with its own earlier key so one side effect cannot
  /// run twice.
  bool shouldAllowRepeatedToolExecution(ToolCallInfo toolCall) {
    return toolCall.name == 'read_file' ||
        isReadOnlyCommandExecutionToolCall(toolCall) ||
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

  /// Whether a turn restricted to [allowedToolNames] could execute a command
  /// at all. `null` means the turn had the full catalog.
  ///
  /// A claim about running something is *unexecutable* rather than unexecuted
  /// when the turn was never given a tool that could run it, and faulting it
  /// makes the harness penalise the model for a restriction the harness
  /// imposed. Session 76864d26 shows the cost: an elicitation turn limited to
  /// `update_goal` narrated a verification, the unexecuted-action guard fired,
  /// and the resulting incomplete evidence overruled the completion that same
  /// turn had just recorded.
  bool offersCommandExecution(Set<String>? allowedToolNames) {
    if (allowedToolNames == null) {
      return true;
    }
    return allowedToolNames.any(isCommandExecutionTool);
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
    final outcome = result.outcome;
    if (outcome?.processState != null) {
      return outcome!.isProcessTerminal && outcome.hasSucceedingExitCode;
    }
    if (outcome?.exitCode != null) {
      return outcome!.hasSucceedingExitCode;
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
    final exitCode = toolResultExitCode(result).exitCode;
    if (exitCode != null) return exitCode == 0;
    return RegExp(
      r'^exit_code:\s*0\s*$',
      multiLine: true,
    ).hasMatch(result.result);
  }

  bool toolResultHasFailedExit(ToolResultInfo result) {
    if (!isCommandExecutionTool(result.name)) return false;
    final outcome = result.outcome;
    if (outcome?.processState != null) {
      return outcome!.isProcessTerminal && outcome.hasFailingExitCode;
    }
    if (outcome?.exitCode != null) return outcome!.hasFailingExitCode;
    final exitCode = toolResultExitCode(result).exitCode;
    if (exitCode != null) return exitCode != 0;
    return RegExp(
      r'^exit_code:\s*(?!0\s*$)-?\d+\s*$',
      multiLine: true,
    ).hasMatch(result.result);
  }

  ToolOutcomeExitCodeResolution toolResultExitCode(ToolResultInfo result) {
    final outcome = result.outcome;
    if (outcome?.exitCode != null) {
      return resolveToolOutcomeExitCode(outcome: outcome, parsedExitCode: null);
    }
    final decoded = tryDecodeMap(result.result);
    return resolveToolOutcomeExitCode(
      outcome: outcome,
      parsedExitCode: exitCodeValue(decoded?['exit_code']),
    );
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

  /// Whether [result] is the tool refusing the request, not a command that ran
  /// and failed.
  ///
  /// A malformed argument is rejected before anything is spawned, so there is
  /// no exit status to judge. Callers that grade command outcomes must skip
  /// these: a rejection reported as a non-zero exit is indistinguishable from
  /// a real failure, and in session 9174dbd1 one such rejection marked every
  /// success claim in the turn unverified for the rest of the session.
  bool toolResultRejectedBeforeExecution(ToolResultInfo result) {
    if (!isCommandExecutionTool(result.name)) {
      return false;
    }
    final decoded = tryDecodeMap(result.result);
    if (decoded == null) {
      return false;
    }
    if (decoded['executed'] == false) {
      return true;
    }
    return _rejectedBeforeExecutionCodes.contains(
      decoded['code']?.toString().trim().toLowerCase(),
    );
  }

  static const Set<String> _rejectedBeforeExecutionCodes = {
    'command_rejected_before_execution',
  };

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

  bool containsOnlyPreviouslySuccessfulCommandToolCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolResultInfo> previousToolResults,
  ) {
    if (toolCalls.isEmpty || previousToolResults.isEmpty) {
      return false;
    }
    return toolCalls.every((toolCall) {
      return previousToolResults.any(
        (result) => _successfulCommandResultMatchesToolCall(result, toolCall),
      );
    });
  }

  String previousSuccessfulCommandOutputForDuplicateCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolResultInfo> previousToolResults,
  ) {
    final outputs = <String>[];
    for (final toolCall in toolCalls) {
      for (final result in previousToolResults.reversed) {
        if (!_successfulCommandResultMatchesToolCall(result, toolCall)) {
          continue;
        }
        final output = toolResultOutputText(result).trim();
        if (output.isNotEmpty) {
          outputs.add(output);
        }
        break;
      }
    }
    return outputs.join('\n');
  }

  /// Whether a duplicate command call's earlier output may stand in as the
  /// turn's answer.
  ///
  /// `git_execute_command` belongs here for the same reason the other two do:
  /// its output is what the model asked for and could no longer see. Leaving
  /// it out made the recovery unreachable for every git-driven turn — session
  /// 96e27118 re-issued `git tag --list --sort=-version:refname` to recover
  /// the tag list, this gate rejected it on the tool name alone, and the turn
  /// ended on its own preamble with the tag list sitting unused in
  /// [previousSuccessfulCommandOutputForDuplicateCalls].
  bool shouldUsePreviousOutputForDuplicateCommandCalls(
    List<ToolCallInfo> toolCalls,
  ) {
    return toolCalls.every((toolCall) {
      return switch (toolCall.name.trim().toLowerCase()) {
        'local_execute_command' || 'git_execute_command' || 'run_tests' => true,
        _ => false,
      };
    });
  }

  bool _successfulCommandResultMatchesToolCall(
    ToolResultInfo result,
    ToolCallInfo toolCall,
  ) {
    if (toolCall.name == 'run_tests') {
      final testPath = runTestsPathArgument(toolCall.arguments);
      return result.name == toolCall.name &&
          runTestsPathArgument(result.arguments) == testPath &&
          toolResultHasSuccessfulExit(result);
    }
    if (!isCommandExecutionTool(toolCall.name)) {
      return false;
    }
    final command = toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return false;
    }
    return result.name == toolCall.name &&
        toolCommandArgument(result.arguments) == command &&
        toolResultHasSuccessfulExit(result);
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
    // Read-only command-execution tools count as inspection too: a read-only
    // `local_execute_command` (e.g. `pwd`) and a read-only `git_execute_command`
    // (e.g. `git status`, `git tag --list`) are probing the workspace, not
    // mutating it. Without classifying git here, a model that loops on read-only
    // git inspection never trips the duplicate-inspection / loop-exhaustion
    // recovery, because those guards require *every* pending tool call to be
    // read-only inspection.
    return isReadOnlyCommandExecutionToolCall(toolCall);
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
    bool excludeNonSemanticKeys = false,
  }) {
    if (arguments is! Map) {
      return arguments;
    }
    final normalized = <String, dynamic>{...arguments};
    if (excludeNonSemanticKeys) {
      normalized.removeWhere((key, _) => nonSemanticArgumentKeys.contains(key));
    }
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
      case 'delete_file':
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
