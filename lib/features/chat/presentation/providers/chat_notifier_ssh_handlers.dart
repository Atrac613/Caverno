// Same-library extension; see the Git handlers for lint rationale.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

final Expando<ChatSshToolRuntime> _sshToolRuntimes =
    Expando<ChatSshToolRuntime>();

extension ChatNotifierSshHandlers on ChatNotifier {
  Future<McpToolResult> _handleSshConnect(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) => _runSshTool(toolCall, approvalCache);

  Future<McpToolResult> _handleSshExecuteCommand(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) => _runSshTool(toolCall, approvalCache);

  Future<McpToolResult> _runSshTool(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) {
    final ports = _ChatNotifierSshPorts(this, toolCall, approvalCache);
    return _sshToolRuntime.handle(
      owner: approvalCache.owner,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      arguments: toolCall.arguments,
      credentialPort: ports,
      approvalPort: ports,
    );
  }

  Future<void> _clearSshOwner(ChatTurnOwner owner) =>
      _sshToolRuntime.clearOwner(owner);

  ChatSshToolRuntime get _sshToolRuntime => _sshToolRuntimes[this] ??=
      ChatSshToolRuntime(SshServiceChatTransport(_sshService));

  /// Puts a pending SSH connect request into state and returns a future
  /// that completes when the user confirms or cancels the dialog.
  Future<SshConnectApproval?> requestSshConnect({
    required ChatTurnOwner owner,
    required String host,
    required int port,
    required String username,
    SshConfigHostSettings config = SshConfigHostSettings.empty,
  }) async {
    // A host the user describes as "connects without a password" is usually
    // configured in ~/.ssh/config. Its user and identity fill in only what the
    // call left out, so a value the model did state still stands.
    final effectiveUsername = username.isNotEmpty
        ? username
        : (config.user ?? '');
    SshAuthCredential? savedCredential;
    if (effectiveUsername.isNotEmpty) {
      try {
        savedCredential = await ref
            .read(sshCredentialsManagerProvider)
            .loadCredential(
              host: host,
              port: port,
              username: effectiveUsername,
            );
      } catch (e) {
        appLog('[SSH] Failed to load saved credential: $e');
      }
    }
    final completer = Completer<SshConnectApproval?>();
    final pending = PendingSshConnect(
      owner: owner,
      id: const Uuid().v4(),
      host: host,
      port: config.port ?? port,
      username: effectiveUsername,
      savedCredential: savedCredential,
      identityCandidates: config.identityFiles.isNotEmpty
          ? config.identityFiles
          : SshClientConnector.discoverDefaultIdentities(),
      completer: completer,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingSshConnect: pending),
      'ssh_connection',
      'Connect to $username@$host:$port',
      host,
    );
  }

  /// Resolves a pending SSH connect dialog from the UI layer.
  bool resolveSshConnect({required String id, SshConnectApproval? approval}) =>
      _completeApproval<SshConnectApproval?, PendingSshConnect>(
        id,
        (_) => approval,
      );

  /// Puts a pending SSH command into state and returns a future that
  /// completes with `true` (approve) or `false` (deny).
  Future<bool> requestSshCommand({
    required ChatTurnOwner owner,
    required String command,
    String? reason,
  }) {
    final session = _sshService.activeSession(owner: owner);
    final completer = Completer<bool>();
    final pending = PendingSshCommand(
      owner: owner,
      id: const Uuid().v4(),
      command: command,
      reason: reason,
      host: session?.host ?? '(no session)',
      username: session?.username ?? '',
      completer: completer,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingSshCommand: pending),
      'remote_command',
      _approvalSummary(reason, command),
      pending.host,
      true,
    );
  }

  /// Resolves a pending SSH command dialog from the UI layer.
  bool resolveSshCommand({required String id, required bool approved}) =>
      _completeApproval<bool, PendingSshCommand>(id, (_) => approved);
}

