import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/immutable_json_snapshot.dart';
import '../../domain/services/participant_tool_executor.dart';
import '../../domain/services/turn_tool_approval_coordinator.dart';

typedef ParticipantToolApprovalCallback =
    Future<ParticipantToolApprovalAcknowledgement> Function(
      ParticipantToolRuntimeApprovalRequest request,
    );
typedef ParticipantToolExecutionCallback =
    Future<ParticipantToolExecutionAcknowledgement> Function(
      ParticipantToolRuntimeExecutionRequest request,
    );
typedef ParticipantToolActivityCallback =
    ParticipantToolActivityAcknowledgement Function(
      ParticipantToolRuntimeActivityRequest request,
    );
typedef ParticipantToolTaintCallback =
    ParticipantToolTaintAcknowledgement Function(
      ParticipantToolRuntimeTaintRequest request,
    );

/// Exact participant invocation identity shared by every runtime boundary.
final class ParticipantToolRuntimeIdentity {
  ParticipantToolRuntimeIdentity({
    required this.scope,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _required(toolCallId, 'toolCallId'),
       toolName = _required(toolName, 'toolName'),
       argumentDigest = _required(argumentDigest, 'argumentDigest');

  final ParticipantToolScope scope;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  ChatTurnOwner get owner => scope.owner;
  String get participantId => scope.participantId;

  @override
  bool operator ==(Object other) =>
      other is ParticipantToolRuntimeIdentity &&
      other.scope == scope &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest;

  @override
  int get hashCode => Object.hash(scope, toolCallId, toolName, argumentDigest);
}

/// Strict immutable input captured before any runtime callback.
final class ParticipantToolRuntimeInput {
  factory ParticipantToolRuntimeInput({
    required ParticipantToolSession session,
    required ToolCallInfo toolCall,
  }) {
    final arguments = ImmutableJsonSnapshot.freezeMap(toolCall.arguments);
    final identity = ParticipantToolRuntimeIdentity(
      scope: session.scope,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      argumentDigest: participantToolArgumentDigest(arguments),
    );
    return ParticipantToolRuntimeInput._(
      session: session,
      identity: identity,
      arguments: arguments,
    );
  }

  const ParticipantToolRuntimeInput._({
    required this.session,
    required this.identity,
    required this.arguments,
  });

  final ParticipantToolSession session;
  final ParticipantToolRuntimeIdentity identity;
  final Map<String, dynamic> arguments;

  ToolCallInfo toToolCall() => ToolCallInfo(
    id: identity.toolCallId,
    name: identity.toolName,
    arguments: arguments,
  );
}

final class ParticipantToolRuntimeApprovalRequest {
  const ParticipantToolRuntimeApprovalRequest({
    required this.identity,
    required this.request,
  });

  final ParticipantToolRuntimeIdentity identity;
  final ParticipantToolApprovalRequest request;
}

enum ParticipantToolApprovalDisposition {
  resolved,
  ownerExpired,
  effectUncertain,
}

final class ParticipantToolApprovalAcknowledgement {
  const ParticipantToolApprovalAcknowledgement({
    required this.identity,
    required this.disposition,
    this.outcome,
  });

  final ParticipantToolRuntimeIdentity identity;
  final ParticipantToolApprovalDisposition disposition;
  final ToolApprovalOutcome? outcome;
}

final class ParticipantToolRuntimeExecutionRequest {
  ParticipantToolRuntimeExecutionRequest({
    required this.identity,
    required Map<String, dynamic> arguments,
  }) : arguments = ImmutableJsonSnapshot.freezeMap(arguments);

  final ParticipantToolRuntimeIdentity identity;
  final Map<String, dynamic> arguments;
}

enum ParticipantToolExecutionDisposition {
  completed,
  rejected,
  ownerExpiredBeforeEffect,
  effectUncertain,
}

final class ParticipantToolExecutionAcknowledgement {
  const ParticipantToolExecutionAcknowledgement({
    required this.identity,
    required this.disposition,
    this.result,
  });

  final ParticipantToolRuntimeIdentity identity;
  final ParticipantToolExecutionDisposition disposition;
  final McpToolResult? result;
}

final class ParticipantToolRuntimeActivityRequest {
  const ParticipantToolRuntimeActivityRequest({
    required this.identity,
    required this.activeToolName,
  });

  final ParticipantToolRuntimeIdentity identity;
  final String activeToolName;
}

enum ParticipantToolActivityDisposition {
  applied,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class ParticipantToolActivityAcknowledgement {
  const ParticipantToolActivityAcknowledgement({
    required this.identity,
    required this.activeToolName,
    required this.disposition,
  });

  final ParticipantToolRuntimeIdentity identity;
  final String activeToolName;
  final ParticipantToolActivityDisposition disposition;
}

final class ParticipantToolRuntimeTaintRequest {
  ParticipantToolRuntimeTaintRequest({
    required this.identity,
    required this.result,
  }) : resultFingerprint = participantToolResultFingerprint(result);

  final ParticipantToolRuntimeIdentity identity;
  final McpToolResult result;
  final String resultFingerprint;
}

enum ParticipantToolTaintDisposition {
  recorded,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class ParticipantToolTaintAcknowledgement {
  const ParticipantToolTaintAcknowledgement({
    required this.identity,
    required this.resultFingerprint,
    required this.disposition,
  });

  final ParticipantToolRuntimeIdentity identity;
  final String resultFingerprint;
  final ParticipantToolTaintDisposition disposition;
}

enum ParticipantToolRuntimeDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
  boundaryMismatch,
}

final class ParticipantToolRuntimeCompletion {
  const ParticipantToolRuntimeCompletion({
    required this.identity,
    required this.disposition,
    required this.result,
  });

  final ParticipantToolRuntimeIdentity identity;
  final ParticipantToolRuntimeDisposition disposition;
  final McpToolResult result;
}

String participantToolArgumentDigest(Map<String, dynamic> arguments) {
  final frozen = ImmutableJsonSnapshot.freezeMap(arguments);
  return _digest(_canonicalJson(frozen));
}

String participantToolResultFingerprint(McpToolResult result) {
  return _digest({
    'toolName': result.toolName,
    'result': result.result,
    'isSuccess': result.isSuccess,
    'isExternalMcpResult': result.isExternalMcpResult,
    'errorMessage': result.errorMessage,
  });
}

String _required(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return value;
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

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
