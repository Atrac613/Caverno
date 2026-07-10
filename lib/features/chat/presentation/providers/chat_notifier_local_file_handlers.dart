// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierLocalFileHandlers on ChatNotifier {
  Future<McpToolResult> _handleLspGoToDefinition(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final projectRoot = _getActiveProjectRootPath();
    if (projectRoot == null || projectRoot.trim().isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': 'active_coding_project_required',
          'error':
              'An active coding project is required for LSP go-to-definition.',
        }),
        isSuccess: false,
        errorMessage: 'An active coding project is required',
      );
    }

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final path = (resolvedArguments['path'] as String?)?.trim() ?? '';
    final line = _oneBasedPositionValue(resolvedArguments['line']);
    final column = _oneBasedPositionValue(resolvedArguments['column']);
    if (path.isEmpty || line == null || column == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': 'invalid_arguments',
          'error': 'path, line, and column are required.',
        }),
        isSuccess: false,
        errorMessage: 'path, line, and column are required',
      );
    }

    try {
      final definitions = await ref
          .read(lspJsonRpcSessionRegistryProvider)
          .collectDefinitions(
            projectRoot: projectRoot,
            path: path,
            line: line - 1,
            character: column - 1,
          );
      if (definitions == null) {
        return McpToolResult(
          toolName: toolCall.name,
          result: jsonEncode({
            'ok': false,
            'code': 'language_server_unavailable',
            'error':
                'No supported language server session is available for this file.',
            'path': path,
          }),
          isSuccess: false,
          errorMessage: 'No supported language server session is available',
        );
      }

      final payload = {
        'ok': true,
        'provider': 'lsp_json_rpc',
        'path': path,
        'line': line,
        'column': column,
        'definition_count': definitions.length,
        'definitions': definitions
            .map(
              (definition) =>
                  _lspDefinitionToJson(definition, projectRoot: projectRoot),
            )
            .toList(growable: false),
      };
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode(payload),
        isSuccess: true,
      );
    } catch (error, stackTrace) {
      appLog('[LSP] Go-to-definition failed: $error');
      appLog('[LSP] stackTrace: $stackTrace');
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': 'lsp_go_to_definition_failed',
          'error': error.toString(),
          'path': path,
        }),
        isSuccess: false,
        errorMessage: error.toString(),
      );
    }
  }

  int? _oneBasedPositionValue(Object? value) {
    final rawValue = switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (rawValue == null || rawValue < 1) {
      return null;
    }
    return rawValue;
  }

  Map<String, dynamic> _lspDefinitionToJson(
    LspDefinitionLocation definition, {
    required String projectRoot,
  }) {
    final absolutePath = _pathFromLspUri(definition.uri);
    final insideProject =
        absolutePath != null &&
        DartProjectPath.isInsideRoot(absolutePath, projectRoot);
    return {
      'uri': definition.uri,
      'path': ?absolutePath,
      if (insideProject)
        'relative_path': DartProjectPath.relativePath(
          absolutePath,
          projectRoot,
        ).replaceAll('\\', '/'),
      'line': definition.startLine + 1,
      'column': definition.startCharacter + 1,
      if (definition.endLine != null) 'end_line': definition.endLine! + 1,
      if (definition.endCharacter != null)
        'end_column': definition.endCharacter! + 1,
    };
  }

  String? _pathFromLspUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.scheme == 'file') {
        return parsed.toFilePath();
      }
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
    return null;
  }

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

    final approvalStateFingerprint =
        await FilesystemTools.textSnapshotFingerprint(path);

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      stateFingerprint: approvalStateFingerprint,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final reason = toolCall.arguments['reason'] as String?;
    String? previewCache;
    Future<String> ensurePreview() async =>
        previewCache ??= await FilesystemTools.buildWriteDiffPreview(
          path: path,
          newContent: content,
        );

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'write_file',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: resolvedArguments,
      approvalCacheStateFingerprint: approvalStateFingerprint,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'write_file',
        arguments: resolvedArguments,
        path: path,
        reason: reason,
        preview: await ensurePreview(),
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        resolvedArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
        stateFingerprint: approvalStateFingerprint,
      );
    }
    if (gate.needsManual) {
      final approved = await requestFileOperation(
        operation: 'Write File',
        path: path,
        preview: await ensurePreview(),
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          resolvedArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied file write',
          ),
          stateFingerprint: approvalStateFingerprint,
        );
      }
    }

    if (!gate.bypassedApproval) {
      final changedResult = await _fileChangedSinceApprovalResult(
        toolName: toolCall.name,
        path: path,
        approvedStateFingerprint: approvalStateFingerprint,
      );
      if (changedResult != null) {
        return changedResult;
      }
    }

    final result = await _executeFileMutationToolAndCapture(
      toolName: toolCall.name,
      arguments: resolvedArguments,
      path: path,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(
            toolCall.name,
            resolvedArguments,
            result,
            stateFingerprint: approvalStateFingerprint,
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

    final preflightResult = await FilesystemTools.preflightEditFile(
      path: path,
      oldText: oldText,
      newText: newText,
      replaceAll: resolvedArguments['replace_all'] as bool? ?? false,
    );
    if (preflightResult != null) {
      final decoded = _tryDecodeMap(preflightResult);
      final error = decoded?['error']?.toString();
      return McpToolResult(
        toolName: toolCall.name,
        result: preflightResult,
        isSuccess: error == null,
        errorMessage: error,
      );
    }

    final approvalStateFingerprint =
        await FilesystemTools.textSnapshotFingerprint(path);

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      stateFingerprint: approvalStateFingerprint,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final reason = toolCall.arguments['reason'] as String?;
    String? previewCache;
    Future<String> ensurePreview() async =>
        previewCache ??= await FilesystemTools.buildEditDiffPreview(
          path: path,
          oldText: oldText,
          newText: newText,
          replaceAll: resolvedArguments['replace_all'] as bool? ?? false,
        );

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'edit_file',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: resolvedArguments,
      approvalCacheStateFingerprint: approvalStateFingerprint,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'edit_file',
        arguments: resolvedArguments,
        path: path,
        reason: reason,
        preview: await ensurePreview(),
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        resolvedArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
        stateFingerprint: approvalStateFingerprint,
      );
    }
    if (gate.needsManual) {
      final approved = await requestFileOperation(
        operation: 'Edit File',
        path: path,
        preview: await ensurePreview(),
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          resolvedArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied file edit',
          ),
          stateFingerprint: approvalStateFingerprint,
        );
      }
    }

    if (!gate.bypassedApproval) {
      final changedResult = await _fileChangedSinceApprovalResult(
        toolName: toolCall.name,
        path: path,
        approvedStateFingerprint: approvalStateFingerprint,
      );
      if (changedResult != null) {
        return changedResult;
      }
    }

    final result = await _executeFileMutationToolAndCapture(
      toolName: toolCall.name,
      arguments: resolvedArguments,
      path: path,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(
            toolCall.name,
            resolvedArguments,
            result,
            stateFingerprint: approvalStateFingerprint,
          );
  }

  Future<McpToolResult?> _fileChangedSinceApprovalResult({
    required String toolName,
    required String path,
    required String approvedStateFingerprint,
  }) async {
    final currentFingerprint = await FilesystemTools.textSnapshotFingerprint(
      path,
    );
    if (currentFingerprint == approvedStateFingerprint) {
      return null;
    }
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'file_changed_since_approval',
        'error':
            'The target file changed after the approval preview was prepared. Re-read the file and submit a fresh mutation.',
        'path': path,
      }),
      isSuccess: false,
      errorMessage: 'The target file changed after approval',
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
      return decoded is! Map<String, dynamic> ||
          (decoded['error'] == null && decoded['already_applied'] != true);
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

    final reason =
        (toolCall.arguments['reason'] as String?)?.trim().isNotEmpty == true
        ? toolCall.arguments['reason'] as String?
        : preview.summary;

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'rollback_last_file_change',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: toolCall.arguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'rollback_last_file_change',
        arguments: toolCall.arguments,
        path: preview.path,
        reason: reason,
        preview: preview.preview,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        toolCall.arguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approved = await requestFileOperation(
        operation: 'Rollback File Change',
        path: preview.path,
        preview: preview.preview,
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
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
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(
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

    final riskWarning = LocalCommandPermissionService.riskWarningFor(command);
    final reason = toolCall.arguments['reason'] as String?;

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'local_execute_command',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: localArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'local_execute_command',
        arguments: localArguments,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: riskWarning?.title,
        warningMessage: riskWarning?.message,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        localArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approval = await requestLocalCommand(
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: _escalatedApprovalWarningTitle(gate, riskWarning?.title),
        warningMessage: _escalatedApprovalWarningMessage(
          gate,
          riskWarning?.message,
        ),
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
        return _rememberToolApprovalDenial(
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
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: localArguments,
    );
    // Full access never caches, so the model can re-run a command (e.g. re-run
    // tests after an edit); approvals cache to avoid re-prompting.
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, localArguments, result);
  }

  Future<McpToolResult> _handleProcessStart(ToolCallInfo toolCall) async {
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

    final riskWarning = LocalCommandPermissionService.riskWarningFor(command);
    final reason = toolCall.arguments['reason'] as String?;
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'process_start',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: localArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'process_start',
        arguments: localArguments,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: riskWarning?.title,
        warningMessage: riskWarning?.message,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        localArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approval = await requestLocalCommand(
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: _escalatedApprovalWarningTitle(gate, riskWarning?.title),
        warningMessage: _escalatedApprovalWarningMessage(
          gate,
          riskWarning?.message,
        ),
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
        return _rememberToolApprovalDenial(
          toolCall.name,
          localArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied background process start',
          ),
        );
      }
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: localArguments,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, localArguments, result);
  }

  Future<McpToolResult> _handleProcessCancel(ToolCallInfo toolCall) async {
    final jobId = toolCall.arguments['job_id']?.toString().trim() ?? '';
    if (jobId.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': 'job_id_required',
          'error': 'job_id is required',
        }),
        isSuccess: false,
        errorMessage: 'job_id is required',
      );
    }
    final workingDirectory = _getActiveProjectRootPath()?.trim() ?? '.';
    final localArguments = {'job_id': jobId};
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      localArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'process_cancel',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: localArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'process_cancel',
        arguments: localArguments,
        workingDirectory: workingDirectory,
        reason: 'Cancel background process $jobId',
        warningTitle: 'Cancel background process?',
        warningMessage:
            'This stops a running local command and may leave partial side effects.',
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        localArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approval = await requestLocalCommand(
        command: 'process_cancel $jobId',
        workingDirectory: workingDirectory,
        reason: 'Cancel background process $jobId',
        warningTitle: 'Cancel background process?',
        warningMessage:
            'This stops a running local command and may leave partial side effects.',
      );
      if (!approval.approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          localArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied background process cancellation',
          ),
        );
      }
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: localArguments,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, localArguments, result);
  }

  Future<McpToolResult> _handleRunTests(ToolCallInfo toolCall) async {
    final projectRoot = _normalizeRunTestsAbsolutePath(
      _getActiveProjectRootPath()?.trim() ?? '',
    );
    if (projectRoot.isEmpty) {
      return _buildRunTestsError(
        toolCall,
        code: 'project_required',
        message: 'run_tests requires a selected coding project',
      );
    }

    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final rawWorkingDirectory =
        (toolCall.arguments['working_directory'] as String?)?.trim() ??
        (toolCall.arguments['cwd'] as String?)?.trim() ??
        '';
    final hasExplicitWorkingDirectory = rawWorkingDirectory.isNotEmpty;
    var workingDirectory = _normalizeRunTestsAbsolutePath(
      FilesystemTools.resolvePath(
            rawWorkingDirectory,
            defaultRoot: projectRoot,
          ) ??
          projectRoot,
    );
    if (workingDirectory.isEmpty ||
        !DartProjectPath.isInsideRoot(workingDirectory, projectRoot)) {
      return _buildRunTestsError(
        toolCall,
        code: 'working_directory_outside_project',
        message:
            'working_directory must resolve inside the selected coding project',
      );
    }

    final rawTestPath = _runTestsPathArgument(toolCall.arguments);
    if (!hasExplicitWorkingDirectory && rawTestPath != null) {
      final inferredWorkingDirectory =
          DartProjectTooling.inferPackageRootForTestPath(
            projectRoot: projectRoot,
            workingDirectory: workingDirectory,
            testPath: rawTestPath,
          );
      if (inferredWorkingDirectory != null &&
          DartProjectPath.isInsideRoot(inferredWorkingDirectory, projectRoot)) {
        workingDirectory = _normalizeRunTestsAbsolutePath(
          inferredWorkingDirectory,
        );
      }
    }

    String? commandTestPath;
    if (rawTestPath != null) {
      final normalizedRawTestPath = _normalizeRunTestsPathForWorkingDirectory(
        rawTestPath,
        projectRoot: projectRoot,
        workingDirectory: workingDirectory,
      );
      final resolvedTestPath = _normalizeRunTestsAbsolutePath(
        FilesystemTools.resolvePath(
              normalizedRawTestPath,
              defaultRoot: workingDirectory,
            ) ??
            '',
      );
      if (resolvedTestPath.isEmpty ||
          !DartProjectPath.isInsideRoot(resolvedTestPath, projectRoot)) {
        return _buildRunTestsError(
          toolCall,
          code: 'test_path_outside_project',
          message: 'test_path must resolve inside the selected coding project',
        );
      }
      commandTestPath =
          DartProjectPath.isInsideRoot(resolvedTestPath, workingDirectory)
          ? DartProjectPath.relativePath(resolvedTestPath, workingDirectory)
          : resolvedTestPath;
    }

    final runner = _normalizeRunTestsRunner(toolCall.arguments['runner']);
    if (runner == null) {
      return _buildRunTestsError(
        toolCall,
        code: 'unsupported_runner',
        message: 'runner must be one of auto, flutter, or dart',
      );
    }

    final command = _buildRunTestsCommand(
      runner: runner,
      projectRoot: projectRoot,
      workingDirectory: workingDirectory,
      testPath: commandTestPath,
    );
    final reason = toolCall.arguments['reason']?.toString().trim();
    final localArguments = <String, dynamic>{
      'command': command,
      'working_directory': workingDirectory,
      'reason': reason == null || reason.isEmpty
          ? 'Run scoped test validation'
          : reason,
      'test_path': ?rawTestPath,
      if (runner != 'auto') 'runner': runner,
    };

    final result = await _handleLocalExecuteCommand(
      ToolCallInfo(
        id: toolCall.id,
        name: 'local_execute_command',
        arguments: localArguments,
      ),
    );
    return result.copyWith(toolName: toolCall.name);
  }

  McpToolResult _buildRunTestsError(
    ToolCallInfo toolCall, {
    required String code,
    required String message,
  }) {
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({'code': code, 'error': message}),
      isSuccess: false,
      errorMessage: message,
    );
  }

  String? _normalizeRunTestsRunner(Object? rawRunner) {
    final runner = rawRunner?.toString().trim().toLowerCase();
    if (runner == null || runner.isEmpty || runner == 'auto') {
      return 'auto';
    }
    if (runner == 'flutter' || runner == 'dart') {
      return runner;
    }
    return null;
  }

  String _buildRunTestsCommand({
    required String runner,
    required String projectRoot,
    required String workingDirectory,
    String? testPath,
  }) {
    final effectiveRunner = runner == 'auto'
        ? _inferRunTestsRunner(
            projectRoot: projectRoot,
            workingDirectory: workingDirectory,
          )
        : runner;
    final hasFvmMetadata = DartProjectTooling.hasFvmMetadata(
      packageRoot: workingDirectory,
      projectRoot: projectRoot,
    );
    final executable = switch (effectiveRunner) {
      'dart' => hasFvmMetadata ? 'fvm dart' : 'dart',
      _ => hasFvmMetadata ? 'fvm flutter' : 'flutter',
    };
    final parts = <String>[executable, 'test'];
    if (testPath != null && testPath.trim().isNotEmpty) {
      parts.add(_shellQuoteRunTestsArgument(testPath.trim()));
    }
    return parts.join(' ');
  }

  String _inferRunTestsRunner({
    required String projectRoot,
    required String workingDirectory,
  }) {
    return DartProjectTooling.isFlutterPackage(workingDirectory) ||
            DartProjectTooling.isFlutterPackage(projectRoot)
        ? 'flutter'
        : 'dart';
  }

  String _normalizeRunTestsPathForWorkingDirectory(
    String rawTestPath, {
    required String projectRoot,
    required String workingDirectory,
  }) {
    final trimmed = rawTestPath.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
      return trimmed;
    }

    final workingDirectoryFromProject = DartProjectPath.relativePath(
      workingDirectory,
      projectRoot,
    ).replaceAll('\\', '/');
    if (workingDirectoryFromProject.isEmpty ||
        workingDirectoryFromProject == '.') {
      return trimmed;
    }

    final normalizedTestPath = trimmed.replaceAll('\\', '/');
    if (normalizedTestPath == workingDirectoryFromProject) {
      return '.';
    }
    final workingDirectoryPrefix = '$workingDirectoryFromProject/';
    if (normalizedTestPath.startsWith(workingDirectoryPrefix)) {
      final stripped = normalizedTestPath.substring(
        workingDirectoryPrefix.length,
      );
      return stripped.isEmpty ? '.' : stripped;
    }
    return trimmed;
  }

  String _shellQuoteRunTestsArgument(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _normalizeRunTestsAbsolutePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      return Uri.file(trimmed).normalizePath().toFilePath();
    } catch (_) {
      return trimmed;
    }
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
