// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

final _localCommandExecutionAuthorities =
    Expando<LocalCommandExecutionAuthority>();

extension ChatNotifierLocalFileHandlers on ChatNotifier {
  LocalCommandExecutionAuthority get _localCommandExecutionAuthority =>
      _localCommandExecutionAuthorities[this] ??=
          LocalCommandExecutionAuthority();

  FileMutationToolRuntimeAdapter<TextFileSnapshot>
  _buildFileMutationRuntimeAdapter() {
    final cacheRuntime = FileMutationApprovalCacheRuntimeAdapter(
      ownerIsCurrent: _isApprovalOwnerCurrent,
      cacheForOwner: _toolApprovalCache.forOwner,
    );
    return FileMutationToolRuntimeAdapter<TextFileSnapshot>(
      acknowledgeLifecycle: cacheRuntime.acknowledgeLifecycle,
      preflightEdit: (request) async {
        final operation = request.operation;
        final value = await FilesystemTools.preflightEditFile(
          path: operation.path,
          oldText: operation.oldText,
          newText: operation.newText,
          replaceAll: operation.replaceAll,
        );
        return cacheRuntime.acknowledge(
          request.identity,
          current: _isApprovalOwnerCurrent(request.identity.owner),
          value: value,
        );
      },
      fingerprint: (identity) async {
        final service = _mcpToolService;
        if (service == null) {
          return cacheRuntime.acknowledge(identity, current: false);
        }
        return service.readFileMutationFingerprint(identity);
      },
      isRegularFile: (identity) async {
        final type = await FileSystemEntity.type(
          identity.canonicalPath,
          followLinks: false,
        );
        return cacheRuntime.acknowledge(
          identity,
          current: _isApprovalOwnerCurrent(identity.owner),
          value: type == FileSystemEntityType.file,
        );
      },
      captureDeleteSnapshot: (identity) async {
        final snapshot = await FilesystemTools.captureTextSnapshot(
          identity.canonicalPath,
        );
        return cacheRuntime.acknowledge(
          identity,
          current: _isApprovalOwnerCurrent(identity.owner),
          value: FileMutationDeleteSnapshot(
            content: snapshot.content,
            error: snapshot.error,
          ),
        );
      },
      buildPreview: (request) async {
        final operation = request.operationRequest.operation;
        final preview = await switch (operation.kind) {
          FileMutationKind.writeFile => FilesystemTools.buildWriteDiffPreview(
            path: operation.path,
            newContent: operation.content,
          ),
          FileMutationKind.editFile => FilesystemTools.buildEditDiffPreview(
            path: operation.path,
            oldText: operation.oldText,
            newText: operation.newText,
            replaceAll: operation.replaceAll,
          ),
          FileMutationKind.deleteFile => Future<String>.value(
            FilesystemTools.buildUnifiedDiff(
              path: operation.path,
              oldContent: request.deleteContent,
              newContent: null,
            ),
          ),
        };
        return cacheRuntime.acknowledge(
          request.identity,
          current: _isApprovalOwnerCurrent(request.identity.owner),
          value: preview,
        );
      },
      lookupDenial: cacheRuntime.lookupDenial,
      resolveGate: (request, {required buildPreview}) async {
        final identity = request.identity;
        final cache = cacheRuntime.currentCache(identity.owner);
        if (cache == null) {
          return cacheRuntime.acknowledge(identity, current: false);
        }
        final approval = request.request;
        final toolCall = ToolCallInfo(
          id: identity.toolCallId,
          name: identity.toolName,
          arguments: approval.arguments,
        );
        final gate = await _resolveToolApprovalGate(
          cache,
          toolCall: toolCall,
          actionKind: identity.toolName,
          mode: approval.approvalMode,
          reviewDomain: ToolApprovalAutoReviewDomain.coding,
          fullAccessEligible: true,
          approvalCacheArguments: approval.cacheArguments,
          approvalCacheStateFingerprint: approval.stateFingerprint,
          buildReviewRequest: () async => _buildAutoReviewRequest(
            identity.owner,
            toolCall: toolCall,
            actionKind: identity.toolName,
            arguments: approval.arguments,
            path: approval.path,
            reason: approval.reason,
            preview: await buildPreview(),
            conversationMessages: approval.conversationMessages,
          ),
        );
        return cacheRuntime.acknowledge(
          identity,
          current: _isApprovalOwnerCurrent(identity.owner),
          value: gate,
        );
      },
      requestManualApproval: (request, {required preview}) async {
        final identity = request.identity;
        final approval = request.request;
        final approved = await requestFileOperation(
          owner: identity.owner,
          operation: approval.operation.kind.approvalTitle,
          path: approval.path,
          preview: preview,
          reason: approval.reason,
        );
        return cacheRuntime.acknowledge(
          identity,
          current: _isApprovalOwnerCurrent(identity.owner),
          value: approved,
        );
      },
      rememberDenial: cacheRuntime.rememberDenial,
      rememberResult: cacheRuntime.rememberResult,
      captureBefore: (identity) async {
        final service = _mcpToolService;
        if (service == null) {
          return cacheRuntime.acknowledge(identity, current: false);
        }
        return service.captureFileMutationBefore(identity);
      },
      recordMutation: (request) async {
        final service = _mcpToolService;
        if (service == null) {
          return cacheRuntime.acknowledge(request.identity, current: false);
        }
        final acknowledgement = await service.recordFileMutation(request);
        if (acknowledgement.disposition ==
                FileMutationRuntimeAcknowledgementDisposition.completed &&
            acknowledgement.value != null) {
          await _recordFileMutationDiff(
            owner: request.identity.owner,
            before: request.capture.snapshot,
            path: request.identity.canonicalPath,
          );
        }
        return acknowledgement;
      },
      execute: (request, authorization) {
        final service = _mcpToolService;
        if (service == null) {
          throw StateError('The filesystem tool service is unavailable.');
        }
        return service.executeRawFileMutation(request, authorization);
      },
      compensate: (request) {
        final service = _mcpToolService;
        if (service == null) {
          throw StateError('The filesystem tool service is unavailable.');
        }
        return service.compensateFileMutation(request);
      },
    );
  }

