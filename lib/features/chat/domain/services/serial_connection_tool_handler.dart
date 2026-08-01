import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'serial_connection_attempt_coordinator.dart';
import 'serial_connection_port.dart';
import 'serial_connection_tool_contract.dart';
import 'tool_approval_auto_review_service.dart';
import 'turn_tool_approval_coordinator.dart';

export 'serial_connection_tool_contract.dart';
export 'serial_connection_port.dart';

// ChatNotifier decomposition collaborator: serial-connection-tool-handler

typedef SerialConnectionApprovalMemoryCallback =
    Future<SerialConnectionApprovalMemoryAcknowledgement> Function(
      SerialConnectionApprovalMemoryRequest request,
    );

/// Exact opened session and approval result awaiting final cache settlement.
final class SerialConnectionApprovalMemoryIdentity {
  const SerialConnectionApprovalMemoryIdentity({
    required this.receipt,
    required this.approvalRequest,
    required this.result,
  });

  final SerialConnectionOpenedReceipt receipt;
  final ToolApprovalRequest approvalRequest;
  final McpToolResult result;

  bool matches(SerialConnectionApprovalMemoryIdentity expected) {
    return identical(receipt, expected.receipt) &&
        identical(approvalRequest, expected.approvalRequest) &&
        identical(result, expected.result);
  }
}

/// Typed request to remember approval without releasing the serial-session lease.
final class SerialConnectionApprovalMemoryRequest {
  const SerialConnectionApprovalMemoryRequest({required this.identity});

  final SerialConnectionApprovalMemoryIdentity identity;
}

enum SerialConnectionApprovalMemoryDisposition {
  remembered,
  rejected,
  ownerExpired,
  effectUncertain,
}

/// Typed acknowledgement for one exact final approval-memory operation.
final class SerialConnectionApprovalMemoryAcknowledgement {
  const SerialConnectionApprovalMemoryAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final SerialConnectionApprovalMemoryIdentity identity;
  final SerialConnectionApprovalMemoryDisposition disposition;
}

/// Executes one owner-scoped serial open without notifier or UI state.
final class SerialConnectionToolHandler {
  SerialConnectionToolHandler({
    required SerialConnectionPort connectionPort,
    required TurnToolApprovalCoordinator approvalCoordinator,
    required SerialConnectionAttemptCoordinator attemptCoordinator,
    SerialConnectionApprovalMemoryCallback? rememberApprovalResult,
  }) : _connectionPort = connectionPort,
       _approvalCoordinator = approvalCoordinator,
       _attemptCoordinator = attemptCoordinator,
       _rememberApprovalResult =
           rememberApprovalResult ??
           ((memoryRequest) async {
             final identity = memoryRequest.identity;
             if (approvalCoordinator.expiredResult(identity.approvalRequest) !=
                 null) {
               return SerialConnectionApprovalMemoryAcknowledgement(
                 identity: identity,
                 disposition:
                     SerialConnectionApprovalMemoryDisposition.ownerExpired,
               );
             }
             final remembered = approvalCoordinator.rememberApprovalResult(
               identity.approvalRequest,
               identity.result,
             );
             if (!identical(remembered, identity.result)) {
               return SerialConnectionApprovalMemoryAcknowledgement(
                 identity: identity,
                 disposition:
                     SerialConnectionApprovalMemoryDisposition.rejected,
               );
             }
             final ownerExpired =
                 approvalCoordinator.expiredResult(identity.approvalRequest) !=
                 null;
             return SerialConnectionApprovalMemoryAcknowledgement(
               identity: identity,
               disposition: ownerExpired
                   ? SerialConnectionApprovalMemoryDisposition.ownerExpired
                   : SerialConnectionApprovalMemoryDisposition.remembered,
             );
           });

  static const String _effectsUncertainMessage =
      'The serial open may have completed after its owner expired or its '
      'completion identity changed; inspect possible side effects before '
      'retrying';
  static const String _cleanupPendingMessage =
      'Rollback cleanup is pending; do not retry this port until the exact '
      'session fingerprint has been reconciled';
  static const String _canonicalToolName = 'serial_open';

