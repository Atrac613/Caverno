import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/immutable_json_snapshot.dart';
import '../../domain/services/serial_connection_attempt_coordinator.dart';
import '../../domain/services/serial_connection_tool_handler.dart';
import '../../domain/services/turn_tool_approval_coordinator.dart';
import 'serial_port_connection_adapter.dart';

export '../../domain/services/serial_connection_attempt_coordinator.dart'
    show
        SerialConnectionAttemptLease,
        SerialConnectionOpenedReceipt,
        SerialConnectionRetirementResult;
export 'serial_port_connection_adapter.dart'
    show SerialSessionCloseKind, SerialSessionPort;

const String canonicalSerialOpenToolName = 'serial_open';

/// Immutable approval inputs captured with one serial tool invocation.
final class SerialConnectionApprovalFacts {
  SerialConnectionApprovalFacts({
    required this.mode,
    List<Message> conversationMessages = const <Message>[],
    this.hasUntrustedInfluence = false,
  }) : conversationMessages = List<Message>.unmodifiable(conversationMessages);

  final ToolApprovalMode mode;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;
}

/// Exact owner, tool call, tool name, and argument identity at dispatch time.
final class SerialConnectionRuntimeIdentity {
  SerialConnectionRuntimeIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _requiredExact(toolCallId, 'toolCallId'),
       toolName = _canonicalToolName(toolName),
       argumentDigest = _requiredExact(argumentDigest, 'argumentDigest');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  bool belongsTo(SerialConnectionRuntimeIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) =>
      other is SerialConnectionRuntimeIdentity &&
      other.owner == owner &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest;

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

/// Strict snapshot used to enter the persistent serial runtime.
final class SerialConnectionRuntimeInput {
  factory SerialConnectionRuntimeInput({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required SerialConnectionApprovalFacts approval,
  }) {
    final arguments = ImmutableJsonSnapshot.freezeMap(toolCall.arguments);
    return SerialConnectionRuntimeInput._(
      identity: SerialConnectionRuntimeIdentity(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        argumentDigest: serialConnectionArgumentDigest(arguments),
      ),
      arguments: arguments,
      approval: approval,
    );
  }

  const SerialConnectionRuntimeInput._({
    required this.identity,
    required this.arguments,
    required this.approval,
  });

  final SerialConnectionRuntimeIdentity identity;
  final Map<String, dynamic> arguments;
  final SerialConnectionApprovalFacts approval;

  SerialConnectionToolRequest toToolRequest() => SerialConnectionToolRequest(
    owner: identity.owner,
    toolCallId: identity.toolCallId,
    toolName: identity.toolName,
    arguments: arguments,
    approvalMode: approval.mode,
    conversationMessages: approval.conversationMessages,
    hasUntrustedInfluence: approval.hasUntrustedInfluence,
  );
}

/// Persistent production composition for owner-bound serial opens.
final class SerialConnectionToolRuntimeAdapter {
  factory SerialConnectionToolRuntimeAdapter({
    required SerialSessionPort sessionPort,
    required bool Function(ChatTurnOwner owner) ownerIsCurrent,
    required TurnToolApprovalCoordinator approvalCoordinator,
    required SerialConnectionAttemptCoordinator attemptCoordinator,
  }) {
    final connectionPort = SerialPortConnectionAdapter(
      service: sessionPort,
      ownerIsCurrent: ownerIsCurrent,
    );
    return SerialConnectionToolRuntimeAdapter._(
      approvalCoordinator: approvalCoordinator,
      attemptCoordinator: attemptCoordinator,
      handler: SerialConnectionToolHandler(
        connectionPort: connectionPort,
        approvalCoordinator: approvalCoordinator,
        attemptCoordinator: attemptCoordinator,
      ),
    );
  }

  SerialConnectionToolRuntimeAdapter._({
    required TurnToolApprovalCoordinator approvalCoordinator,
    required SerialConnectionAttemptCoordinator attemptCoordinator,
    required SerialConnectionToolHandler handler,
  }) : _approvalCoordinator = approvalCoordinator,
       _attemptCoordinator = attemptCoordinator,
       _handler = handler;

  final TurnToolApprovalCoordinator _approvalCoordinator;
  final SerialConnectionAttemptCoordinator _attemptCoordinator;
  final SerialConnectionToolHandler _handler;
  final Set<ChatTurnOwner> _observedOwners = <ChatTurnOwner>{};

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required SerialConnectionApprovalFacts approval,
  }) {
    final input = SerialConnectionRuntimeInput(
      owner: owner,
      toolCall: toolCall,
      approval: approval,
    );
    _observedOwners.add(owner);
    return _handler.handle(input.toToolRequest());
  }

  List<SerialConnectionOpenedReceipt> get pendingCleanupReceipts =>
      _attemptCoordinator.pendingCleanupReceipts;

  List<SerialConnectionAttemptLease> get pendingEffectLeases =>
      _attemptCoordinator.pendingEffectLeases;

  SerialConnectionRetirementResult retireOwner(ChatTurnOwner owner) {
    _observedOwners.remove(owner);
    _approvalCoordinator.clearOwner(owner);
    return _attemptCoordinator.clearOwner(owner);
  }

  SerialConnectionRetirementResult retireAll() {
    for (final owner in _observedOwners) {
      _approvalCoordinator.clearOwner(owner);
    }
    _observedOwners.clear();
    _approvalCoordinator.clearAll();
    return _attemptCoordinator.clearAll();
  }

  Future<bool> retryPendingCleanup(SerialConnectionOpenedReceipt receipt) =>
      _handler.retryPendingCleanup(receipt);

  bool settlePendingOpenNoEffect(SerialConnectionAttemptLease lease) =>
      _handler.settlePendingOpenNoEffect(lease);

  Future<bool> rollbackPendingOpen(
    SerialConnectionAttemptLease lease, {
    required String sessionFingerprint,
  }) => _handler.rollbackPendingOpen(
    lease,
    sessionFingerprint: sessionFingerprint,
  );
}

String serialConnectionArgumentDigest(Map<String, dynamic> arguments) {
  final frozen = ImmutableJsonSnapshot.freezeMap(arguments);
  return sha256
      .convert(utf8.encode(jsonEncode(_canonicalJson(frozen))))
      .toString();
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

String _canonicalToolName(String value) {
  if (value != canonicalSerialOpenToolName) {
    throw ArgumentError.value(
      value,
      'toolName',
      'toolName must be exactly $canonicalSerialOpenToolName.',
    );
  }
  return value;
}

String _requiredExact(String value, String name) {
  if (value.isEmpty || value != value.trim()) {
    throw ArgumentError.value(
      value,
      name,
      '$name must be exact and non-empty.',
    );
  }
  return value;
}
