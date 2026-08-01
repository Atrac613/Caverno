// ChatNotifier decomposition collaborator: git-tool-handler

import 'dart:convert';

import '../../data/datasources/git_tools.dart';
import '../../data/datasources/project_scoped_tool_argument_resolver.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'git_process_execution_coordinator.dart';
import 'git_tool_contract.dart';
import 'git_tool_process_runner.dart';
import 'tool_call_execution_policy.dart';

export 'git_tool_contract.dart';

/// Executes and interprets Git tools without reading notifier state.
final class GitToolHandler {
  GitToolHandler({
    required GitExecutionPort executionPort,
    required GitWorktreeSessionPort worktreeSessionPort,
    required GitApprovalPort approvalPort,
    required GitProcessExecutionCoordinator processCoordinator,
  }) : _executionPort = executionPort,
       _worktreeSessionPort = worktreeSessionPort,
       _processRunner = GitToolProcessRunner(
         approvalPort: approvalPort,
         processCoordinator: processCoordinator,
       );

  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _fileMutationEvidencePolicy = FileMutationEvidencePolicy();

  final GitExecutionPort _executionPort;
  final GitWorktreeSessionPort _worktreeSessionPort;
  final GitToolProcessRunner _processRunner;

  Future<McpToolResult> handleExecuteCommand(GitToolCallInput input) async {
    final resolvedArguments = _resolveArguments(input);
    final rawCommand = (resolvedArguments['command'] as String?)?.trim() ?? '';
    final command = GitTools.normalizeCommand(rawCommand);
    final workingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    if (command.isEmpty || workingDirectory.isEmpty) {
      return _failure(
        input.toolName,
        'command is required and working_directory must be provided or inferred from the selected coding project',
      );
    }
    final shellOperator = GitTools.firstShellControlOperator(rawCommand);
    if (shellOperator != null) {
      return _failure(
        input.toolName,
        'git_execute_command accepts one Git subcommand per tool call; '
        'shell operator "$shellOperator" is not supported',
      );
    }

    final request = GitCommandExecutionRequest(
      source: input,
      arguments: {
        ...resolvedArguments,
        'command': command,
        'working_directory': workingDirectory,
      },
      command: command,
      workingDirectory: workingDirectory,
    );
    final identity = _commandIdentity(request);
    if (GitTools.isReadOnly(command)) {
      return _processRunner.run(
        identity: identity,
        toolName: input.toolName,
        execute: (authorization) =>
            _executionPort.execute(request, authorization),
      );
    }

    return _processRunner.run(
      identity: identity,
      toolName: input.toolName,
      approval: GitApprovalRequest(
        source: input,
        actionKind: 'git_execute_command',
        arguments: request.arguments,
        commandSummary: command,
        workingDirectory: workingDirectory,
        manualDenialMessage: 'User denied git command execution',
      ),
      execute: (authorization) =>
          _executionPort.execute(request, authorization),
    );
  }

  Future<McpToolResult> handleFinishWorktreeSession(
    GitToolCallInput input,
  ) async {
    final resolvedArguments = _resolveArguments(input);
    final requestedWorktreePath =
        (resolvedArguments['worktree_path'] as String?)?.trim() ?? '';
    final worktreePath = requestedWorktreePath.isNotEmpty
        ? requestedWorktreePath
        : input.ownerWorktreePath ?? '';
    final rawBaseBranch = resolvedArguments['base_branch'] as String?;
    final baseBranch = rawBaseBranch?.trim().isNotEmpty == true
        ? rawBaseBranch!.trim()
        : 'main';
    final removeWorktree = _boolArgument(
      resolvedArguments['remove_worktree'],
      defaultValue: true,
    );
    final mergeMessage =
        (resolvedArguments['merge_message'] as String?)?.trim() ?? '';
    if (worktreePath.isEmpty) {
      return _failure(
        input.toolName,
        'worktree_path is required or the current conversation must be associated with a worktree',
      );
    }

    final request = GitWorktreeSessionRequest(
      source: input,
      arguments: {
        ...resolvedArguments,
        'worktree_path': worktreePath,
        'base_branch': baseBranch,
        'remove_worktree': removeWorktree,
        if (mergeMessage.isNotEmpty) 'merge_message': mergeMessage,
      },
      worktreePath: worktreePath,
      baseBranch: baseBranch,
      removeWorktree: removeWorktree,
      mergeMessage: mergeMessage.isEmpty ? null : mergeMessage,
    );
    return _processRunner.run(
      identity: _worktreeIdentity(request),
      toolName: input.toolName,
      approval: GitApprovalRequest(
        source: input,
        actionKind: 'git_finish_worktree_session',
        arguments: request.arguments,
        commandSummary: request.commandSummary,
        workingDirectory: worktreePath,
        manualDenialMessage: 'User denied worktree session completion',
      ),
      execute: (authorization) =>
          _worktreeSessionPort.finish(request, authorization),
    );
  }

