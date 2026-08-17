import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/ssh_session_ownership_coordinator.dart';
import '../../domain/services/ssh_tool_handler.dart';

export '../../domain/services/ssh_tool_handler.dart';

typedef ChatSshSession = ({
  String host,
  int port,
  String username,
  String fingerprint,
});

abstract interface class ChatSshTransport {
  ChatSshSession? activeSession(ChatTurnOwner owner);

  Future<void> connect(
    ChatTurnOwner owner,
    SshCredentialKey target,
    SshAuthCredential credential,
  );

  Future<String> execute(
    ChatTurnOwner owner,
    String command,
    String expectedFingerprint,
  );

  Future<bool> disconnectIfFingerprint(
    ChatTurnOwner owner,
    String expectedFingerprint,
  );

  Future<void> clearOwner(ChatTurnOwner owner);
}

/// Production transport adapter for the owner-bound SSH collaborator.
final class ChatSshToolRuntime {
  ChatSshToolRuntime(this._transport);

  static const _uncertain =
      'The SSH session changed during the operation; inspect possible side '
      'effects before retrying';

  final ChatSshTransport _transport;
  final SshSessionOwnershipCoordinator _ownership =
      SshSessionOwnershipCoordinator();
  final Map<ChatTurnOwner, SshOwnedConnection> _connections = {};
  int _nextConnectionIdentity = 0;

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required SshCredentialPort credentialPort,
    required SshCommandApprovalPort approvalPort,
  }) {
    final request = switch (toolName) {
      'ssh_connect' => SshToolRequest.connect(
        owner: owner,
        toolCallId: toolCallId,
        connectionIdentity: SshConnectionIdentity(
          'ssh-connect:${++_nextConnectionIdentity}',
        ),
        arguments: arguments,
      ),
      'ssh_execute_command' => SshToolRequest.executeCommand(
        owner: owner,
        toolCallId: toolCallId,
        arguments: arguments,
      ),
      'ssh_disconnect' => SshToolRequest.disconnect(
        owner: owner,
        toolCallId: toolCallId,
        arguments: arguments,
      ),
      _ => throw ArgumentError.value(toolName, 'toolName', 'Unknown SSH tool'),
    };
    return SshToolHandler(
      credentialPort: credentialPort,
      connectionPort: _RuntimeConnectionPort(this),
      executionPort: _RuntimeExecutionPort(this),
      approvalPort: approvalPort,
    ).handle(request);
  }

  SshCallCompletion<SshOwnedConnection?> _lookupActive(SshToolRequest request) {
    final active = _ownership.activeSession(request.owner);
    final connection = _connections[request.owner];
    final status = _transport.activeSession(request.owner);
    final fingerprint = status?.fingerprint;
    final isExact =
        active != null &&
        connection != null &&
        status != null &&
        active.externalFingerprint.value == fingerprint &&
        connection.connectToolCallId == active.identity.toolCallId &&
        connection.key.host == status.host &&
        connection.key.port == status.port &&
        connection.key.username == status.username;
    return SshCallCompletion(
      request: request,
      value: isExact ? connection : null,
    );
  }

  Future<SshOperationCompletion<void>> _connect(
    SshOperationIdentity operation, {
    required SshAuthCredential credential,
  }) async {
    final identity = _connectionOperation(operation);
    final begun = _ownership.beginConnect(identity);
    final attempt = begun.attempt;
    if (attempt == null) {
      throw StateError('SSH connection owner is no longer active');
    }

    final prior = _ownership.activeSession(operation.owner);
    if (prior != null) {
      final retired = _ownership.retireSession(operation.owner, prior.token);
      final receipt = retired.cleanupReceipt;
      if (receipt != null && !await _settle(receipt)) {
        _ownership.finishConnect(identity, attempt.token);
        throw StateError('A successor SSH session is already active');
      }
      _connections.remove(operation.owner);
    }

    try {
      await _transport.connect(operation.owner, operation.target, credential);
    } catch (_) {
      _ownership.finishConnect(identity, attempt.token);
      rethrow;
    }

    final fingerprint = _transport.activeSession(operation.owner)?.fingerprint;
    if (fingerprint == null) {
      _ownership.finishConnect(identity, attempt.token);
      throw StateError('SSH transport did not expose a session identity');
    }
    final completed = _ownership.completeConnect(
      identity: identity,
      token: attempt.token,
      externalFingerprint: SshExternalSessionFingerprint(fingerprint),
    );
    if (completed.cleanupReceipt case final receipt?) {
      await _settle(receipt);
    }
    if (completed.status != SshOwnershipStatus.activated) {
      throw StateError('SSH connection ownership changed before activation');
    }
    _connections[operation.owner] = SshOwnedConnection(
      owner: operation.owner,
      connectToolCallId: operation.toolCallId,
      identity: operation.connectionIdentity,
      key: operation.target,
    );
    return SshOperationCompletion(operation: operation, value: null);
  }

  Future<SshOperationCompletion<McpToolResult>> _execute(
    SshOperationIdentity operation,
    Map<String, dynamic> arguments,
  ) async {
    final active = _exactSession(operation);
    if (active == null) throw StateError(_uncertain);
    final command = (arguments['command'] as String?)?.trim() ?? '';
    final commandIdentity = SshCommandOperationIdentity((
      owner: operation.owner,
      toolCallId: operation.toolCallId,
      toolName: operation.toolName,
      commandDigest: sha256
          .convert(utf8.encode(jsonEncode(arguments)))
          .toString(),
    ));
    final acquired = _ownership.acquireCommandLease(
      operation: commandIdentity,
      sessionToken: active.token,
    );
    final lease = acquired.lease;
    if (lease == null) throw StateError(_uncertain);

    try {
      final result = await _transport.execute(
        operation.owner,
        command,
        active.externalFingerprint.value,
      );
      if (!_ownership.isCommandLeaseCurrent(
            commandIdentity,
            active.token,
            lease.token,
          ) ||
          _transport.activeSession(operation.owner)?.fingerprint !=
              active.externalFingerprint.value) {
        throw StateError(_uncertain);
      }
      return SshOperationCompletion(
        operation: operation,
        value: McpToolResult(
          toolName: operation.toolName,
          result: result,
          isSuccess: true,
        ),
      );
    } catch (error) {
      final stillCurrent =
          _ownership.isCommandLeaseCurrent(
            commandIdentity,
            active.token,
            lease.token,
          ) &&
          _transport.activeSession(operation.owner)?.fingerprint ==
              active.externalFingerprint.value;
      if (!stillCurrent) rethrow;
      return SshOperationCompletion(
        operation: operation,
        value: McpToolResult(
          toolName: operation.toolName,
          result: '',
          isSuccess: false,
          errorMessage: error.toString(),
        ),
      );
    } finally {
      _ownership.releaseCommandLease(
        operation: commandIdentity,
        sessionToken: active.token,
        leaseToken: lease.token,
      );
    }
  }

  Future<SshOperationCompletion<void>> _rollback(
    SshOperationIdentity operation,
  ) async {
    await _retireExact(operation);
    return SshOperationCompletion(operation: operation, value: null);
  }

  Future<SshOperationCompletion<McpToolResult>> _disconnect(
    SshOperationIdentity operation,
  ) async {
    final disconnected = await _retireExact(operation);
    return SshOperationCompletion(
      operation: operation,
      value: McpToolResult(
        toolName: operation.toolName,
        result: disconnected ? 'Disconnected' : '',
        isSuccess: disconnected,
        errorMessage: disconnected ? null : _uncertain,
      ),
    );
  }

  Future<bool> _retireExact(SshOperationIdentity operation) async {
    final active = _exactSession(operation);
    if (active == null) return false;
    final retired = _ownership.retireSession(operation.owner, active.token);
    final receipt = retired.cleanupReceipt;
    if (receipt == null) return false;
    final disconnected = await _settle(receipt);
    final current = _connections[operation.owner];
    if (current != null &&
        current.identity.value == operation.connectionIdentity.value) {
      _connections.remove(operation.owner);
    }
    return disconnected;
  }

  SshActivatedSession? _exactSession(SshOperationIdentity operation) {
    final active = _ownership.activeSession(operation.owner);
    final connection = _connections[operation.owner];
    if (active == null ||
        connection == null ||
        connection.identity.value != operation.connectionIdentity.value ||
        connection.connectToolCallId != operation.sessionToolCallId ||
        active.externalFingerprint.value !=
            _transport.activeSession(operation.owner)?.fingerprint) {
      return null;
    }
    return active;
  }

  SshConnectionOperationIdentity _connectionOperation(
    SshOperationIdentity operation,
  ) => SshConnectionOperationIdentity((
    owner: operation.owner,
    toolCallId: operation.toolCallId,
    toolName: operation.toolName,
    connectionDigest: operation.connectionIdentity.value,
  ));

  Future<bool> _settle(SshDisconnectReceipt receipt) async {
    final observed = _transport.activeSession(receipt.owner)?.fingerprint;
    final expected = receipt.expectedFingerprint;
    final authorization = _ownership.authorizeDisconnect(
      receipt: receipt,
      observedFingerprint: observed == null
          ? expected
          : SshExternalSessionFingerprint(observed),
    );
    final permit = authorization.permit;
    if (permit == null) return observed == null;
    final succeeded =
        observed == null ||
        await _transport.disconnectIfFingerprint(receipt.owner, expected.value);
    _ownership.finishDisconnect(permit, succeeded: succeeded);
    return succeeded;
  }

  Future<void> clearOwner(ChatTurnOwner owner) async {
    final cleared = _ownership.clearOwner(owner);
    _connections.remove(owner);
    for (final receipt in cleared.cleanupReceipts) {
      await _settle(receipt);
    }
    await _transport.clearOwner(owner);
  }

  Future<void> clearAll() async {
    final cleared = _ownership.clearAll();
    _connections.clear();
    for (final receipt in cleared.cleanupReceipts) {
      await _settle(receipt);
    }
  }
}

final class _RuntimeConnectionPort implements SshConnectionPort {
  const _RuntimeConnectionPort(this.runtime);
  final ChatSshToolRuntime runtime;

  @override
  SshCallCompletion<SshOwnedConnection?> lookupActive(SshToolRequest request) =>
      runtime._lookupActive(request);

  @override
  Future<SshOperationCompletion<void>> connect(
    SshOperationIdentity operation, {
    required SshAuthCredential credential,
  }) => runtime._connect(operation, credential: credential);

  @override
  Future<SshOperationCompletion<void>> disconnect(
    SshOperationIdentity operation,
  ) => runtime._rollback(operation);
}

final class _RuntimeExecutionPort implements SshCommandExecutionPort {
  const _RuntimeExecutionPort(this.runtime);
  final ChatSshToolRuntime runtime;

  @override
  Future<SshOperationCompletion<McpToolResult>> executeCommand(
    SshOperationIdentity operation, {
    required Map<String, dynamic> arguments,
  }) => runtime._execute(operation, arguments);

  @override
  Future<SshOperationCompletion<McpToolResult>> disconnect(
    SshOperationIdentity operation, {
    required Map<String, dynamic> arguments,
  }) => runtime._disconnect(operation);
}
