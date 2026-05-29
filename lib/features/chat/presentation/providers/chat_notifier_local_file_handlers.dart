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

    if (_hasFullCodingApprovalAccess) {
      return _executeFileMutationToolAndCapture(
        toolName: toolCall.name,
        arguments: resolvedArguments,
        path: path,
      );
    }

    final preview = await FilesystemTools.buildWriteDiffPreview(
      path: path,
      newContent: content,
    );
    final reason = toolCall.arguments['reason'] as String?;
    final autoReviewDecision = await _reviewCodingApproval(
      toolCall: toolCall,
      actionKind: 'write_file',
      arguments: resolvedArguments,
      path: path,
      reason: reason,
      preview: preview,
    );
    if (autoReviewDecision?.isAllowed == true) {
      final result = await _executeFileMutationToolAndCapture(
        toolName: toolCall.name,
        arguments: resolvedArguments,
        path: path,
      );
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        result,
      );
    }
    if (autoReviewDecision != null) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          decision: autoReviewDecision,
        ),
      );
    }

    final approved = await requestFileOperation(
      operation: 'Write File',
      path: path,
      preview: preview,
      reason: reason,
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

    final result = await _executeFileMutationToolAndCapture(
      toolName: toolCall.name,
      arguments: resolvedArguments,
      path: path,
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

    if (_hasFullCodingApprovalAccess) {
      return _executeFileMutationToolAndCapture(
        toolName: toolCall.name,
        arguments: resolvedArguments,
        path: path,
      );
    }

    final preview = await FilesystemTools.buildEditDiffPreview(
      path: path,
      oldText: oldText,
      newText: newText,
      replaceAll: resolvedArguments['replace_all'] as bool? ?? false,
    );
    final reason = toolCall.arguments['reason'] as String?;
    final autoReviewDecision = await _reviewCodingApproval(
      toolCall: toolCall,
      actionKind: 'edit_file',
      arguments: resolvedArguments,
      path: path,
      reason: reason,
      preview: preview,
    );
    if (autoReviewDecision?.isAllowed == true) {
      final result = await _executeFileMutationToolAndCapture(
        toolName: toolCall.name,
        arguments: resolvedArguments,
        path: path,
      );
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        result,
      );
    }
    if (autoReviewDecision != null) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          decision: autoReviewDecision,
        ),
      );
    }

    final approved = await requestFileOperation(
      operation: 'Edit File',
      path: path,
      preview: preview,
      reason: reason,
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

    final result = await _executeFileMutationToolAndCapture(
      toolName: toolCall.name,
      arguments: resolvedArguments,
      path: path,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      result,
    );
  }

  Future<McpToolResult> _executeFileMutationToolAndCapture({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String path,
  }) async {
    final before = await FilesystemTools.captureTextSnapshot(path);
    final result = await _mcpToolService!.executeTool(
      name: toolName,
      arguments: arguments,
    );
    if (_isSuccessfulFileMutationResult(result)) {
      await _recordFileMutationDiff(before: before, path: path);
    }
    return result;
  }

  bool _isSuccessfulFileMutationResult(McpToolResult result) {
    if (!result.isSuccess) {
      return false;
    }
    try {
      final decoded = jsonDecode(result.result);
      return decoded is! Map<String, dynamic> || decoded['error'] == null;
    } catch (_) {
      return true;
    }
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

    if (_hasFullCodingApprovalAccess) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
    }

    final reason =
        (toolCall.arguments['reason'] as String?)?.trim().isNotEmpty == true
        ? toolCall.arguments['reason'] as String?
        : preview.summary;

    final autoReviewDecision = await _reviewCodingApproval(
      toolCall: toolCall,
      actionKind: 'rollback_last_file_change',
      arguments: toolCall.arguments,
      path: preview.path,
      reason: reason,
      preview: preview.preview,
    );
    if (autoReviewDecision?.isAllowed == true) {
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
    if (autoReviewDecision != null) {
      return _rememberToolApprovalResult(
        toolCall.name,
        toolCall.arguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          decision: autoReviewDecision,
        ),
      );
    }

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
    if (!_isRemoteInteraction &&
        permissionDecision.isAllowed &&
        !requiresExplicitApproval) {
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

    if (_hasFullCodingApprovalAccess) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
      );
    }

    final riskWarning = LocalCommandPermissionService.riskWarningFor(command);
    final reason = toolCall.arguments['reason'] as String?;
    final autoReviewDecision = await _reviewCodingApproval(
      toolCall: toolCall,
      actionKind: 'local_execute_command',
      arguments: localArguments,
      workingDirectory: workingDirectory,
      reason: reason,
      warningTitle: riskWarning?.title,
      warningMessage: riskWarning?.message,
    );
    if (autoReviewDecision?.isAllowed == true) {
      final result = await _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
      );
      return _rememberToolApprovalResult(toolCall.name, localArguments, result);
    }
    if (autoReviewDecision != null) {
      return _rememberToolApprovalResult(
        toolCall.name,
        localArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          decision: autoReviewDecision,
        ),
      );
    }

    final approval = await requestLocalCommand(
      command: command,
      workingDirectory: workingDirectory,
      reason: reason,
      warningTitle: riskWarning?.title,
      warningMessage: riskWarning?.message,
    );

    if (approval.shouldRemember && !_isRemoteInteraction) {
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
        origin: _activeInteractionOrigin,
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
        origin: _activeInteractionOrigin,
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