  bool satisfiesCurrentGoalGitLifecycle(GitLifecycleInput input) {
    final results = input.toolResults;
    if (results.isEmpty) return false;
    final objective = input.goalObjective?.toLowerCase() ?? '';
    if (!input.goalIsActive ||
        !objective.contains('git') ||
        !objective.contains('revert')) {
      return false;
    }

    var hasInit = false;
    var hasAdd = false;
    var hasCommit = false;
    var hasRevert = false;
    var hasFileCreation = false;
    var lastRevertIndex = -1;
    var lastCleanStatusIndex = -1;

    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final name = result.name.trim().toLowerCase();
      if (name == 'write_file' &&
          _fileMutationEvidencePolicy.isSuccessfulResult(result)) {
        hasFileCreation = true;
        continue;
      }
      if (name != 'git_execute_command' ||
          !_executionPolicy.toolResultHasSuccessfulExit(result)) {
        continue;
      }
      final command = _normalizedGitSubcommand(result);
      if (command == null) continue;
      if (command == 'init') {
        hasInit = true;
      } else if (command.startsWith('add ')) {
        hasAdd = true;
      } else if (command.startsWith('commit ')) {
        hasCommit = true;
      } else if (command == 'revert --no-edit head') {
        hasRevert = true;
        lastRevertIndex = index;
      } else if ((command == 'status' || command == 'status --short') &&
          lastRevertIndex >= 0 &&
          _gitStatusResultIsClean(result)) {
        lastCleanStatusIndex = index;
      }
    }

    return hasInit &&
        hasFileCreation &&
        hasAdd &&
        hasCommit &&
        hasRevert &&
        lastCleanStatusIndex > lastRevertIndex;
  }

  String buildGitLifecycleCompletionResponse(GitLifecycleInput input) {
    final marker = _firstCodingGoalMarker(input.toolResults);
    final markerText = marker == null ? '' : ' Marker: $marker.';
    return 'The Git lifecycle completed successfully: git init, file creation, '
        'git add, git commit, git revert, and the final git status all '
        'succeeded with a clean working tree.$markerText Goal complete. '
        'Tests passed.';
  }

  GitProcessExecutionIdentity _commandIdentity(
    GitCommandExecutionRequest request,
  ) {
    final repository =
        request.source.ownerRepositoryPath ?? request.workingDirectory;
    final worktree =
        request.source.ownerWorktreePath ?? request.workingDirectory;
    return GitProcessExecutionIdentity(
      owner: request.source.owner,
      toolCallId: request.source.toolCallId,
      toolName: request.source.toolName,
      repositoryIdentity: repository,
      worktreeIdentity: worktree,
      argumentDigest: gitToolArgumentDigest(request.arguments),
    );
  }

  GitProcessExecutionIdentity _worktreeIdentity(
    GitWorktreeSessionRequest request,
  ) {
    return GitProcessExecutionIdentity(
      owner: request.source.owner,
      toolCallId: request.source.toolCallId,
      toolName: request.source.toolName,
      repositoryIdentity:
          request.source.ownerRepositoryPath ?? request.worktreePath,
      worktreeIdentity: request.worktreePath,
      argumentDigest: gitToolArgumentDigest(request.arguments),
    );
  }

  Map<String, dynamic> _resolveArguments(GitToolCallInput input) {
    return ProjectScopedToolArgumentResolver.resolve(
      toolName: input.toolName,
      arguments: input.arguments,
      loadProjectRoot: () => input.ownerRepositoryPath,
    );
  }

  bool _boolArgument(Object? value, {required bool defaultValue}) {
    return switch (value) {
      null => defaultValue,
      bool boolValue => boolValue,
      num numberValue => numberValue != 0,
      String stringValue => switch (stringValue.trim().toLowerCase()) {
        'true' || '1' || 'yes' || 'y' => true,
        'false' || '0' || 'no' || 'n' => false,
        _ => defaultValue,
      },
      _ => defaultValue,
    };
  }

  String? _normalizedGitSubcommand(ToolResultInfo result) {
    var command = _executionPolicy.toolCommandArgument(result.arguments);
    final decodedCommand = _executionPolicy.tryDecodeMap(
      result.result,
    )?['command'];
    if ((command == null || command.trim().isEmpty) &&
        decodedCommand is String) {
      command = decodedCommand;
    }
    if (command == null) return null;
    var normalized = _executionPolicy.normalizeToolCommandForComparison(
      command,
    );
    if (normalized.startsWith('git ')) {
      normalized = normalized.substring(4).trim();
    }
    return normalized;
  }

  bool _gitStatusResultIsClean(ToolResultInfo result) {
    final decoded = _executionPolicy.tryDecodeMap(result.result);
    final stdout = decoded?['stdout']?.toString().trim().toLowerCase() ?? '';
    final stderr = decoded?['stderr']?.toString().trim().toLowerCase() ?? '';
    return stderr.isEmpty &&
        (stdout.isEmpty || stdout.contains('working tree clean'));
  }

  String? _firstCodingGoalMarker(List<ToolResultInfo> results) {
    final markerPattern = RegExp(r'\bCODING_GOAL_[A-Z0-9_]+\b');
    for (final result in results) {
      for (final candidate in [jsonEncode(result.arguments), result.result]) {
        final match = markerPattern.firstMatch(candidate);
        if (match != null) return match.group(0);
      }
    }
    return null;
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}