  final SerialConnectionPort _connectionPort;
  final TurnToolApprovalCoordinator _approvalCoordinator;
  final SerialConnectionAttemptCoordinator _attemptCoordinator;
  final SerialConnectionApprovalMemoryCallback _rememberApprovalResult;

  List<SerialConnectionOpenedReceipt> get pendingCleanupReceipts {
    return _attemptCoordinator.pendingCleanupReceipts;
  }

  List<SerialConnectionAttemptLease> get pendingEffectLeases {
    return _attemptCoordinator.pendingEffectLeases;
  }

  SerialConnectionRetirementResult retireOwner(ChatTurnOwner owner) {
    return _attemptCoordinator.clearOwner(owner);
  }

  SerialConnectionRetirementResult retireAll() {
    return _attemptCoordinator.clearAll();
  }

  Future<bool> retryPendingCleanup(SerialConnectionOpenedReceipt receipt) {
    final identity = receipt.identity;
    return _rollbackExpiredReceipt(
      receipt,
      SerialConnectionRequest(
        toolCallId: identity.toolCallId,
        portName: identity.portName,
        options: identity.options,
      ),
    );
  }

  bool settlePendingOpenNoEffect(SerialConnectionAttemptLease lease) {
    return _attemptCoordinator.releaseNoEffect(lease.identity, lease.token);
  }

  Future<bool> rollbackPendingOpen(
    SerialConnectionAttemptLease lease, {
    required String sessionFingerprint,
  }) async {
    final opened = _attemptCoordinator.markOpened(
      lease.identity,
      lease.token,
      sessionFingerprint: sessionFingerprint,
    );
    if (opened.kind != SerialConnectionMarkOpenedKind.rollbackRequired) {
      return false;
    }
    return retryPendingCleanup(opened.receipt!);
  }

