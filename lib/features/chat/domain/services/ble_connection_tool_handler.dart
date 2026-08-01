import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import 'tool_approval_auto_review_service.dart';
import 'turn_tool_approval_coordinator.dart';

// ChatNotifier decomposition collaborator: ble-connection-tool-handler

/// Immutable BLE target selected explicitly by the tool request.
final class BleConnectionRequest {
  const BleConnectionRequest({
    required this.toolCallId,
    required this.deviceId,
  });

  final String toolCallId;
  final String deviceId;
}

/// Owner-bound display metadata returned by the BLE scan adapter.
final class BleConnectionLookupResult {
  const BleConnectionLookupResult({
    required this.owner,
    required this.toolCallId,
    required this.deviceId,
    required this.displayName,
  });

  final ChatTurnOwner owner;
  final String toolCallId;
  final String deviceId;
  final String? displayName;

  bool belongsTo(ChatTurnOwner expectedOwner, BleConnectionRequest request) {
    return owner == expectedOwner &&
        toolCallId == request.toolCallId &&
        deviceId == request.deviceId;
  }
}

enum BleConnectionResultKind { connected, ownerExpired, failed }

/// Owner-bound completion returned after the port revalidates the turn.
final class BleConnectionResult {
  const BleConnectionResult.connected({
    required this.owner,
    required this.toolCallId,
    required this.deviceId,
  }) : kind = BleConnectionResultKind.connected,
       errorMessage = null;

  const BleConnectionResult.ownerExpired({
    required this.owner,
    required this.toolCallId,
    required this.deviceId,
  }) : kind = BleConnectionResultKind.ownerExpired,
       errorMessage = null;

  BleConnectionResult.failed({
    required this.owner,
    required this.toolCallId,
    required this.deviceId,
    required Object error,
  }) : kind = BleConnectionResultKind.failed,
       errorMessage = error.toString();

  final ChatTurnOwner owner;
  final String toolCallId;
  final String deviceId;
  final BleConnectionResultKind kind;
  final String? errorMessage;

  bool belongsTo(ChatTurnOwner expectedOwner, BleConnectionRequest request) {
    return owner == expectedOwner &&
        toolCallId == request.toolCallId &&
        deviceId == request.deviceId;
  }
}

/// Looks up and connects only within the exact conversation generation.
///
/// Implementations must revalidate [owner] after every asynchronous boundary.
/// A connection that completes for an expired owner must be rolled back before
/// returning [BleConnectionResult.ownerExpired].
abstract interface class BleConnectionPort {
  Future<BleConnectionLookupResult> lookupDisplayName(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  );

  Future<BleConnectionResult> connect(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  );
}

/// Immutable input for one `ble_connect` tool execution.
final class BleConnectionToolRequest {
  BleConnectionToolRequest({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required String deviceId,
    required this.approvalMode,
    this.reason,
    List<Message> conversationMessages = const [],
    this.hasUntrustedInfluence = false,
  }) : deviceId = deviceId.trim(),
       conversationMessages = List<Message>.unmodifiable(conversationMessages);

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String deviceId;
  final ToolApprovalMode approvalMode;
  final String? reason;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;
}

/// Executes an owner-scoped BLE connection without notifier or UI state.
final class BleConnectionToolHandler {
  const BleConnectionToolHandler({
    required BleConnectionPort connectionPort,
    required TurnToolApprovalCoordinator approvalCoordinator,
  }) : _connectionPort = connectionPort,
       _approvalCoordinator = approvalCoordinator;

  static const String _expiredMessage =
      'The approval turn expired before execution';
  static const String _effectsUncertainMessage =
      'The BLE connection may have completed after its owner expired or its '
      'completion identity changed; inspect possible side effects before '
      'retrying';
  static const String _canonicalToolName = 'ble_connect';

  final BleConnectionPort _connectionPort;
  final TurnToolApprovalCoordinator _approvalCoordinator;

  Future<McpToolResult> handle(BleConnectionToolRequest request) async {
    if (request.toolName != _canonicalToolName) {
      return _failure(
        request.toolName,
        'BleConnectionToolHandler only accepts ble_connect',
      );
    }
    if (request.toolCallId.trim().isEmpty) {
      return _failure(request.toolName, 'tool_call_id is required');
    }
    if (request.deviceId.isEmpty) {
      return _failure(request.toolName, 'device_id is required');
    }

    final approvalArguments = <String, dynamic>{'device_id': request.deviceId};
    final approvalRequest = ToolApprovalRequest(
      owner: request.owner,
      toolCallId: request.toolCallId,
      toolName: request.toolName,
      arguments: approvalArguments,
      actionKind: 'ble_connect',
      mode: request.approvalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: true,
      cacheArguments: {'device_id': request.deviceId},
      reason: request.reason,
      conversationMessages: request.conversationMessages,
      hasUntrustedInfluence: request.hasUntrustedInfluence,
    );
    final preflight = await _approvalCoordinator.preflightCachedDenial(
      approvalRequest,
    );
    if (preflight.outcome?.denialResult case final denial?) return denial;

    final connectionRequest = BleConnectionRequest(
      toolCallId: request.toolCallId,
      deviceId: request.deviceId,
    );
    final BleConnectionLookupResult lookupResult;
    try {
      lookupResult = await _connectionPort.lookupDisplayName(
        request.owner,
        connectionRequest,
      );
    } catch (error) {
      return _approvalCoordinator.expiredResult(approvalRequest) ??
          _failure(request.toolName, 'BLE connect failed: $error');
    }
    if (!lookupResult.belongsTo(request.owner, connectionRequest)) {
      return _expired(request.toolName);
    }

    final approval = await _approvalCoordinator.resolveAfterPreflight(
      preflight,
      targetDisplayName: lookupResult.displayName,
    );
    if (approval.denialResult case final denial?) return denial;

    final BleConnectionResult connection;
    try {
      connection = await _connectionPort.connect(
        request.owner,
        connectionRequest,
      );
    } catch (error) {
      return _approvalCoordinator.expiredResult(approvalRequest) == null
          ? _failure(request.toolName, 'BLE connect failed: $error')
          : _effectsUncertain(request.toolName);
    }
    if (!connection.belongsTo(request.owner, connectionRequest)) {
      return _effectsUncertain(request.toolName);
    }
    if (connection.kind == BleConnectionResultKind.ownerExpired ||
        _approvalCoordinator.expiredResult(approvalRequest) != null) {
      return _effectsUncertain(request.toolName);
    }
    final McpToolResult result;
    if (connection.kind == BleConnectionResultKind.connected) {
      result = McpToolResult(
        toolName: request.toolName,
        result: 'Connected to ${lookupResult.displayName ?? request.deviceId}',
        isSuccess: true,
      );
    } else {
      result = _failure(
        request.toolName,
        'BLE connect failed: ${connection.errorMessage}',
      );
    }
    return approval.gateDecision!.bypassedApproval
        ? result
        : _approvalCoordinator.rememberApprovalResult(approvalRequest, result);
  }

  McpToolResult _expired(String toolName) {
    return _failure(toolName, _expiredMessage);
  }

  McpToolResult _effectsUncertain(String toolName) {
    return _failure(toolName, _effectsUncertainMessage);
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
