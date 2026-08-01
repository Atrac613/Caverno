import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/ble_connection_runtime_contract.dart';
import '../../domain/services/ble_connection_tool_handler.dart';
import '../../domain/services/turn_tool_approval_coordinator.dart';

export '../../domain/services/ble_connection_runtime_contract.dart';
export '../../domain/services/ble_connection_tool_handler.dart'
    show BleConnectionToolRequest;

/// Production-facing composition of BLE approval and owner-aware execution.
final class BleConnectionToolRuntimeAdapter {
  const BleConnectionToolRuntimeAdapter({
    required TurnToolApprovalCoordinator approvalCoordinator,
    required BleOwnerLifecycleCallback acknowledgeOwner,
    required BleScanLookupCallback lookupScanResult,
    required BleSerializedConnectPort connectPort,
  }) : _approvalCoordinator = approvalCoordinator,
       _acknowledgeOwner = acknowledgeOwner,
       _lookupScanResult = lookupScanResult,
       _connectPort = connectPort;

  final TurnToolApprovalCoordinator _approvalCoordinator;
  final BleOwnerLifecycleCallback _acknowledgeOwner;
  final BleScanLookupCallback _lookupScanResult;
  final BleSerializedConnectPort _connectPort;

  Future<McpToolResult> handle(BleConnectionToolRequest request) {
    final identity = _validatedIdentity(request);
    return BleConnectionToolHandler(
      connectionPort: _BleConnectionPortBridge(
        expectedIdentity: identity,
        acknowledgeOwner: _acknowledgeOwner,
        lookupScanResult: _lookupScanResult,
        connectPort: _connectPort,
      ),
      approvalCoordinator: _approvalCoordinator,
    ).handle(request);
  }

  BleConnectionRuntimeIdentity? _validatedIdentity(
    BleConnectionToolRequest request,
  ) {
    try {
      return BleConnectionRuntimeIdentity(
        owner: request.owner,
        toolCallId: request.toolCallId,
        toolName: request.toolName,
        deviceId: request.deviceId,
      );
    } on ArgumentError {
      return null;
    }
  }
}

final class _BleConnectionPortBridge implements BleConnectionPort {
  const _BleConnectionPortBridge({
    required BleConnectionRuntimeIdentity? expectedIdentity,
    required BleOwnerLifecycleCallback acknowledgeOwner,
    required BleScanLookupCallback lookupScanResult,
    required BleSerializedConnectPort connectPort,
  }) : _expectedIdentity = expectedIdentity,
       _acknowledgeOwner = acknowledgeOwner,
       _lookupScanResult = lookupScanResult,
       _connectPort = connectPort;

  final BleConnectionRuntimeIdentity? _expectedIdentity;
  final BleOwnerLifecycleCallback _acknowledgeOwner;
  final BleScanLookupCallback _lookupScanResult;
  final BleSerializedConnectPort _connectPort;

  @override
  Future<BleConnectionLookupResult> lookupDisplayName(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  ) async {
    final identity = _expectedIdentity;
    if (identity == null || !_matchesLegacyRequest(identity, owner, request)) {
      return _mismatchedLookup(owner, request);
    }
    if (_lifecycle(identity) != BleOwnerLifecycleDisposition.current) {
      return _mismatchedLookup(owner, request);
    }

    final BleScanLookupAcknowledgement acknowledgement;
    try {
      acknowledgement = await _lookupScanResult(identity);
    } catch (error) {
      throw StateError('BLE scan lookup failed: $error');
    }
    if (!acknowledgement.identity.belongsTo(identity)) {
      return _mismatchedLookup(owner, request);
    }
    if (acknowledgement.disposition == BleScanLookupDisposition.ownerExpired) {
      return _mismatchedLookup(owner, request);
    }
    if (acknowledgement.disposition == BleScanLookupDisposition.failed) {
      throw StateError(
        'BLE scan lookup failed: '
        '${acknowledgement.errorMessage ?? 'unknown scan error'}',
      );
    }
    if (_lifecycle(identity) != BleOwnerLifecycleDisposition.current) {
      return _mismatchedLookup(owner, request);
    }
    return BleConnectionLookupResult(
      owner: owner,
      toolCallId: request.toolCallId,
      deviceId: request.deviceId,
      displayName: acknowledgement.displayName,
    );
  }

  @override
  Future<BleConnectionResult> connect(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  ) async {
    final identity = _expectedIdentity;
    if (identity == null || !_matchesLegacyRequest(identity, owner, request)) {
      return BleConnectionResult.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
        deviceId: request.deviceId,
      );
    }
    if (_lifecycle(identity) != BleOwnerLifecycleDisposition.current) {
      return BleConnectionResult.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
        deviceId: request.deviceId,
      );
    }

    final BleSerializedConnectAcknowledgement acknowledgement;
    try {
      acknowledgement = await _connectPort.connect(identity);
    } catch (_) {
      return BleConnectionResult.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
        deviceId: request.deviceId,
      );
    }
    if (!acknowledgement.identity.belongsTo(identity)) {
      return BleConnectionResult.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
        deviceId: request.deviceId,
      );
    }
    return switch (acknowledgement.disposition) {
      BleSerializedConnectDisposition.connected =>
        BleConnectionResult.connected(
          owner: owner,
          toolCallId: request.toolCallId,
          deviceId: request.deviceId,
        ),
      BleSerializedConnectDisposition.ownerExpired ||
      BleSerializedConnectDisposition.effectUncertain =>
        BleConnectionResult.ownerExpired(
          owner: owner,
          toolCallId: request.toolCallId,
          deviceId: request.deviceId,
        ),
      BleSerializedConnectDisposition.failed => BleConnectionResult.failed(
        owner: owner,
        toolCallId: request.toolCallId,
        deviceId: request.deviceId,
        error: acknowledgement.errorMessage ?? 'Unknown BLE connection error',
      ),
    };
  }

  BleOwnerLifecycleDisposition _lifecycle(
    BleConnectionRuntimeIdentity identity,
  ) {
    try {
      final acknowledgement = _acknowledgeOwner(identity);
      if (!acknowledgement.identity.belongsTo(identity)) {
        return BleOwnerLifecycleDisposition.effectUncertain;
      }
      return acknowledgement.disposition;
    } catch (_) {
      return BleOwnerLifecycleDisposition.effectUncertain;
    }
  }

  bool _matchesLegacyRequest(
    BleConnectionRuntimeIdentity identity,
    ChatTurnOwner owner,
    BleConnectionRequest request,
  ) {
    return identity.owner == owner &&
        identity.toolCallId == request.toolCallId &&
        identity.deviceId == request.deviceId;
  }

  BleConnectionLookupResult _mismatchedLookup(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  ) {
    return BleConnectionLookupResult(
      owner: owner,
      toolCallId: '${request.toolCallId}#runtime-boundary-mismatch',
      deviceId: request.deviceId,
      displayName: null,
    );
  }
}