final class _ChatNotifierSshPorts
    implements SshCredentialPort, SshCommandApprovalPort {
  const _ChatNotifierSshPorts(this.notifier, this.toolCall, this.cache);

  final ChatNotifier notifier;
  final ToolCallInfo toolCall;
  final OwnerToolApprovalCache cache;

  @override
  Future<SshOperationCompletion<SshAuthCredential?>> loadSavedCredential(
    SshOperationIdentity operation,
  ) async {
    final key = operation.target;
    final credential = key.username.isEmpty
        ? null
        : await notifier.ref
              .read(sshCredentialsManagerProvider)
              .loadCredential(
                host: key.host,
                port: key.port,
                username: key.username,
              );
    return SshOperationCompletion(operation: operation, value: credential);
  }

  @override
  Future<SshCredentialSelectionResult> requestCredential(
    SshConnectCredentialRequest request,
  ) async {
    final key = request.approvedTarget;
    final approval = await notifier.requestSshConnect(
      owner: request.operation.owner,
      host: key.host,
      port: key.port,
      username: key.username,
      config: SshConfigReader.resolve(key.host),
    );
    if (approval == null) {
      return SshCredentialSelectionResult.cancelled(
        operation: request.operation,
      );
    }
    return SshCredentialSelectionResult.fromSelection(
      operation: request.operation,
      selection: SshConnectCredentialSelection(
        key: SshCredentialKey(
          host: approval.host.trim(),
          port: approval.port,
          username: approval.username.trim(),
        ),
        credential: approval.credential,
        remember: approval.remember,
      ),
    );
  }

  @override
  Future<SshOperationCompletion<void>> saveCredential(
    SshOperationIdentity operation,
    SshAuthCredential credential,
  ) async {
    final key = operation.target;
    await notifier.ref
        .read(sshCredentialsManagerProvider)
        .saveCredential(
          host: key.host,
          port: key.port,
          username: key.username,
          credential: credential,
        );
    return SshOperationCompletion(operation: operation, value: null);
  }

  @override
  Future<SshOperationCompletion<void>> deleteCredential(
    SshOperationIdentity operation,
  ) async {
    final key = operation.target;
    await notifier.ref
        .read(sshCredentialsManagerProvider)
        .deleteCredential(
          host: key.host,
          port: key.port,
          username: key.username,
        );
    return SshOperationCompletion(operation: operation, value: null);
  }

  @override
  SshOperationCompletion<McpToolResult?> lookupDenial(
    SshApprovalRequest request,
  ) => SshOperationCompletion(
    operation: request.operation,
    value: cache.lookupDenial(request.toolName, request.cacheArguments),
  );

  @override
  Future<SshOperationCompletion<ToolApprovalGateDecision>> resolveGate(
    SshApprovalRequest request, {
    required bool fullAccessEligible,
  }) async {
    final gate = await notifier._resolveToolApprovalGate(
      cache,
      toolCall: toolCall,
      actionKind: request.toolName,
      mode: notifier._settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: fullAccessEligible,
      approvalCacheArguments: request.cacheArguments,
      buildReviewRequest: () async => notifier._buildAutoReviewRequest(
        request.owner,
        toolCall: toolCall,
        actionKind: request.toolName,
        arguments: request.cacheArguments,
        reason: request.operation.request.reason,
      ),
    );
    return SshOperationCompletion(operation: request.operation, value: gate);
  }

  @override
  Future<SshOperationCompletion<bool>> requestCommandApproval(
    SshApprovalRequest request,
  ) async {
    final arguments = request.operation.request.arguments;
    final approved = await notifier.requestSshCommand(
      owner: request.owner,
      command: (arguments['command'] as String?)?.trim() ?? '',
      reason: arguments['reason'] as String?,
    );
    return SshOperationCompletion(
      operation: request.operation,
      value: approved,
    );
  }

  @override
  SshOperationCompletion<McpToolResult> rememberDenial(
    SshApprovalRequest request,
    McpToolResult result,
  ) => SshOperationCompletion(
    operation: request.operation,
    value: cache.rememberDenial(
      request.toolName,
      request.cacheArguments,
      result,
    ),
  );

  @override
  SshOperationCompletion<McpToolResult> rememberResult(
    SshApprovalRequest request,
    McpToolResult result,
  ) => SshOperationCompletion(
    operation: request.operation,
    value: cache.rememberResult(
      request.toolName,
      request.cacheArguments,
      result,
    ),
  );

  @override
  SshOperationCompletion<McpToolResult?> expiredResult(
    SshOperationIdentity operation,
  ) => SshOperationCompletion(
    operation: operation,
    value: notifier._expiredApproval(operation.toolName, cache),
  );
}
