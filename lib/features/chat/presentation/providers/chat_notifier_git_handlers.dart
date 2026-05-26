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

    if (!_settings.confirmGitWrites && !_isRemoteInteraction) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: gitArguments,
      );
    }

    // Write commands require user approval.
    final reason = toolCall.arguments['reason'] as String?;
    final approved = await requestGitCommand(
      command: command,
      workingDirectory: workingDirectory,
      reason: reason,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
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
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: gitArguments,
    );
    return _rememberToolApprovalResult(toolCall.name, gitArguments, result);
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