  Future<McpToolResult> handle(SerialConnectionToolRequest request) async {
    if (request.toolName != _canonicalToolName) {
      return _failure(
        request.toolName,
        'SerialConnectionToolHandler only accepts serial_open',
      );
    }
    if (request.toolCallId.trim().isEmpty) {
      return _failure(request.toolName, 'tool_call_id is required');
    }
    final connectionRequest = _parseRequest(
      request.toolCallId.trim(),
      request.arguments,
    );
    if (connectionRequest.portName.isEmpty) {
      return _failure(request.toolName, 'port is required');
    }

    final approvalArguments = connectionRequest.toArguments();
    final approvalRequest = ToolApprovalRequest(
      owner: request.owner,
      toolCallId: request.toolCallId,
      toolName: request.toolName,
      arguments: approvalArguments,
      actionKind: 'serial_open',
      mode: request.approvalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: true,
      cacheArguments: approvalArguments,
      reason: request.arguments['reason'] as String?,
      conversationMessages: request.conversationMessages,
      hasUntrustedInfluence: request.hasUntrustedInfluence,
    );
    final approval = await _approvalCoordinator.resolve(approvalRequest);
    if (approval.denialResult case final denial?) return denial;

    final identity = SerialConnectionAttemptIdentity(
      owner: request.owner,
      toolCallId: connectionRequest.toolCallId,
      toolName: request.toolName,
      portName: connectionRequest.portName,
      options: connectionRequest.options,
    );
    final acquisition = _attemptCoordinator.acquire(identity);
    if (acquisition.kind == SerialConnectionAttemptAcquisitionKind.busy) {
      return _failure(
        request.toolName,
        'A serial open is already in progress for ${connectionRequest.portName}',
      );
    }
    if (acquisition.kind ==
        SerialConnectionAttemptAcquisitionKind.ownerRetired) {
      return _failure(
        request.toolName,
        'The approval turn expired before execution',
      );
    }
    final lease = acquisition.lease!;
    final beginKind = _attemptCoordinator.beginOpen(identity, lease.token);
    if (beginKind == SerialConnectionBeginOpenKind.ownerRetired) {
      return _failure(
        request.toolName,
        'The approval turn expired before execution',
      );
    }
    if (beginKind != SerialConnectionBeginOpenKind.begun) {
      return _effectsUncertain(request.toolName, cleanupPending: true);
    }

    final SerialConnectionResult connection;
    try {
      connection = await _connectionPort.open(request.owner, connectionRequest);
    } catch (_) {
      _attemptCoordinator.clearOwner(request.owner);
      return _effectsUncertain(request.toolName, cleanupPending: true);
    }
    if (!connection.belongsTo(request.owner, connectionRequest)) {
      _attemptCoordinator.clearOwner(request.owner);
      return _effectsUncertain(request.toolName, cleanupPending: true);
    }
    if (connection.kind == SerialConnectionResultKind.failed) {
      _attemptCoordinator.releaseNoEffect(identity, lease.token);
      return _failure(
        request.toolName,
        'Serial open failed: ${connection.errorMessage}',
      );
    }

    final resultJson = connection.resultJson;
    final ownerExpired =
        connection.kind == SerialConnectionResultKind.ownerExpired ||
        _approvalCoordinator.expiredResult(approvalRequest) != null;
    if (ownerExpired) _attemptCoordinator.clearOwner(request.owner);
    if (resultJson == null) {
      return _effectsUncertain(request.toolName, cleanupPending: true);
    }
    final succeeded = !_serialResultIsError(resultJson);
    if (!succeeded) {
      _attemptCoordinator.releaseNoEffect(identity, lease.token);
      return ownerExpired
          ? _effectsUncertain(request.toolName)
          : McpToolResult(
              toolName: request.toolName,
              result: resultJson,
              isSuccess: false,
            );
    }

    final sessionFingerprint = connection.sessionFingerprint?.trim();
    if (sessionFingerprint == null || sessionFingerprint.isEmpty) {
      _attemptCoordinator.clearOwner(request.owner);
      return _effectsUncertain(request.toolName, cleanupPending: true);
    }
    final opened = _attemptCoordinator.markOpened(
      identity,
      lease.token,
      sessionFingerprint: sessionFingerprint,
    );
    if (opened.kind == SerialConnectionMarkOpenedKind.rejected) {
      return _effectsUncertain(request.toolName, cleanupPending: true);
    }
    final receipt = opened.receipt!;
    final mustRollback =
        ownerExpired ||
        opened.kind == SerialConnectionMarkOpenedKind.rollbackRequired;
    if (mustRollback) {
      if (!ownerExpired) _attemptCoordinator.clearOwner(request.owner);
      final cleanupSettled = await _rollbackExpiredReceipt(
        receipt,
        connectionRequest,
      );
      return _effectsUncertain(
        request.toolName,
        cleanupPending: !cleanupSettled,
      );
    }

    final result = McpToolResult(
      toolName: request.toolName,
      result: resultJson,
      isSuccess: true,
    );
    if (!approval.gateDecision!.bypassedApproval) {
      final memoryIdentity = SerialConnectionApprovalMemoryIdentity(
        receipt: receipt,
        approvalRequest: approvalRequest,
        result: result,
      );
      final SerialConnectionApprovalMemoryAcknowledgement acknowledgement;
      try {
        acknowledgement = await _rememberApprovalResult(
          SerialConnectionApprovalMemoryRequest(identity: memoryIdentity),
        );
      } catch (_) {
        return _rollbackAfterFinalSettlementFailure(
          receipt,
          connectionRequest,
          ownerExpired: false,
        );
      }
      final exactAcknowledgement = acknowledgement.identity.matches(
        memoryIdentity,
      );
      final exactRemembered =
          exactAcknowledgement &&
          acknowledgement.disposition ==
              SerialConnectionApprovalMemoryDisposition.remembered;
      final bool ownerExpiredAfterAcknowledgement;
      try {
        ownerExpiredAfterAcknowledgement =
            (exactAcknowledgement &&
                acknowledgement.disposition ==
                    SerialConnectionApprovalMemoryDisposition.ownerExpired) ||
            _approvalCoordinator.expiredResult(approvalRequest) != null;
      } catch (_) {
        return _rollbackAfterFinalSettlementFailure(
          receipt,
          connectionRequest,
          ownerExpired: false,
        );
      }
      if (!exactRemembered || ownerExpiredAfterAcknowledgement) {
        return _rollbackAfterFinalSettlementFailure(
          receipt,
          connectionRequest,
          ownerExpired: ownerExpiredAfterAcknowledgement,
        );
      }
    }
    if (_attemptCoordinator.finishCurrent(receipt) !=
        SerialConnectionCommitKind.committed) {
      return _rollbackAfterFinalSettlementFailure(
        receipt,
        connectionRequest,
        ownerExpired: true,
      );
    }
    return result;
  }

