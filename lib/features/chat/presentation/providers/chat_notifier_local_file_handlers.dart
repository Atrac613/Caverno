// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierLocalFileHandlers on ChatNotifier {
  Future<McpToolResult> _handleWriteFile(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final path = (resolvedArguments['path'] as String?)?.trim() ?? '';
    final content = resolvedArguments['content'] as String? ?? '';
    if (path.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmFileMutations) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: resolvedArguments,
      );
    }

    final preview = await FilesystemTools.buildWriteDiffPreview(
      path: path,
      newContent: content,
    );
    final approved = await requestFileOperation(
      operation: 'Write File',
      path: path,
      preview: preview,
      reason: toolCall.arguments['reason'] as String?,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied file write',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: resolvedArguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      result,
    );
  }

  Future<McpToolResult> _handleEditFile(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final path = (resolvedArguments['path'] as String?)?.trim() ?? '';
    final oldText = resolvedArguments['old_text'] as String? ?? '';
    final newText = resolvedArguments['new_text'] as String? ?? '';
    if (path.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmFileMutations) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: resolvedArguments,
      );
    }

    final preview = await FilesystemTools.buildEditDiffPreview(
      path: path,
      oldText: oldText,
      newText: newText,
      replaceAll: resolvedArguments['replace_all'] as bool? ?? false,
    );

    final approved = await requestFileOperation(
      operation: 'Edit File',
      path: path,
      preview: preview,
      reason: toolCall.arguments['reason'] as String?,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied file edit',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: resolvedArguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      result,
    );
  }

  Future<McpToolResult> _handleRollbackLastFileChange(
    ToolCallInfo toolCall,
  ) async {
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      toolCall.arguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final preview = await _mcpToolService!.previewLastFileRollbackChange();
    if (preview == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'No recent file change is available to roll back',
      );
    }

    if (!_settings.confirmFileMutations) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
    }

    final reason =
        (toolCall.arguments['reason'] as String?)?.trim().isNotEmpty == true
        ? toolCall.arguments['reason'] as String?
        : preview.summary;

    final approved = await requestFileOperation(
      operation: 'Rollback File Change',
      path: preview.path,
      preview: preview.preview,
      reason: reason,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        toolCall.arguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied file rollback',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      toolCall.arguments,
      result,
    );
  }

  Future<McpToolResult> _handleLocalExecuteCommand(
    ToolCallInfo toolCall,
  ) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final command = LocalShellTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
    final workingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    if (command.isEmpty || workingDirectory.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage:
            'command is required and working_directory must be provided or inferred from the selected coding project',
      );
    }

    final localArguments = {
      ...resolvedArguments,
      'command': command,
      'working_directory': workingDirectory,
    };

    final permissionDecision = LocalCommandPermissionService.evaluate(
      command: command,
      workingDirectory: workingDirectory,
      rules: _settings.localCommandPermissionRules,
    );
    final requiresExplicitApproval =
        LocalCommandPermissionService.requiresExplicitApproval(command);
    if (permissionDecision.isDenied) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Local command was denied by a saved permission rule',
      );
    }
    if (permissionDecision.isAllowed && !requiresExplicitApproval) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
      );
    }

    if (LocalShellTools.isReadOnly(command) && !requiresExplicitApproval) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      localArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmLocalCommands && !requiresExplicitApproval) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
      );
    }

    final riskWarning = LocalCommandPermissionService.riskWarningFor(command);
    final approval = await requestLocalCommand(
      command: command,
      workingDirectory: workingDirectory,
      reason: toolCall.arguments['reason'] as String?,
      warningTitle: riskWarning?.title,
      warningMessage: riskWarning?.message,
    );

    if (approval.shouldRemember) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .upsertLocalCommandPermissionRule(
            LocalCommandPermissionService.buildExactRule(
              id: const Uuid().v4(),
              action: approval.rememberedRuleAction!,
              command: command,
              workingDirectory: workingDirectory,
            ).copyWith(match: approval.rememberedRuleMatch!),
          );
    }

    if (!approval.approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        localArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied local command execution',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: localArguments,
    );
    return _rememberToolApprovalResult(toolCall.name, localArguments, result);
  }

  Future<LocalCommandApproval> requestLocalCommand({
    required String command,
    required String workingDirectory,
    String? reason,
    String? warningTitle,
    String? warningMessage,
  }) {
    final completer = Completer<LocalCommandApproval>();
    state = state.copyWith(
      pendingLocalCommand: PendingLocalCommand(
        id: const Uuid().v4(),
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: warningTitle,
        warningMessage: warningMessage,
        completer: completer,
      ),
    );
    return completer.future;
  }

  void resolveLocalCommand({
    required String id,
    required LocalCommandApproval approval,
  }) {
    final pending = state.pendingLocalCommand;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approval);
    }
    state = state.copyWith(pendingLocalCommand: null);
  }

  Future<bool> requestFileOperation({
    required String operation,
    required String path,
    required String preview,
    String? reason,
  }) {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingFileOperation: PendingFileOperation(
        id: const Uuid().v4(),
        operation: operation,
        path: path,
        preview: preview,
        reason: reason,
        completer: completer,
      ),
    );
    return completer.future;
  }

  void resolveFileOperation({required String id, required bool approved}) {
    final pending = state.pendingFileOperation;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingFileOperation: null);
  }
}
