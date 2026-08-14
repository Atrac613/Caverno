// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

typedef _OwnerToolApprovalHandler =
    Future<McpToolResult> Function(
      ToolCallInfo toolCall,
      OwnerToolApprovalCache approvalCache,
    );

extension ChatNotifierToolHandlerRegistry on ChatNotifier {
  PythonScriptToolRuntimeAdapter _buildPythonScriptRuntimeAdapter() {
    final staging = PythonInputStagingRuntimeAdapter();
    final approvalCacheRuntime = PythonScriptApprovalCacheRuntimeAdapter(
      ownerIsCurrent: _isApprovalOwnerCurrent,
      cacheForOwner: _toolApprovalCache.forOwner,
    );
    return PythonScriptToolRuntimeAdapter(
      resolveOwnerMessages: (identity) =>
          _resolvePythonOwnerMessages(identity, approvalCacheRuntime),
      acknowledgeLifecycle: approvalCacheRuntime.acknowledgeLifecycle,
      stage: staging.stage,
      cleanup: staging.cleanup,
      lookupDenial: approvalCacheRuntime.lookupDenial,
      resolveGate: (request) =>
          _resolvePythonGate(request, approvalCacheRuntime),
      requestManualApproval: (request) =>
          _requestPythonManualApproval(request, approvalCacheRuntime),
      rememberDenial: approvalCacheRuntime.rememberDenial,
      rememberResult: approvalCacheRuntime.rememberResult,
      execute: _executePythonRuntime,
      stagingLeases: PythonStagingLeaseRegistry(),
      executionAuthority: PythonScriptExecutionAuthority(),
    );
  }

  PythonRuntimeAcknowledgement<PythonScriptInvocationIdentity, List<Message>>
  _resolvePythonOwnerMessages(
    PythonScriptInvocationIdentity identity,
    PythonScriptApprovalCacheRuntimeAdapter approvalCacheRuntime,
  ) {
    final messages = _activeResponseRegistry.messagesForOwner(identity.owner);
    return approvalCacheRuntime.acknowledge(
      identity,
      current: _isApprovalOwnerCurrent(identity.owner) && messages != null,
      value: messages,
    );
  }