  Future<McpToolResult> _handleFileMutation(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;
    final owner = approvalCache.owner;
    final projectRoot = _projectRootForGeneration(owner.interactionGeneration);
    final resolvedArguments = ProjectScopedToolArgumentResolver.resolve(
      toolName: toolCall.name,
      arguments: toolCall.arguments,
      loadProjectRoot: () => projectRoot,
    );
    final ownerMessages = _activeResponseRegistry.messagesForOwner(owner);
    if (ownerMessages == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final completion = await _fileMutationRuntime.handle(
      owner: owner,
      toolCall: toolCall,
      approvalMode: _settings.codingApprovalMode,
      projectRoot: projectRoot,
      resolvedArguments: resolvedArguments,
      conversationMessages: ownerMessages,
      hasUntrustedInfluence: _conversationTaintState.hasUntrustedInfluence(
        owner: owner,
      ),
    );
    return completion.result;
  }

  Future<void> _recordFileMutationDiff({
    required ChatTurnOwner owner,
    required TextFileSnapshot before,
    required String path,
  }) async {
    if (_activeTurnUserPrompt == null || !_isApprovalOwnerCurrent(owner)) {
      return;
    }

    final after = await FilesystemTools.captureTextSnapshot(path);
    final filePath = after.path.trim().isNotEmpty ? after.path : before.path;
    final beforeError = before.error?.trim();
    final afterError = after.error?.trim();
    final unavailable =
        beforeError?.isNotEmpty == true || afterError?.isNotEmpty == true;

    final TurnDiffFile? file;
    if (unavailable) {
      file = TurnDiffFile(
        filePath: filePath,
        isNewFile: !before.exists && after.exists,
        isDeletedFile: before.exists && !after.exists,
        isBinary:
            _snapshotErrorSuggestsBinary(beforeError) ||
            _snapshotErrorSuggestsBinary(afterError),
        isLargeFile: false,
        note: [
          if (beforeError?.isNotEmpty == true) beforeError!,
          if (afterError?.isNotEmpty == true) afterError!,
        ].join('\n'),
      );
    } else {
      file = TurnDiffService.buildFileDiff(
        filePath: filePath,
        oldContent: before.exists ? before.content : null,
        newContent: after.exists ? after.content : null,
        oldExists: before.exists,
        newExists: after.exists,
      )?.file;
    }

    if (file == null || !file.hasChanges || !_isApprovalOwnerCurrent(owner)) {
      return;
    }
    _pendingTurnDiffFiles.add(file);
  }

  bool _snapshotErrorSuggestsBinary(String? error) {
    final lower = error?.toLowerCase() ?? '';
    return lower.contains('binary') || lower.contains('utf-8');
  }

  Future<McpToolResult> _handleRollbackLastFileChange(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final request = FileRollbackToolRequest(
      owner: approvalCache.owner,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      arguments: toolCall.arguments,
    );
    return _mcpToolService!.executeExactFileRollback(
      request: request,
      lookupDenial: (candidate) =>
          approvalCache.lookupDenial(candidate.toolName, candidate.arguments),
      resolveGate: (approvalRequest) {
        final exactToolCall = ToolCallInfo(
          id: approvalRequest.identity.toolCallId,
          name: approvalRequest.identity.toolName,
          arguments: approvalRequest.toolRequest.arguments,
        );
        return _resolveToolApprovalGate(
          approvalCache,
          toolCall: exactToolCall,
          actionKind: 'rollback_last_file_change',
          mode: _settings.codingApprovalMode,
          reviewDomain: ToolApprovalAutoReviewDomain.coding,
          fullAccessEligible: true,
          approvalCacheArguments: approvalRequest.toolRequest.arguments,
          approvalCacheStateFingerprint: approvalRequest.checkpointToken,
          buildReviewRequest: () async => _buildAutoReviewRequest(
            approvalRequest.identity.owner,
            toolCall: exactToolCall,
            actionKind: 'rollback_last_file_change',
            arguments: approvalRequest.toolRequest.arguments,
            path: approvalRequest.target.path,
            reason: approvalRequest.reason,
            preview: approvalRequest.target.preview,
          ),
        );
      },
      requestManualApproval: (approvalRequest) => requestFileOperation(
        owner: approvalRequest.identity.owner,
        operation: 'Rollback File Change',
        path: approvalRequest.target.path,
        preview: approvalRequest.target.preview,
        reason: approvalRequest.reason,
      ),
      ownerIsCurrent: (identity) => _isApprovalOwnerCurrent(identity.owner),
      rememberDenial: (approvalRequest, result) {
        approvalCache.rememberDenial(
          approvalRequest.identity.toolName,
          approvalRequest.toolRequest.arguments,
          result,
        );
      },
      rememberResult: (approvalRequest, result) {
        approvalCache.rememberResult(
          approvalRequest.identity.toolName,
          approvalRequest.toolRequest.arguments,
          result,
          stateFingerprint: approvalRequest.checkpointToken,
        );
      },
    );
  }

  Future<McpToolResult> _handleLocalExecuteCommand(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;
    final owner = approvalCache.owner;
    final snapshot = _activeResponseRegistry.snapshotForOwner(owner);
    if (snapshot == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    // The shell layer rejects embedded git writes unconditionally, so asking
    // for approval first spends an auto-review round trip on a call that can
    // never run. Decide it here, where the answer is already known.
    final gitWriteBlocked = LocalShellGitWriteGuard.evaluate(
      toolName: toolCall.name,
      arguments: toolCall.arguments,
    );
    if (gitWriteBlocked != null) return gitWriteBlocked;
    final approvalMode = _settings.codingApprovalMode;
    final approvalPort = CallbackLocalCommandApprovalPort(
      ownerIsCurrent: (candidate) =>
          candidate == owner && _isApprovalOwnerCurrent(candidate),
      lookupDenial: (_, request) => approvalCache.lookupDenial(
        request.execution.toolName,
        request.execution.arguments,
      ),
      resolveGate: (candidate, request) {
        final call = ToolCallInfo(
          id: request.toolCallId,
          name: request.execution.toolName,
          arguments: request.execution.arguments,
        );
        return _resolveToolApprovalGate(
          approvalCache,
          toolCall: call,
          actionKind: 'local_execute_command',
          mode: approvalMode,
          reviewDomain: ToolApprovalAutoReviewDomain.coding,
          fullAccessEligible: true,
          requiredManualDecision: request.requiredManualDecision,
          requiredManualDecisionSource:
              request.requiredManualDecisionSource ?? 'required_manual',
          approvalCacheArguments: request.execution.arguments,
          buildReviewRequest: () async => _buildAutoReviewRequest(
            candidate,
            toolCall: call,
            actionKind: 'local_execute_command',
            arguments: request.execution.arguments,
            workingDirectory: request.execution.workingDirectory,
            reason: request.reason,
            warningTitle: request.warningTitle,
            warningMessage: request.warningMessage,
            outOfRootPaths: request.outOfRootPaths,
          ),
        );
      },
      requestManualApproval: (candidate, request, gate) async {
        final approval = await requestLocalCommand(
          owner: candidate,
          command: request.execution.command,
          workingDirectory: request.execution.workingDirectory,
          reason: request.reason,
          warningTitle: _escalatedApprovalWarningTitle(
            gate,
            request.warningTitle,
          ),
          warningMessage: _escalatedApprovalWarningMessage(
            gate,
            request.warningMessage,
          ),
        );
        return LocalCommandManualApproval(
          approved: approval.approved,
          rememberedAction: switch (approval.rememberedRuleAction) {
            LocalCommandPermissionAction.allow =>
              RememberedCommandPermissionAction.allow,
            LocalCommandPermissionAction.deny =>
              RememberedCommandPermissionAction.deny,
            _ => null,
          },
          rememberedMatch: switch (approval.rememberedRuleMatch) {
            LocalCommandPermissionMatch.exact =>
              RememberedCommandPermissionMatch.exact,
            LocalCommandPermissionMatch.prefix =>
              RememberedCommandPermissionMatch.prefix,
            _ => null,
          },
        );
      },
      rememberDenial: (_, request, result) => approvalCache.rememberDenial(
        request.execution.toolName,
        request.execution.arguments,
        result,
      ),
      rememberResult: (_, request, result) => approvalCache.rememberResult(
        request.execution.toolName,
        request.execution.arguments,
        result,
      ),
    );
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final executionPort = LocalCommandToolRuntimeAdapter(
      runtimePort: CallbackLocalCommandRuntimePort(
        acknowledgeOwner: (identity) =>
            identity.owner == owner && _isApprovalOwnerCurrent(identity.owner)
            ? LocalCommandRuntimeOwnerAcknowledgement.current(
                identity: identity,
              )
            : LocalCommandRuntimeOwnerAcknowledgement.ownerExpired(
                identity: identity,
              ),
        execute: (operation) => operation.runEffect(() async {
          final result = await _mcpToolService!.executeProcessTool(
            owner: operation.identity.owner,
            name: operation.identity.toolName,
            arguments: operation.arguments,
          );
          return LocalCommandRuntimeExecutionAcknowledgement.completed(
            identity: operation.identity,
            result: result,
          );
        }),
      ),
      executionAuthority: _localCommandExecutionAuthority,
    );
    final projectRoot = snapshot.projectRoot ?? '';
    return LocalCommandToolHandler(
      executionPort: executionPort,
      approvalPort: approvalPort,
      permissionRuleStorePort: LocalCommandPermissionRuleRuntimeAdapter(
        owner: owner,
        rules: _settings.localCommandPermissionRules,
        ownerIsCurrent: _isApprovalOwnerCurrent,
        upsert: settingsNotifier.upsertLocalCommandPermissionRule,
        remove: settingsNotifier.removeLocalCommandPermissionRule,
      ),
    ).handle(
      LocalCommandToolRequest(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        allowedWorkingDirectoryRoot: projectRoot,
        defaultWorkingDirectory: projectRoot,
        arguments: toolCall.arguments,
        isRemoteInteraction:
            snapshot.sessionLogContext.phase == 'remote_interaction',
      ),
    );
  }

  /// Read-only job observation: no approval, no path — the owner scopes it.
  Future<McpToolResult> _handleProcessObservation(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) => _mcpToolService!.executeProcessTool(
    owner: approvalCache.owner,
    name: toolCall.name,
    arguments: toolCall.arguments,
  );

  Future<McpToolResult> _handleProcessStart(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
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
      'allowed_read_root': _getActiveProjectRootPath() ?? '',
    };

    final permissionDecision = LocalCommandPermissionService.evaluate(
      command: command,
      workingDirectory: workingDirectory,
      rules: _settings.localCommandPermissionRules,
    );
    final approvalScope = LocalCommandApprovalScope.of(
      command: command,
      projectRoot: _getActiveProjectRootPath(),
      reachesNativeShell: true,
      commandShapeRequiresApproval:
          LocalCommandPermissionService.requiresExplicitApproval,
    );
    final requiresExplicitApproval = approvalScope.requiresExplicitApproval;
    if (permissionDecision.isDenied) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Local command was denied by a saved permission rule',
      );
    }
    final preapprovedExpired = _expiredApproval(toolCall.name, approvalCache);
    if (preapprovedExpired != null) return preapprovedExpired;
    if (!_isRemoteInteraction &&
        permissionDecision.isAllowed &&
        !requiresExplicitApproval) {
      return _mcpToolService!.executeProcessTool(
        owner: approvalCache.owner,
        name: toolCall.name,
        arguments: localArguments,
      );
    }

