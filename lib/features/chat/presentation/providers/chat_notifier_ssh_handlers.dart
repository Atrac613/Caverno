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

    final approval = await requestSshConnect(
      host: host,
      port: port,
      username: username,
    );
    if (approval == null) {
      return _rememberToolApprovalResult(
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
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result:
              'Connected to ${approval.username}@${approval.host}:${approval.port}',
          isSuccess: true,
        ),
      );
    } catch (e) {
      appLog('[Tool] SSH connect failed: $e');
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'SSH connect failed: $e',
        ),
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
    final approved = await requestSshCommand(command: command, reason: reason);
    if (!approved) {
      return _rememberToolApprovalResult(
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
    // Approved — delegate to the tool service, which runs the command on
    // the same SSH session.
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    return _rememberToolApprovalResult(toolCall.name, cacheArguments, result);
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
    state = state.copyWith(
      pendingSshConnect: PendingSshConnect(
        id: const Uuid().v4(),
        host: host,
        port: port,
        username: username,
        savedPassword: savedPassword,
        completer: completer,
      ),
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
    state = state.copyWith(
      pendingSshCommand: PendingSshCommand(
        id: const Uuid().v4(),
        command: command,
        reason: reason,
        host: session?.host ?? '(no session)',
        username: session?.username ?? '',
        completer: completer,
      ),
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
