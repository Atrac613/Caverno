import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/message.dart';
import 'immutable_json_snapshot.dart';

/// Immutable serial settings forwarded without transport interpretation.
final class SerialConnectionOptions {
  const SerialConnectionOptions({
    required this.baudRate,
    required this.dataBits,
    required this.parity,
    required this.stopBits,
    required this.flowControl,
  });

  final int baudRate;
  final int dataBits;
  final String parity;
  final int stopBits;
  final String flowControl;

  bool hasSameValues(SerialConnectionOptions other) {
    return baudRate == other.baudRate &&
        dataBits == other.dataBits &&
        parity == other.parity &&
        stopBits == other.stopBits &&
        flowControl == other.flowControl;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SerialConnectionOptions && hasSameValues(other);
  }

  @override
  int get hashCode {
    return Object.hash(baudRate, dataBits, parity, stopBits, flowControl);
  }
}

/// Explicit serial target passed to the owner-aware transport adapter.
final class SerialConnectionRequest {
  const SerialConnectionRequest({
    required this.toolCallId,
    required this.portName,
    required this.options,
  });

  final String toolCallId;
  final String portName;
  final SerialConnectionOptions options;

  Map<String, dynamic> toArguments() {
    return <String, dynamic>{
      'port': portName,
      'baud_rate': options.baudRate,
      'data_bits': options.dataBits,
      'parity': options.parity,
      'stop_bits': options.stopBits,
      'flow_control': options.flowControl,
    };
  }

  bool hasSameTarget(SerialConnectionRequest other) {
    return toolCallId == other.toolCallId &&
        portName == other.portName &&
        options == other.options;
  }
}

enum SerialConnectionResultKind { completed, ownerExpired, failed }

/// Owner-bound serial completion after the adapter revalidates the turn.
final class SerialConnectionResult {
  const SerialConnectionResult.completed({
    required this.owner,
    required this.request,
    required String this.resultJson,
    required this.sessionFingerprint,
  }) : kind = SerialConnectionResultKind.completed,
       errorMessage = null;

  const SerialConnectionResult.ownerExpired({
    required this.owner,
    required this.request,
    required this.resultJson,
    required this.sessionFingerprint,
  }) : kind = SerialConnectionResultKind.ownerExpired,
       errorMessage = null;

  SerialConnectionResult.failed({
    required this.owner,
    required this.request,
    required Object error,
  }) : kind = SerialConnectionResultKind.failed,
       resultJson = null,
       sessionFingerprint = null,
       errorMessage = error.toString();

  final ChatTurnOwner owner;
  final SerialConnectionRequest request;
  final SerialConnectionResultKind kind;
  final String? resultJson;
  final String? sessionFingerprint;
  final String? errorMessage;

  bool belongsTo(
    ChatTurnOwner expectedOwner,
    SerialConnectionRequest expectedRequest,
  ) {
    return owner == expectedOwner && request.hasSameTarget(expectedRequest);
  }
}

enum SerialConnectionRollbackKind {
  closed,
  alreadyAbsent,
  sessionMismatch,
  failed,
}

/// Exact completion for a conditional serial-session rollback.
final class SerialConnectionRollbackResult {
  const SerialConnectionRollbackResult.closed({
    required this.owner,
    required this.request,
    required this.expectedSessionFingerprint,
  }) : kind = SerialConnectionRollbackKind.closed,
       errorMessage = null;

  const SerialConnectionRollbackResult.alreadyAbsent({
    required this.owner,
    required this.request,
    required this.expectedSessionFingerprint,
  }) : kind = SerialConnectionRollbackKind.alreadyAbsent,
       errorMessage = null;

  const SerialConnectionRollbackResult.sessionMismatch({
    required this.owner,
    required this.request,
    required this.expectedSessionFingerprint,
  }) : kind = SerialConnectionRollbackKind.sessionMismatch,
       errorMessage = null;

  SerialConnectionRollbackResult.failed({
    required this.owner,
    required this.request,
    required this.expectedSessionFingerprint,
    required Object error,
  }) : kind = SerialConnectionRollbackKind.failed,
       errorMessage = error.toString();

  final ChatTurnOwner owner;
  final SerialConnectionRequest request;
  final String expectedSessionFingerprint;
  final SerialConnectionRollbackKind kind;
  final String? errorMessage;

  bool belongsTo(
    ChatTurnOwner expectedOwner,
    SerialConnectionRequest expectedRequest,
    String expectedFingerprint,
  ) {
    return owner == expectedOwner &&
        request.hasSameTarget(expectedRequest) &&
        expectedSessionFingerprint == expectedFingerprint;
  }
}

/// Immutable input for one `serial_open` tool execution.
final class SerialConnectionToolRequest {
  SerialConnectionToolRequest({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required Map<String, dynamic> arguments,
    required this.approvalMode,
    List<Message> conversationMessages = const [],
    this.hasUntrustedInfluence = false,
  }) : arguments = _freezeMap(arguments),
       conversationMessages = List<Message>.unmodifiable(conversationMessages);

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final ToolApprovalMode approvalMode;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}