  Future<
    PythonRuntimeAcknowledgement<
      PythonApprovalRuntimeIdentity,
      ToolApprovalGateDecision
    >
  >
  _resolvePythonGate(
    PythonRuntimeApprovalRequest request,
    PythonScriptApprovalCacheRuntimeAdapter approvalCacheRuntime,
  ) async {
    final identity = request.identity;
    final owner = identity.runtime.owner;
    final cache = approvalCacheRuntime.currentCache(owner);
    if (cache == null) {
      return approvalCacheRuntime.acknowledge(identity, current: false);
    }
    final toolRequest = request.toolRequest.toolRequest;
    final toolCall = ToolCallInfo(
      id: toolRequest.toolCallId,
      name: toolRequest.toolName,
      arguments: toolRequest.arguments,
    );
    final gate = await _resolveToolApprovalGate(
      cache,
      toolCall: toolCall,
      actionKind: 'run_python_script',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: request.toolRequest.key.cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        owner,
        toolCall: toolCall,
        actionKind: 'run_python_script',
        arguments: request.toolRequest.key.cacheArguments,
        workingDirectory: request.stagedInputs.workingDirectory,
        reason: request.reason,
        preview: request.code,
      ),
    );
    return approvalCacheRuntime.acknowledge(
      identity,
      current: _isApprovalOwnerCurrent(owner),
      value: gate,
    );
  }

  Future<PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, bool>>
  _requestPythonManualApproval(
    PythonRuntimeApprovalRequest request,
    PythonScriptApprovalCacheRuntimeAdapter approvalCacheRuntime,
  ) async {
    final identity = request.identity;
    final owner = identity.runtime.owner;
    if (approvalCacheRuntime.currentCache(owner) == null) {
      return approvalCacheRuntime.acknowledge(identity, current: false);
    }
    final approved = await requestFileOperation(
      owner: owner,
      operation: 'Run Python script',
      path: request.stagedInputs.workingDirectory,
      preview: request.code,
      reason: request.reason,
    );
    return approvalCacheRuntime.acknowledge(
      identity,
      current: _isApprovalOwnerCurrent(owner),
      value: approved,
    );
  }

  Future<
    PythonRuntimeAcknowledgement<PythonExecutionRuntimeIdentity, McpToolResult>
  >
  _executePythonRuntime(PythonRuntimeExecutionRequest request) async {
    return PythonRuntimeAcknowledgement(
      identity: request.identity,
      disposition: PythonRuntimeAcknowledgementDisposition.completed,
      value: await request.runEffect(
        () => _mcpToolService!.executeTool(
          name: request.toolName,
          arguments: request.arguments,
        ),
      ),
    );
  }

  OwnerToolApprovalCache? _approvalCacheForGeneration(int? generation) {
    if (generation == null) return null;
    final owner = _turnOwnerForGeneration(generation);
    return owner == null ? null : _toolApprovalCache.forOwner(owner);
  }

  ChatToolHandler _bindOwnerHandler(
    OwnerToolApprovalCache? approvalCache,
    _OwnerToolApprovalHandler handler,
  ) {
    if (approvalCache == null) {
      return (toolCall) async =>
          _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    return (toolCall) => handler(toolCall, approvalCache);
  }

  ChatToolHandler _ownerComputerUseHandler(
    OwnerToolApprovalCache? approvalCache,
  ) => _bindOwnerHandler(approvalCache, _handleComputerUseAction);

  ChatToolHandler _ownerBrowserActionHandler(
    OwnerToolApprovalCache? approvalCache,
  ) => _bindOwnerHandler(approvalCache, _handleBrowserAction);

  ChatToolHandler _ownerNetworkMutationHandler(
    OwnerToolApprovalCache? approvalCache,
  ) => _bindOwnerHandler(approvalCache, _handleNetworkMutation);

  List<Map<String, dynamic>> _toolDefinitionsAllowedBy(
    Set<String>? allowedToolNames,
  ) {
    final availableTools = _mcpToolService?.getOpenAiToolDefinitions() ?? [];
    if (allowedToolNames == null) return availableTools;
    final allowedTools = availableTools
        .where((definition) {
          final function = definition['function'];
          final name = function is Map ? function['name']?.toString() : null;
          return name != null && allowedToolNames.contains(name);
        })
        .toList(growable: false);
    if (allowedTools.isEmpty) {
      appLog(
        '[Tool] No definitions matched the hidden-turn capability gate: '
        '${allowedToolNames.toList()}',
      );
    }
    return allowedTools;
  }

  void _logAllowedToolDefinitions(List<Map<String, dynamic>> definitions) {
    final names = definitions.map(
      (definition) => (definition['function'] as Map?)?['name'],
    );
    appLog('[Tool] Tool definitions: ${names.toList()}');
  }

  ChatToolHandlerRegistry _buildToolHandlerRegistry({
    int? interactionGeneration,
    required OwnerToolApprovalCache? approvalCache,
  }) {
    return ChatToolHandlerRegistry.fromModules([
      _ProjectScopedToolHandlerModule(this),
      _OwnerToolHandlerModule(this, approvalCache),
      _ConversationToolHandlerModule(
        this,
        interactionGeneration: interactionGeneration,
      ),
    ]);
  }
}

final class _ProjectScopedToolHandlerModule implements ChatToolHandlerModule {
  const _ProjectScopedToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers => {
    for (final toolName in const [
      'list_directory',
      'read_file',
      'inspect_file',
      'find_files',
      'search_files',
    ])
      toolName: _notifier._handleProjectScopedTool,
  };
}

final class _OwnerToolHandlerModule implements ChatToolHandlerModule {
  const _OwnerToolHandlerModule(this._notifier, this._approvalCache);

  final ChatNotifier _notifier;
  final OwnerToolApprovalCache? _approvalCache;

  ChatToolHandler _bind(_OwnerToolApprovalHandler handler) =>
      _notifier._bindOwnerHandler(_approvalCache, handler);

  Future<McpToolResult> _saveSkill(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final store = SaveSkillNotifierRuntimeStore(
      notifier: _notifier.ref.read(skillsNotifierProvider.notifier),
      isOwnerCurrent: _notifier._isApprovalOwnerCurrent,
    );
    final runtime = SaveSkillToolRuntimeAdapter(
      captureSnapshot: store.captureSnapshot,
      requestFreshManualApproval: (request) =>
          _requestSaveSkillApproval(request),
      acknowledgeOwner: (identity) => _acknowledgeSaveSkillOwner(identity),
      write: store.write,
      compensate: store.compensate,
      recordSuccess: store.recordSuccess,
      reconcileSuccess: store.reconcileSuccess,
    );
    final completion = await runtime.handle(
      owner: approvalCache.owner,
      toolCall: toolCall,
    );
    if (_isPersistedSaveSkillResult(completion.result)) {
      _notifier._lastSaveSkillGeneration =
          approvalCache.owner.interactionGeneration;
    }
    return completion.result;
  }

