// Same-library extension on [ChatNotifier]; the `state` accessor is intentionally
// reached through the part-of bridge. Riverpod marks `state` as `@protected` and
// `@visibleForTesting`, which are not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierGitHandlers on ChatNotifier {
  Future<McpToolResult> _handleGitExecuteCommand(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final command = GitTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
    final requestedWorkingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    final workingDirectory = requestedWorkingDirectory;

    if (command.isEmpty || workingDirectory.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage:
            'command is required and working_directory must be provided or inferred from the selected coding project',
      );
    }

    final gitArguments = {
      ...resolvedArguments,
      'command': command,
      'working_directory': workingDirectory,
    };

    // Read-only commands execute immediately without user confirmation.
    if (GitTools.isReadOnly(command)) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: gitArguments,
      );
    }

    final cachedResult = _lookupToolApprovalResult(toolCall.name, gitArguments);
    if (cachedResult != null) {
      return cachedResult;
    }

    final reason = toolCall.arguments['reason'] as String?;
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'git_execute_command',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: gitArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'git_execute_command',
        arguments: gitArguments,
        workingDirectory: workingDirectory,
        reason: reason,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        gitArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      // Write commands require user approval.
      final approved = await requestGitCommand(
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          gitArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied git command execution',
          ),
        );
      }
    }
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: gitArguments,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, gitArguments, result);
  }

  Future<McpToolResult> _handleGitFinishWorktreeSession(
    ToolCallInfo toolCall,
  ) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final conversationWorktreePath =
        ref
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.normalizedWorktreePath ??
        '';
    final requestedWorktreePath =
        (resolvedArguments['worktree_path'] as String?)?.trim() ?? '';
    final worktreePath = requestedWorktreePath.isNotEmpty
        ? requestedWorktreePath
        : conversationWorktreePath;
    final baseBranch =
        (resolvedArguments['base_branch'] as String?)?.trim().isNotEmpty ??
            false
        ? (resolvedArguments['base_branch'] as String).trim()
        : 'main';
    final removeWorktree = _boolArgument(
      resolvedArguments['remove_worktree'],
      defaultValue: true,
    );
    final mergeMessage =
        (resolvedArguments['merge_message'] as String?)?.trim() ?? '';

    if (worktreePath.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage:
            'worktree_path is required or the current conversation must be associated with a worktree',
      );
    }

    final finishArguments = <String, dynamic>{
      ...resolvedArguments,
      'worktree_path': worktreePath,
      'base_branch': baseBranch,
      'remove_worktree': removeWorktree,
      if (mergeMessage.isNotEmpty) 'merge_message': mergeMessage,
    };

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      finishArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final reason = toolCall.arguments['reason'] as String?;
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'git_finish_worktree_session',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: finishArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'git_finish_worktree_session',
        arguments: finishArguments,
        workingDirectory: worktreePath,
        reason: reason,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        finishArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final commandSummary = removeWorktree
          ? 'finish worktree session: merge into $baseBranch and remove $worktreePath'
          : 'finish worktree session: merge into $baseBranch';
      final approved = await requestGitCommand(
        command: commandSummary,
        workingDirectory: worktreePath,
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          finishArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied worktree session completion',
          ),
        );
      }
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: finishArguments,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, finishArguments, result);
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

  bool _toolResultsSatisfyCurrentGoalGitLifecycle(
    List<ToolResultInfo> toolResults,
  ) {
    if (toolResults.isEmpty) {
      return false;
    }
    final goal = ref
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.goal;
    final objective = goal?.normalizedObjective?.toLowerCase() ?? '';
    if (!(goal?.isActive ?? false) ||
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

    for (var index = 0; index < toolResults.length; index++) {
      final result = toolResults[index];
      final name = result.name.trim().toLowerCase();
      if (name == 'write_file' && _isSuccessfulFileMutationToolResult(result)) {
        hasFileCreation = true;
        continue;
      }
      if (name != 'git_execute_command' ||
          !_toolResultHasSuccessfulExit(result)) {
        continue;
      }
      final command = _normalizedGitSubcommand(result);
      if (command == null) {
        continue;
      }
      if (command == 'init') {
        hasInit = true;
      } else if (command.startsWith('add ')) {
        hasAdd = true;
      } else if (command.startsWith('commit ')) {
        hasCommit = true;
      } else if (command == 'revert --no-edit head') {
        hasRevert = true;
        lastRevertIndex = index;
      } else if (command == 'status' || command == 'status --short') {
        if (lastRevertIndex >= 0 && _gitStatusResultIsClean(result)) {
          lastCleanStatusIndex = index;
        }
      }
    }

    return hasInit &&
        hasFileCreation &&
        hasAdd &&
        hasCommit &&
        hasRevert &&
        lastCleanStatusIndex > lastRevertIndex;
  }

  String _buildGitLifecycleCompletionResponse(
    List<ToolResultInfo> toolResults,
  ) {
    final marker = _firstCodingGoalMarker(toolResults);
    final markerText = marker == null ? '' : ' Marker: $marker.';
    return 'The Git lifecycle completed successfully: git init, file creation, '
        'git add, git commit, git revert, and the final git status all '
        'succeeded with a clean working tree.$markerText Goal complete. '
        'Tests passed.';
  }

  String? _normalizedGitSubcommand(ToolResultInfo result) {
    var command = _toolCommandArgument(result.arguments);
    final decoded = _tryDecodeMap(result.result);
    final decodedCommand = decoded?['command'];
    if ((command == null || command.trim().isEmpty) &&
        decodedCommand is String) {
      command = decodedCommand;
    }
    if (command == null) {
      return null;
    }
    var normalized = _normalizeToolCommandForComparison(command);
    if (normalized.startsWith('git ')) {
      normalized = normalized.substring(4).trim();
    }
    return normalized;
  }

  bool _gitStatusResultIsClean(ToolResultInfo result) {
    final decoded = _tryDecodeMap(result.result);
    final stdout = decoded?['stdout']?.toString().trim().toLowerCase() ?? '';
    final stderr = decoded?['stderr']?.toString().trim().toLowerCase() ?? '';
    return stderr.isEmpty &&
        (stdout.isEmpty || stdout.contains('working tree clean'));
  }

  String? _firstCodingGoalMarker(List<ToolResultInfo> toolResults) {
    final markerPattern = RegExp(r'\bCODING_GOAL_[A-Z0-9_]+\b');
    for (final result in toolResults) {
      final candidates = [jsonEncode(result.arguments), result.result];
      for (final candidate in candidates) {
        final match = markerPattern.firstMatch(candidate);
        if (match != null) {
          return match.group(0);
        }
      }
    }
    return null;
  }

  /// Puts a pending git command into state and returns a future that
  /// completes with `true` (approve) or `false` (deny).
  Future<bool> requestGitCommand({
    required String command,
    required String workingDirectory,
    String? reason,
  }) {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingGitCommand: PendingGitCommand(
        id: const Uuid().v4(),
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        completer: completer,
        origin: _activeInteractionOrigin,
      ),
    );
    return completer.future;
  }

  /// Resolves a pending git command dialog from the UI layer.
  void resolveGitCommand({required String id, required bool approved}) {
    final pending = state.pendingGitCommand;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingGitCommand: null);
  }
}
