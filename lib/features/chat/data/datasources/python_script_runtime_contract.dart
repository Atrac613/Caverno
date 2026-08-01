import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/python_script_tool_contract.dart';
import '../../domain/services/python_staging_lease_registry.dart';
import 'python_execution_authority.dart';

typedef PythonOwnerMessagesCallback =
    PythonRuntimeAcknowledgement<PythonScriptInvocationIdentity, List<Message>>
    Function(PythonScriptInvocationIdentity identity);
typedef PythonRuntimeLifecycleCallback =
    PythonRuntimeAcknowledgement<PythonScriptRuntimeIdentity, Object?> Function(
      PythonScriptRuntimeIdentity identity,
    );
typedef PythonRuntimeStagingCallback =
    Future<
      PythonRuntimeAcknowledgement<
        PythonScriptRuntimeIdentity,
        PythonStagingAllocation
      >
    >
    Function(PythonRuntimeStagingRequest request);
typedef PythonRuntimeCleanupCallback =
    Future<
      PythonRuntimeAcknowledgement<
        PythonStagingCleanupIdentity,
        PythonStagingCleanupOutcome
      >
    >
    Function(PythonRuntimeCleanupRequest request);
typedef PythonRuntimeDenialLookupCallback =
    PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, McpToolResult?>
    Function(PythonRuntimeCacheRequest request);
typedef PythonRuntimeGateCallback =
    Future<
      PythonRuntimeAcknowledgement<
        PythonApprovalRuntimeIdentity,
        ToolApprovalGateDecision
      >
    >
    Function(PythonRuntimeApprovalRequest request);
typedef PythonRuntimeManualApprovalCallback =
    Future<PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, bool>>
    Function(PythonRuntimeApprovalRequest request);
typedef PythonRuntimeCacheWriteCallback =
    PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, Object?>
    Function(PythonRuntimeCacheWriteRequest request);
typedef PythonRuntimeExecutionCallback =
    Future<
      PythonRuntimeAcknowledgement<
        PythonExecutionRuntimeIdentity,
        McpToolResult
      >
    >
    Function(PythonRuntimeExecutionRequest request);

