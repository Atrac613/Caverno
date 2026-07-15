// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierSshHandlers on ChatNotifier {
  Future<McpToolResult> _handleSshConnect(ToolCallInfo toolCall) async {
    final host = (toolCall.arguments['host'] as String?)?.trim() ?? '';
    final port = (toolCall.arguments['port'] as num?)?.toInt() ?? 22;
    final username = (toolCall.arguments['username'] as String?)?.trim() ?? '';
    final cacheArguments = <String, dynamic>{
      'host': host,
      'port': port,
      'username': username,
    };

    if (host.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'host is required',
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    // Full access can auto-connect only when a password is already stored for
    // this host/user; without one an interactive prompt is unavoidable. Load it
    // up front so it doubles as the full-access eligibility signal.
    String? savedPassword;
    if (username.isNotEmpty) {
      try {
        savedPassword = await ref
            .read(sshCredentialsManagerProvider)
            .loadPassword(host: host, port: port, username: username);
      } catch (e) {
        appLog('[SSH] Failed to load saved password: $e');
      }
    }
    final hasSavedPassword = savedPassword != null && savedPassword.isNotEmpty;

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'ssh_connect',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: hasSavedPassword,
      approvalCacheArguments: cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'ssh_connect',
        arguments: cacheArguments,
        reason: toolCall.arguments['reason'] as String?,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        cacheArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }

    final SshConnectApproval approval;
    if (gate.runsDirectly && hasSavedPassword) {
      // Connect non-interactively with the stored credential.
      approval = SshConnectApproval(
        host: host,
        port: port,
        username: username,
        password: savedPassword,
        savePassword: true,
      );
    } else {
      // Default mode, or auto-review allowed but no stored credential exists to
      // connect with: fall back to the interactive password dialog.
      final manualApproval = await requestSshConnect(
        host: host,
        port: port,
        username: username,
      );
      if (manualApproval == null) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          cacheArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User cancelled SSH connection',
          ),
        );
      }
      approval = manualApproval;
    }

    try {
      await ref
          .read(sshServiceProvider)
          .connect(
            host: approval.host,
            port: approval.port,
            username: approval.username,
            password: approval.password,
          );
      if (approval.savePassword) {
        await ref
            .read(sshCredentialsManagerProvider)
            .savePassword(
              host: approval.host,
              port: approval.port,
              username: approval.username,
              password: approval.password,
            );
      } else {
        // User unchecked "save"; clear any previously saved password for
        // this triplet so the next connect prompt is empty.
        await ref
            .read(sshCredentialsManagerProvider)
            .deletePassword(
              host: approval.host,
              port: approval.port,
              username: approval.username,
            );
      }
      final connectedResult = McpToolResult(
        toolName: toolCall.name,
        result:
            'Connected to ${approval.username}@${approval.host}:${approval.port}',
        isSuccess: true,
      );
      return gate.bypassedApproval
          ? connectedResult
          : _rememberToolApprovalResult(
              toolCall.name,
              cacheArguments,
              connectedResult,
            );
    } catch (e) {
      appLog('[Tool] SSH connect failed: $e');
      final failedResult = McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'SSH connect failed: $e',
      );
      return gate.bypassedApproval
          ? failedResult
          : _rememberToolApprovalResult(
              toolCall.name,
              cacheArguments,
              failedResult,
            );
    }
  }

  Future<McpToolResult> _handleSshExecuteCommand(ToolCallInfo toolCall) async {
    final sshService = ref.read(sshServiceProvider);
    if (!sshService.isConnected) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'No active SSH session — call ssh_connect first',
      );
    }
    final command = (toolCall.arguments['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'command is required',
      );
    }
    final cacheArguments = <String, dynamic>{'command': command};
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }
    final reason = toolCall.arguments['reason'] as String?;
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'ssh_execute_command',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: true,
      approvalCacheArguments: cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'ssh_execute_command',
        arguments: cacheArguments,
        reason: reason,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        cacheArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approved = await requestSshCommand(
        command: command,
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          cacheArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied SSH command execution',
          ),
        );
      }
    }
    // Approved — delegate to the tool service, which runs the command on
    // the same SSH session.
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, cacheArguments, result);
  }

  /// Puts a pending SSH connect request into state and returns a future
  /// that completes when the user confirms or cancels the dialog.
  Future<SshConnectApproval?> requestSshConnect({
    required String host,
    required int port,
    required String username,
  }) async {
    String? savedPassword;
    if (username.isNotEmpty) {
      try {
        savedPassword = await ref
            .read(sshCredentialsManagerProvider)
            .loadPassword(host: host, port: port, username: username);
      } catch (e) {
        appLog('[SSH] Failed to load saved password: $e');
      }
    }

    final completer = Completer<SshConnectApproval?>();
    final pending = PendingSshConnect(
      id: const Uuid().v4(),
      host: host,
      port: port,
      username: username,
      savedPassword: savedPassword,
      completer: completer,
    );
    state = state.copyWith(pendingSshConnect: pending);
    _emitRuntimeApprovalRequired(
      id: pending.id,
      capability: 'ssh_connection',
      summary: 'Connect to $username@$host:$port',
      target: host,
    );
    return completer.future;
  }

  /// Resolves a pending SSH connect dialog from the UI layer.
  void resolveSshConnect({required String id, SshConnectApproval? approval}) {
    final pending = state.pendingSshConnect;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approval);
    }
    state = state.copyWith(pendingSshConnect: null);
  }

  /// Puts a pending SSH command into state and returns a future that
  /// completes with `true` (approve) or `false` (deny).
  Future<bool> requestSshCommand({required String command, String? reason}) {
    final session = ref.read(sshServiceProvider).activeSession;
    final completer = Completer<bool>();
    final pending = PendingSshCommand(
      id: const Uuid().v4(),
      command: command,
      reason: reason,
      host: session?.host ?? '(no session)',
      username: session?.username ?? '',
      completer: completer,
    );
    state = state.copyWith(pendingSshCommand: pending);
    _emitRuntimeApprovalRequired(
      id: pending.id,
      capability: 'remote_command',
      summary: reason?.trim().isNotEmpty == true ? reason!.trim() : command,
      target: pending.host,
      rememberAllowed: true,
    );
    return completer.future;
  }

  /// Resolves a pending SSH command dialog from the UI layer.
  void resolveSshCommand({required String id, required bool approved}) {
    final pending = state.pendingSshCommand;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingSshCommand: null);
  }
}
