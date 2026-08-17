import '../entities/mcp_tool_entity.dart';
import 'ssh_tool_contract.dart';

export 'ssh_tool_contract.dart';

part 'ssh_tool_failures.dart';

// ChatNotifier decomposition collaborator: ssh-tool-handler

/// Coordinates exact-call SSH connection and command flows.
final class SshToolHandler {
  const SshToolHandler({
    required SshCredentialPort credentialPort,
    required SshConnectionPort connectionPort,
    required SshCommandExecutionPort executionPort,
    required SshCommandApprovalPort approvalPort,
  }) : _credentialPort = credentialPort,
       _connectionPort = connectionPort,
       _executionPort = executionPort,
       _approvalPort = approvalPort;

  final SshCredentialPort _credentialPort;
  final SshConnectionPort _connectionPort;
  final SshCommandExecutionPort _executionPort;
  final SshCommandApprovalPort _approvalPort;

  Future<McpToolResult> handle(SshToolRequest request) {
    return switch (request.kind) {
      SshToolKind.connect => _connect(request),
      SshToolKind.executeCommand => _executeCommand(request),
      SshToolKind.disconnect => _disconnect(request),
    };
  }

  Future<McpToolResult> _connect(SshToolRequest request) async {
    final host = (request.arguments['host'] as String?)?.trim() ?? '';
    final port = (request.arguments['port'] as num?)?.toInt() ?? 22;
    final username = (request.arguments['username'] as String?)?.trim() ?? '';
    if (host.isEmpty) return _failure(request.toolName, 'host is required');

    final target = SshCredentialKey(host: host, port: port, username: username);
    final operation = SshOperationIdentity(
      request: request,
      connectionIdentity: request.connectionIdentity!,
      sessionToolCallId: request.toolCallId,
      target: target,
    );
    final approval = SshApprovalRequest(
      operation: operation,
      cacheArguments: {'host': host, 'port': port, 'username': username},
    );
    final cached = _approvalPort.lookupDenial(approval);
    if (!cached.belongsTo(operation)) return _identityFailure(request.toolName);
    if (cached.value case final denial?) return denial;

    SshAuthCredential? savedCredential;
    if (username.isNotEmpty) {
      try {
        final completion = await _credentialPort.loadSavedCredential(operation);
        if (!completion.belongsTo(operation)) {
          return _identityFailure(request.toolName);
        }
        savedCredential = completion.value;
      } catch (_) {
        // Credential storage failures preserve the interactive fallback.
      }
    }
    final hasSavedCredential = savedCredential != null;
    final gateCompletion = await _approvalPort.resolveGate(
      approval,
      fullAccessEligible: hasSavedCredential,
    );
    if (!gateCompletion.belongsTo(operation)) {
      return _identityFailure(request.toolName);
    }
    final gate = gateCompletion.value;
    if (gate.isDenied) {
      return _rememberDenial(
        approval,
        _autoReviewDeniedResult(request.toolName, gate.deniedRationale!),
      );
    }

    final SshConnectCredentialSelection selection;
    if (gate.runsDirectly && hasSavedCredential) {
      selection = SshConnectCredentialSelection(
        key: target,
        credential: savedCredential,
        remember: true,
      );
    } else {
      final credential = await _credentialPort.requestCredential(
        SshConnectCredentialRequest(
          operation: operation,
          savedCredential: savedCredential,
        ),
      );
      if (!credential.belongsTo(operation)) {
        return _identityFailure(request.toolName);
      }
      if (credential.kind ==
          SshCredentialSelectionResultKind.reapprovalRequired) {
        return _targetChangedFailure(
          request.toolName,
          credential.selection!.key,
        );
      }
      if (credential.kind == SshCredentialSelectionResultKind.cancelled) {
        return _rememberDenial(
          approval,
          _failure(request.toolName, 'User cancelled SSH connection'),
        );
      }
      selection = credential.selection!;
    }

    // The dialog may have supplied a username the call omitted, which the tool
    // asks it to do. The session must then be opened and its credential stored
    // under the completed target: the approved one names no user to log in as.
    final session = operation.completedWith(selection.key);
    final expired = _expiration(session);
    if (expired case final result?) return result;
    var connected = false;
    try {
      final connectCompletion = await _connectionPort.connect(
        session,
        credential: selection.credential,
      );
      if (!connectCompletion.belongsTo(session)) {
        return _effectsFailure(request.toolName);
      }
      connected = true;
      if (_expiration(session) != null) {
        await _rollbackExpiredConnect(session);
        return _effectsFailure(request.toolName);
      }
      final persisted = selection.remember
          ? await _credentialPort.saveCredential(session, selection.credential)
          : await _credentialPort.deleteCredential(session);
      if (!persisted.belongsTo(session)) {
        return _connectedPersistenceFailure(
          request.toolName,
          'credential completion identity changed',
        );
      }
    } catch (error) {
      if (connected) {
        return _connectedPersistenceFailure(request.toolName, '$error');
      }
      final result = _failure(request.toolName, 'SSH connect failed: $error');
      return gate.bypassedApproval ? result : _rememberResult(approval, result);
    }
    if (_expiration(session) != null) {
      await _rollbackExpiredConnect(session);
      return _effectsFailure(request.toolName);
    }

    final result = McpToolResult(
      toolName: request.toolName,
      result: 'Connected to ${session.target.username}@$host:$port',
      isSuccess: true,
    );
    return gate.bypassedApproval
        ? result
        : _rememberResult(approval, result, effectsPossible: true);
  }