final class PythonScriptInvocationIdentity {
  PythonScriptInvocationIdentity({
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

  @override
  bool operator ==(Object other) =>
      other is PythonScriptInvocationIdentity &&
      other.owner == owner &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest;

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

final class PythonScriptRuntimeInput {
  factory PythonScriptRuntimeInput({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) {
    final arguments = freezePythonToolMap(toolCall.arguments);
    return PythonScriptRuntimeInput._(
      identity: PythonScriptInvocationIdentity(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        argumentDigest: pythonRuntimeJsonDigest(arguments),
      ),
      arguments: arguments,
    );
  }

  const PythonScriptRuntimeInput._({
    required this.identity,
    required this.arguments,
  });

  final PythonScriptInvocationIdentity identity;
  final Map<String, dynamic> arguments;

  PythonScriptToolRequest toToolRequest(List<Message> messages) {
    return PythonScriptToolRequest(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      toolName: identity.toolName,
      ownerMessages: PythonOwnerMessageSnapshot(
        owner: identity.owner,
        messages: messages,
      ),
      arguments: arguments,
    );
  }
}

final class PythonScriptRuntimeIdentity {
  PythonScriptRuntimeIdentity({
    required this.invocation,
    required List<Message> ownerMessages,
  }) : ownerMessageDigest = pythonOwnerMessageDigest(ownerMessages);

  final PythonScriptInvocationIdentity invocation;
  final String ownerMessageDigest;

  ChatTurnOwner get owner => invocation.owner;
  String get toolCallId => invocation.toolCallId;
  String get toolName => invocation.toolName;

  @override
  bool operator ==(Object other) =>
      other is PythonScriptRuntimeIdentity &&
      other.invocation == invocation &&
      other.ownerMessageDigest == ownerMessageDigest;

  @override
  int get hashCode => Object.hash(invocation, ownerMessageDigest);
}

enum PythonRuntimeAcknowledgementDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class PythonRuntimeAcknowledgement<I, T> {
  const PythonRuntimeAcknowledgement({
    required this.identity,
    required this.disposition,
    this.value,
    this.message,
  });

  final I identity;
  final PythonRuntimeAcknowledgementDisposition disposition;
  final T? value;
  final String? message;
}

final class PythonRuntimeStagingRequest {
  PythonRuntimeStagingRequest({
    required this.identity,
    required this.attempt,
    required this.attachment,
  }) {
    _requireAttempt(identity, attempt);
  }

  final PythonScriptRuntimeIdentity identity;
  final PythonStagingAttempt attempt;
  final PythonInputAttachment? attachment;
}

final class PythonStagingCleanupIdentity {
  PythonStagingCleanupIdentity({
    required this.runtime,
    required this.attempt,
    required this.directoryIdentity,
  }) {
    _requireAttempt(runtime, attempt);
  }

  final PythonScriptRuntimeIdentity runtime;
  final PythonStagingAttempt attempt;
  final PythonStagingDirectoryIdentity directoryIdentity;

  @override
  bool operator ==(Object other) =>
      other is PythonStagingCleanupIdentity &&
      other.runtime == runtime &&
      other.attempt == attempt &&
      other.directoryIdentity == directoryIdentity;

  @override
  int get hashCode => Object.hash(runtime, attempt, directoryIdentity);
}

final class PythonRuntimeCleanupRequest {
  const PythonRuntimeCleanupRequest({required this.identity});

  final PythonStagingCleanupIdentity identity;
}

final class PythonApprovalRuntimeIdentity {
  PythonApprovalRuntimeIdentity({
    required this.runtime,
    required Map<String, dynamic> cacheArguments,
  }) : cacheArgumentDigest = pythonRuntimeJsonDigest(cacheArguments);

  final PythonScriptRuntimeIdentity runtime;
  final String cacheArgumentDigest;

  @override
  bool operator ==(Object other) =>
      other is PythonApprovalRuntimeIdentity &&
      other.runtime == runtime &&
      other.cacheArgumentDigest == cacheArgumentDigest;

  @override
  int get hashCode => Object.hash(runtime, cacheArgumentDigest);
}

final class PythonRuntimeCacheRequest {
  PythonRuntimeCacheRequest({
    required this.identity,
    required Map<String, dynamic> cacheArguments,
  }) : cacheArguments = freezePythonToolMap(cacheArguments) {
    if (pythonRuntimeJsonDigest(this.cacheArguments) !=
        identity.cacheArgumentDigest) {
      throw ArgumentError(
        'Python cache arguments do not match their exact identity.',
      );
    }
  }

  final PythonApprovalRuntimeIdentity identity;
  final Map<String, dynamic> cacheArguments;
}

final class PythonRuntimeApprovalRequest {
  const PythonRuntimeApprovalRequest({
    required this.identity,
    required this.toolRequest,
  });

  final PythonApprovalRuntimeIdentity identity;
  final PythonScriptApprovalRequest toolRequest;

  String get code => toolRequest.code;
  String? get reason => toolRequest.reason;
  PythonStagedInputs get stagedInputs => toolRequest.stagedInputs;
}

final class PythonRuntimeCacheWriteRequest {
  const PythonRuntimeCacheWriteRequest({
    required this.cacheRequest,
    required this.result,
  });

  final PythonRuntimeCacheRequest cacheRequest;
  final McpToolResult result;

  PythonApprovalRuntimeIdentity get identity => cacheRequest.identity;
}

final class PythonExecutionRuntimeIdentity {
  PythonExecutionRuntimeIdentity({
    required this.runtime,
    required this.directoryIdentity,
    required Map<String, dynamic> arguments,
  }) : argumentDigest = pythonRuntimeJsonDigest(arguments);

  final PythonScriptRuntimeIdentity runtime;
  final PythonStagingDirectoryIdentity directoryIdentity;
  final String argumentDigest;

  @override
  bool operator ==(Object other) =>
      other is PythonExecutionRuntimeIdentity &&
      other.runtime == runtime &&
      other.directoryIdentity == directoryIdentity &&
      other.argumentDigest == argumentDigest;

  @override
  int get hashCode => Object.hash(runtime, directoryIdentity, argumentDigest);
}

typedef PythonScriptExecutionAuthority =
    PythonExecutionAuthority<PythonExecutionRuntimeIdentity>;
typedef PythonScriptExecutionEffectPermit =
    PythonExecutionEffectPermit<PythonExecutionRuntimeIdentity>;
typedef PythonScriptExecutionRecoveryReceipt =
    PythonExecutionRecoveryReceipt<PythonExecutionRuntimeIdentity>;

final class PythonRuntimeExecutionRequest {
  PythonRuntimeExecutionRequest({
    required this.identity,
    required Map<String, dynamic> arguments,
    required PythonScriptExecutionEffectPermit effectPermit,
  }) : arguments = freezePythonToolMap(arguments) {
    if (pythonRuntimeJsonDigest(this.arguments) != identity.argumentDigest) {
      throw ArgumentError(
        'Python execution arguments do not match their exact identity.',
      );
    }
    if (effectPermit.identity != identity) {
      throw ArgumentError(
        'Python execution permit does not match its exact identity.',
      );
    }
    _effectPermit = effectPermit;
  }

  final PythonExecutionRuntimeIdentity identity;
  final Map<String, dynamic> arguments;
  late final PythonScriptExecutionEffectPermit _effectPermit;

  String get toolName => identity.runtime.toolName;

  /// Runs the actual process effect under the exact one-use permit.
  Future<T> runEffect<T>(Future<T> Function() effect) {
    return _effectPermit.runEffect(effect);
  }
}

enum PythonScriptRuntimeDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class PythonScriptRuntimeCompletion {
  const PythonScriptRuntimeCompletion({
    required this.identity,
    required this.disposition,
    required this.result,
  });

  final PythonScriptRuntimeIdentity identity;
  final PythonScriptRuntimeDisposition disposition;
  final McpToolResult result;
}

McpToolResult pythonRuntimeFailure(
  String toolName,
  PythonScriptRuntimeDisposition disposition,
  String message,
) {
  final code = switch (disposition) {
    PythonScriptRuntimeDisposition.completed => throw StateError(
      'Completed Python operations do not use failure results.',
    ),
    PythonScriptRuntimeDisposition.rejected => 'python_script_rejected',
    PythonScriptRuntimeDisposition.ownerExpired => 'turn_owner_expired',
    PythonScriptRuntimeDisposition.effectUncertain =>
      'python_script_effect_uncertain',
  };
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': code,
      'error': message,
      'next_action': disposition == PythonScriptRuntimeDisposition.ownerExpired
          ? 'Repeat the tool call in the current turn.'
          : 'Inspect possible effects before retrying.',
    }),
    isSuccess: false,
    errorMessage: message,
  );
}

String pythonRuntimeJsonDigest(Map<String, dynamic> arguments) {
  final frozen = freezePythonToolMap(arguments);
  return _digest(_canonicalJson(frozen));
}

String pythonOwnerMessageDigest(List<Message> messages) {
  return _digest([
    for (final message in messages)
      <String, Object?>{
        'id': message.id,
        'content': message.content,
        'role': message.role.name,
        'timestamp': message.timestamp.toIso8601String(),
        'isStreaming': message.isStreaming,
        'error': message.error,
        'imageBase64': message.imageBase64,
        'imageMimeType': message.imageMimeType,
        'originalImagePath': message.originalImagePath,
        'originalImageMimeType': message.originalImageMimeType,
        'participantId': message.participantId,
        'participantDisplayName': message.participantDisplayName,
        'participantRoleLabel': message.participantRoleLabel,
        'participantColorValue': message.participantColorValue,
        'participantToolNames': [...message.participantToolNames],
        'handoffTargetParticipantId': message.handoffTargetParticipantId,
        'handoffTargetDisplayName': message.handoffTargetDisplayName,
        'handoffTargetRoleLabel': message.handoffTargetRoleLabel,
        'responseMetrics': switch (message.responseMetrics) {
          null => null,
          final metrics => <String, Object?>{
            'promptTokens': metrics.promptTokens,
            'completionTokens': metrics.completionTokens,
            'totalTokens': metrics.totalTokens,
            'elapsedMilliseconds': metrics.elapsedMilliseconds,
            'finishReason': metrics.finishReason,
          },
        },
      },
  ]);
}

void _requireAttempt(
  PythonScriptRuntimeIdentity identity,
  PythonStagingAttempt attempt,
) {
  if (attempt.owner != identity.owner ||
      attempt.toolCallId != identity.toolCallId ||
      attempt.toolName != identity.toolName) {
    throw ArgumentError('Python staging attempt identity mismatch.');
  }
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

String _digest(Object? value) {
  return sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

String _canonicalToolName(String value) {
  if (value != PythonScriptToolRequest.canonicalToolName) {
    throw ArgumentError.value(
      value,
      'toolName',
      'The Python runtime accepts only run_python_script.',
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