  Future<SaveSkillApprovalAcknowledgement> _requestSaveSkillApproval(
    SaveSkillRuntimeApprovalRequest request,
  ) async {
    final identity = request.identity;
    final owner = identity.runtime.owner;
    try {
      final approved = await _notifier.requestFileOperation(
        owner: owner,
        operation: request.request.operation,
        path: request.request.path,
        preview: request.request.preview,
        reason: request.request.reason,
      );
      return SaveSkillApprovalAcknowledgement(
        identity: identity,
        disposition: !_notifier._isApprovalOwnerCurrent(owner)
            ? SaveSkillApprovalDisposition.ownerExpired
            : approved
            ? SaveSkillApprovalDisposition.approved
            : SaveSkillApprovalDisposition.rejected,
      );
    } catch (_) {
      return SaveSkillApprovalAcknowledgement(
        identity: identity,
        disposition: SaveSkillApprovalDisposition.effectUncertain,
      );
    }
  }

  SaveSkillOwnerAcknowledgement _acknowledgeSaveSkillOwner(
    SaveSkillRuntimeIdentity identity,
  ) {
    return SaveSkillOwnerAcknowledgement(
      identity: identity,
      disposition: _notifier._isApprovalOwnerCurrent(identity.owner)
          ? SaveSkillOwnerDisposition.current
          : SaveSkillOwnerDisposition.ownerExpired,
    );
  }