  Future<McpToolResult> _executeCommand(SshToolRequest request) async {
    final connection = _lookupConnection(request);
    if (connection == null) return _noActiveSession(request.toolName);
    final command = (request.arguments['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return _failure(request.toolName, 'command is required');
    }
    final operation = _operationForConnection(request, connection);
    final approval = SshApprovalRequest(
      operation: operation,
      cacheArguments: {'command': command},
    );
    final cached = _approvalPort.lookupDenial(approval);
    if (!cached.belongsTo(operation)) return _identityFailure(request.toolName);
    if (cached.value case final denial?) return denial;

    final gateCompletion = await _approvalPort.resolveGate(
      approval,
      fullAccessEligible: true,
    );
    if (!gateCompletion.belongsTo(operation)) {
      return _identityFailure(request.toolName);
    }
    final gate = gateCompletion.value;
    if (gate.isDenied) {
      return _rememberDenial(
        approval,
        _autoReviewDeniedResult(request.toolName, gate.deniedRationale!),
      );
    }
    if (gate.needsManual) {
      final decision = await _approvalPort.requestCommandApproval(approval);
      if (!decision.belongsTo(operation)) {
        return _identityFailure(request.toolName);
      }
      if (!decision.value) {
        return _rememberDenial(
          approval,
          _failure(request.toolName, 'User denied SSH command execution'),
        );
      }
    }
    if (_expiration(operation) case final expired?) return expired;

    final SshOperationCompletion<McpToolResult> completion;
    try {
      completion = await _executionPort.executeCommand(
        operation,
        arguments: request.arguments,
      );
    } catch (_) {
      return _effectsFailure(request.toolName);
    }
    if (!completion.belongsTo(operation) || _expiration(operation) != null) {
      return _effectsFailure(request.toolName);
    }
    return gate.bypassedApproval
        ? completion.value
        : _rememberResult(approval, completion.value, effectsPossible: true);
  }

  Future<McpToolResult> _disconnect(SshToolRequest request) async {
    final connection = _lookupConnection(request);
    if (connection == null) {
      return McpToolResult(
        toolName: request.toolName,
        result: 'No active SSH session',
        isSuccess: true,
      );
    }
    final operation = _operationForConnection(request, connection);
    if (_expiration(operation) case final expired?) return expired;
    try {
      final completion = await _executionPort.disconnect(
        operation,
        arguments: request.arguments,
      );
      if (!completion.belongsTo(operation) || _expiration(operation) != null) {
        return _effectsFailure(request.toolName);
      }
      return completion.value;
    } catch (_) {
      return _effectsFailure(request.toolName);
    }
  }

  SshOwnedConnection? _lookupConnection(SshToolRequest request) {
    final completion = _connectionPort.lookupActive(request);
    if (!completion.belongsTo(request)) return null;
    final connection = completion.value;
    return connection != null && connection.owner == request.owner
        ? connection
        : null;
  }

  SshOperationIdentity _operationForConnection(
    SshToolRequest request,
    SshOwnedConnection connection,
  ) {
    return SshOperationIdentity(
      request: request,
      connectionIdentity: connection.identity,
      sessionToolCallId: connection.connectToolCallId,
      target: connection.key,
    );
  }

  McpToolResult? _expiration(SshOperationIdentity operation) {
    final completion = _approvalPort.expiredResult(operation);
    return completion.belongsTo(operation)
        ? completion.value
        : _identityFailure(operation.toolName);
  }

  Future<void> _rollbackExpiredConnect(SshOperationIdentity operation) async {
    try {
      final completion = await _connectionPort.disconnect(operation);
      if (!completion.belongsTo(operation)) return;
    } catch (_) {}
  }

  McpToolResult _rememberDenial(
    SshApprovalRequest request,
    McpToolResult result,
  ) {
    final completion = _approvalPort.rememberDenial(request, result);
    return completion.belongsTo(request.operation)
        ? completion.value
        : _identityFailure(request.toolName);
  }

  McpToolResult _rememberResult(
    SshApprovalRequest request,
    McpToolResult result, {
    bool effectsPossible = false,
  }) {
    final completion = _approvalPort.rememberResult(request, result);
    if (completion.belongsTo(request.operation)) return completion.value;
    return effectsPossible
        ? _effectsFailure(request.toolName)
        : _identityFailure(request.toolName);
  }
}