    final cachedResult = approvalCache.lookupDenial(
      toolCall.name,
      localArguments,
    );
    if (cachedResult != null) return cachedResult;

    final riskWarning = LocalCommandPermissionService.riskWarningFor(command);
    final reason = toolCall.arguments['reason'] as String?;
    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'process_start',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      requiredManualDecision: approvalScope.requiredManualDecision,
      requiredManualDecisionSource:
          approvalScope.requiredManualDecisionSource ?? 'required_manual',
      approvalCacheArguments: localArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
        toolCall: toolCall,
        actionKind: 'process_start',
        arguments: localArguments,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: riskWarning?.title,
        warningMessage: riskWarning?.message,
        outOfRootPaths: approvalScope.outOfRootPaths,
      ),
    );
    if (gate.isDenied) {
      return approvalCache.rememberDenial(
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
        owner: approvalCache.owner,
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        warningTitle: _escalatedApprovalWarningTitle(gate, riskWarning?.title),
        warningMessage: _escalatedApprovalWarningMessage(
          gate,
          riskWarning?.message,
        ),
      );
      final manualExpired = _expiredApproval(toolCall.name, approvalCache);
      if (manualExpired != null) return manualExpired;
      if (approval.shouldRemember &&
          !_isRemoteInteraction &&
          approvalScope.requiredManualDecision == null) {
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
        return approvalCache.rememberDenial(
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

    final expired = _expiredApproval(toolCall.name, approvalCache);
    if (expired != null) return expired;
    final result = await _mcpToolService!.executeProcessTool(
      owner: approvalCache.owner,
      name: toolCall.name,
      arguments: localArguments,
    );
    return gate.bypassedApproval || approvalScope.requiredManualDecision != null
        ? result
        : approvalCache.rememberResult(toolCall.name, localArguments, result);
  }

  Future<McpToolResult> _handleProcessCancel(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
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
    final cachedResult = approvalCache.lookupDenial(
      toolCall.name,
      localArguments,
    );
    if (cachedResult != null) return cachedResult;

    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'process_cancel',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: localArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
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
      return approvalCache.rememberDenial(
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
        owner: approvalCache.owner,
        command: 'process_cancel $jobId',
        workingDirectory: workingDirectory,
        reason: 'Cancel background process $jobId',
        warningTitle: 'Cancel background process?',
        warningMessage:
            'This stops a running local command and may leave partial side effects.',
      );
      if (!approval.approved) {
        return approvalCache.rememberDenial(
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
    final expired = _expiredApproval(toolCall.name, approvalCache);
    if (expired != null) return expired;
    final result = await _mcpToolService!.executeProcessTool(
      owner: approvalCache.owner,
      name: toolCall.name,
      arguments: localArguments,
    );
    return gate.bypassedApproval
        ? result
        : approvalCache.rememberResult(toolCall.name, localArguments, result);
  }

  Future<McpToolResult> _handleRunTests(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
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
      approvalCache,
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
    if (value.isEmpty) return "''";
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
    required ChatTurnOwner owner,
    required String command,
    required String workingDirectory,
    String? reason,
    String? warningTitle,
    String? warningMessage,
  }) {
    final completer = Completer<LocalCommandApproval>();
    final pending = PendingLocalCommand(
      owner: owner,
      id: const Uuid().v4(),
      command: command,
      workingDirectory: workingDirectory,
      reason: reason,
      warningTitle: warningTitle,
      warningMessage: warningMessage,
      completer: completer,
      origin: _activeInteractionOrigin,
      remoteDeviceId: _activeRemoteDeviceId,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingLocalCommand: pending),
      'command_execution',
      _approvalSummary(reason, command),
      workingDirectory,
      true,
    );
  }

  bool resolveLocalCommand({
    required String id,
    required LocalCommandApproval approval,
  }) => _completeApproval<LocalCommandApproval, PendingLocalCommand>(
    id,
    (_) => approval,
  );

  Future<bool> requestFileOperation({
    required ChatTurnOwner owner,
    required String operation,
    required String path,
    required String preview,
    String? reason,
  }) {
    final completer = Completer<bool>();
    final pending = PendingFileOperation(
      owner: owner,
      id: const Uuid().v4(),
      operation: operation,
      path: path,
      preview: preview,
      reason: reason,
      completer: completer,
      origin: _activeInteractionOrigin,
      remoteDeviceId: _activeRemoteDeviceId,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingFileOperation: pending),
      'file_mutation',
      _approvalSummary(reason, '$operation $path'),
      path,
    );
  }

  bool resolveFileOperation({required String id, required bool approved}) =>
      _completeApproval<bool, PendingFileOperation>(id, (_) => approved);
}