  bool _isPersistedSaveSkillResult(McpToolResult result) {
    if (!result.isSuccess || result.result.isEmpty) return false;
    try {
      final decoded = jsonDecode(result.result);
      return decoded is Map<String, dynamic> && decoded['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<McpToolResult> _lspGoToDefinition(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final accessFailure = await _notifier._ensureActiveProjectAccess(
      toolCall.name,
    );
    if (accessFailure != null) return accessFailure;
    final owner = approvalCache.owner;
    final snapshot = _notifier._activeResponseRegistry.snapshotForOwner(owner);
    if (snapshot == null) {
      return _notifier._turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final lifecyclePort = _NotifierLspDefinitionLifecyclePort(_notifier);
    final handler = LspGoToDefinitionToolHandler(
      port: LspGoToDefinitionRuntimeAdapter.fromRegistry(
        registry: _notifier.ref.read(lspJsonRpcSessionRegistryProvider),
        lifecyclePort: lifecyclePort,
      ),
      lifecyclePort: lifecyclePort,
    );
    return handler.handle(
      LspGoToDefinitionToolInput(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        ownerProjectRoot: snapshot.projectRoot,
        arguments: toolCall.arguments,
      ),
    );
  }

  Future<McpToolResult> _createRoutine(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final store = CreateRoutineNotifierRuntimeStore(
      notifier: _notifier.ref.read(routinesNotifierProvider.notifier),
      isOwnerCurrent: _notifier._isApprovalOwnerCurrent,
    );
    final runtime = CreateRoutineToolRuntimeAdapter(
      requestApproval: _requestCreateRoutineApproval,
      acknowledgeOwner: _acknowledgeCreateRoutineOwner,
      create: store.create,
      captureSnapshot: store.captureSnapshot,
      compensate: store.compensate,
      recordSuccess: store.recordSuccess,
      releaseSuccess: store.releaseSuccess,
    );
    final completion = await runtime.handle(
      owner: approvalCache.owner,
      toolCall: toolCall,
    );
    return completion.result;
  }

  Future<CreateRoutineApprovalAcknowledgement> _requestCreateRoutineApproval(
    CreateRoutineRuntimeIdentity identity,
    RoutineCreationApprovalRequest request,
  ) async {
    try {
      final approved = await _notifier.requestFileOperation(
        owner: identity.owner,
        operation: request.operation,
        path: request.path,
        preview: request.preview,
        reason: request.reason,
      );
      return CreateRoutineApprovalAcknowledgement(
        identity: identity,
        disposition: !_notifier._isApprovalOwnerCurrent(identity.owner)
            ? CreateRoutineApprovalDisposition.ownerExpired
            : approved
            ? CreateRoutineApprovalDisposition.approved
            : CreateRoutineApprovalDisposition.rejected,
      );
    } catch (_) {
      return CreateRoutineApprovalAcknowledgement(
        identity: identity,
        disposition: CreateRoutineApprovalDisposition.effectUncertain,
      );
    }
  }

  CreateRoutineOwnerAcknowledgement _acknowledgeCreateRoutineOwner(
    CreateRoutineRuntimeIdentity identity,
  ) {
    if (_notifier._isApprovalOwnerCurrent(identity.owner)) {
      return CreateRoutineOwnerAcknowledgement.current(identity: identity);
    }
    return CreateRoutineOwnerAcknowledgement.ownerExpired(
      identity: identity,
      expiredResult: approvalTurnExpiredResult(identity.toolName),
    );
  }

  @override
  Map<String, ChatToolHandler> get handlers => {
    'lsp_go_to_definition': _bind(_lspGoToDefinition),
    for (final toolName in const ['write_file', 'edit_file', 'delete_file'])
      toolName: _bind(_notifier._handleFileMutation),
    'rollback_last_file_change': _bind(_notifier._handleRollbackLastFileChange),
    'local_execute_command': _bind(_notifier._handleLocalExecuteCommand),
    'process_start': _bind(_notifier._handleProcessStart),
    'process_cancel': _bind(_notifier._handleProcessCancel),
    for (final toolName in const [
      'process_status',
      'process_tail',
      'process_wait',
      'process_list',
    ])
      toolName: _bind(
        (toolCall, approvalCache) =>
            _notifier._handleProjectScopedTool(toolCall, approvalCache.owner),
      ),
    'run_tests': _bind(_notifier._handleRunTests),
    'run_python_script': _bind((toolCall, approvalCache) async {
      final completion = await _notifier._pythonScriptRuntime.handle(
        owner: approvalCache.owner,
        toolCall: toolCall,
      );
      return completion.result;
    }),
    'ssh_connect': _bind(_notifier._handleSshConnect),
    'ssh_execute_command': _bind(_notifier._handleSshExecuteCommand),
    'ssh_disconnect': _bind(_notifier._handleSshExecuteCommand),
    'git_execute_command': _bind(_notifier._handleGitExecuteCommand),
    'git_finish_worktree_session': _bind(
      _notifier._handleGitFinishWorktreeSession,
    ),
    'ble_connect': _bind(_notifier._handleBleConnect),
    'serial_open': _bind(_notifier._handleSerialOpen),
    'save_skill': _bind(_saveSkill),
    'create_routine': _bind(_createRoutine),
  };
}

final class _NotifierLspDefinitionLifecyclePort
    implements LspDefinitionLifecyclePort {
  const _NotifierLspDefinitionLifecyclePort(this._notifier);

  final ChatNotifier _notifier;

  @override
  LspDefinitionOwnerAcknowledgement acknowledgeOwner(
    LspDefinitionOperationIdentity identity,
  ) {
    return _notifier._isApprovalOwnerCurrent(identity.owner)
        ? LspDefinitionOwnerAcknowledgement.current(identity: identity)
        : LspDefinitionOwnerAcknowledgement.ownerExpired(identity: identity);
  }
}

final class _ConversationToolHandlerModule implements ChatToolHandlerModule {
  const _ConversationToolHandlerModule(
    this._notifier, {
    required this.interactionGeneration,
  });

  final ChatNotifier _notifier;
  final int? interactionGeneration;

  @override
  Map<String, ChatToolHandler> get handlers => {
    'ask_user_question': (toolCall) => _notifier._handleAskUserQuestion(
      toolCall,
      interactionGeneration: interactionGeneration,
    ),
    'spawn_subagent': (toolCall) => _notifier._handleSpawnSubagent(
      toolCall,
      interactionGeneration: interactionGeneration,
    ),
    'get_subagent_result': (toolCall) => _notifier._handleGetSubagentResult(
      toolCall,
      interactionGeneration: interactionGeneration,
    ),
    'update_goal': (toolCall) => _notifier.handleUpdateGoal(
      toolCall,
      interactionGeneration: interactionGeneration,
    ),
  };
}