  SerialConnectionRequest _parseRequest(
    String toolCallId,
    Map<String, dynamic> arguments,
  ) {
    return SerialConnectionRequest(
      toolCallId: toolCallId,
      portName: (arguments['port'] as String?)?.trim() ?? '',
      options: SerialConnectionOptions(
        baudRate: (arguments['baud_rate'] as num?)?.toInt() ?? 9600,
        dataBits: (arguments['data_bits'] as num?)?.toInt() ?? 8,
        parity: (arguments['parity'] as String?) ?? 'none',
        stopBits: (arguments['stop_bits'] as num?)?.toInt() ?? 1,
        flowControl: (arguments['flow_control'] as String?) ?? 'none',
      ),
    );
  }

  Future<bool> _rollbackExpiredReceipt(
    SerialConnectionOpenedReceipt receipt,
    SerialConnectionRequest request,
  ) async {
    final begin = _attemptCoordinator.beginRollback(
      receipt,
      observedSessionFingerprint: receipt.sessionFingerprint,
    );
    if (begin.kind != SerialConnectionRollbackBeginKind.begun) return false;
    final permit = begin.permit!;
    final SerialConnectionRollbackResult rollback;
    try {
      rollback = await _connectionPort.rollbackOpen(permit);
    } catch (_) {
      _attemptCoordinator.finishRollback(permit, succeeded: false);
      return false;
    }
    final exactCompletion = rollback.belongsTo(
      receipt.identity.owner,
      request,
      receipt.sessionFingerprint,
    );
    final settled =
        exactCompletion &&
        (rollback.kind == SerialConnectionRollbackKind.closed ||
            rollback.kind == SerialConnectionRollbackKind.alreadyAbsent);
    final finish = _attemptCoordinator.finishRollback(
      permit,
      succeeded: settled,
    );
    return finish == SerialConnectionRollbackFinishKind.released;
  }

  Future<McpToolResult> _rollbackAfterFinalSettlementFailure(
    SerialConnectionOpenedReceipt receipt,
    SerialConnectionRequest request, {
    required bool ownerExpired,
  }) async {
    if (ownerExpired) {
      _attemptCoordinator.clearOwner(receipt.identity.owner);
    } else if (!_attemptCoordinator.requireRollback(receipt)) {
      return _effectsUncertain(receipt.identity.toolName, cleanupPending: true);
    }
    final cleanupSettled = await _rollbackExpiredReceipt(receipt, request);
    return _effectsUncertain(
      receipt.identity.toolName,
      cleanupPending: !cleanupSettled,
    );
  }

  bool _serialResultIsError(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson);
      return decoded is Map && decoded['error'] == true;
    } catch (_) {
      return false;
    }
  }

  McpToolResult _effectsUncertain(
    String toolName, {
    bool cleanupPending = false,
  }) {
    final suffix = cleanupPending ? '; $_cleanupPendingMessage' : '';
    return _failure(toolName, '$_effectsUncertainMessage$suffix');
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}
