import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'computer_use_action_policy.dart';
import 'computer_use_runtime_coordinator.dart';

/// Immutable Computer Use invocation captured for one exact runtime session.
final class ComputerUseToolRequest {
  factory ComputerUseToolRequest({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String runtimeSessionId,
    required int runtimeRevision,
    required DateTime authorizationExpiresAt,
  }) {
    final action = ComputerUseActionInput(
      toolName: toolName.trim(),
      arguments: arguments,
    );
    final argumentDigest = sha256
        .convert(utf8.encode(jsonEncode(action.arguments)))
        .toString();
    return ComputerUseToolRequest._(
      identity: ComputerUseOperationIdentity(
        owner: owner,
        toolCallId: toolCallId,
        toolName: action.toolName,
        argumentDigest: argumentDigest,
        runtimeSessionId: runtimeSessionId,
      ),
      action: action,
      runtimeRevision: runtimeRevision,
      authorizationExpiresAt: authorizationExpiresAt,
    );
  }

  const ComputerUseToolRequest._({
    required this.identity,
    required this.action,
    required this.runtimeRevision,
    required this.authorizationExpiresAt,
  });

  final ComputerUseOperationIdentity identity;
  final ComputerUseActionInput action;
  final int runtimeRevision;
  final DateTime authorizationExpiresAt;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;
  String get argumentDigest => identity.argumentDigest;
  String get runtimeSessionId => identity.runtimeSessionId;
  Map<String, dynamic> get arguments => action.arguments;
  String? get reason => arguments['reason'] as String?;
}

/// Current helper state used to fence a captured Computer Use request.
final class ComputerUseRuntimeState {
  ComputerUseRuntimeState({required String sessionId, required this.revision})
    : sessionId = _requiredValue(sessionId, 'sessionId') {
    RangeError.checkNotNegative(revision, 'revision');
  }

  final String sessionId;
  final int revision;

  bool matches(ComputerUseToolRequest request) {
    return sessionId == request.runtimeSessionId &&
        revision == request.runtimeRevision;
  }

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }
    return normalized;
  }
}

/// Reads the live helper identity immediately before runtime side effects.
abstract interface class ComputerUseRuntimeStatePort {
  ComputerUseRuntimeState capture();
}

/// Exact operation identity attached to every asynchronous port completion.
final class ComputerUseOwnedValue<T> {
  const ComputerUseOwnedValue({required this.identity, required this.value});

  final ComputerUseOperationIdentity identity;
  final T value;

  bool belongsTo(ComputerUseToolRequest request) =>
      identity == request.identity;
}

/// Exact acknowledgement for a cache or audit write.
final class ComputerUseEffectAcknowledgement {
  const ComputerUseEffectAcknowledgement({
    required this.identity,
    required this.accepted,
  });

  final ComputerUseOperationIdentity identity;
  final bool accepted;

  bool belongsTo(ComputerUseToolRequest request) =>
      identity == request.identity;
}

/// Immutable manual Computer Use approval decision.
final class ComputerUseApprovalDecision {
  const ComputerUseApprovalDecision({
    required this.approved,
    required this.armed,
    this.blockerCode,
  });

  final bool approved;
  final bool armed;
  final String? blockerCode;
}

/// Either a typed manual decision or a terminal approval-system result.
final class ComputerUseApprovalOutcome {
  const ComputerUseApprovalOutcome.decided(
    ComputerUseApprovalDecision this.decision,
  ) : immediateResult = null;

  const ComputerUseApprovalOutcome.immediate(McpToolResult this.immediateResult)
    : decision = null;

  final ComputerUseApprovalDecision? decision;
  final McpToolResult? immediateResult;
}

/// Immutable approval presentation detached from notifier and UI state.
final class ComputerUseApprovalRequest {
  ComputerUseApprovalRequest({
    required this.toolRequest,
    required this.toolPolicy,
    required this.actionProposalPolicy,
    required this.presentation,
    required Map<String, dynamic>? target,
    required this.exactText,
    required this.visionContext,
    required List<String> details,
  }) : target = target == null ? null : freezeComputerUseArguments(target),
       details = List<String>.unmodifiable(details);

  final ComputerUseToolRequest toolRequest;
  final MacosComputerUseToolPolicyDecision? toolPolicy;
  final MacosComputerUseActionProposalPolicyDecision? actionProposalPolicy;
  final ComputerUseActionPresentation presentation;
  final Map<String, dynamic>? target;
  final String? exactText;
  final ComputerUseContext visionContext;
  final List<String> details;

  String? get reason => toolRequest.reason;
}

/// Immutable post-action observation request.
final class ComputerUseObservationRequest {
  ComputerUseObservationRequest({
    required this.toolRequest,
    required this.actionResult,
    required this.observationToolName,
    required Map<String, dynamic> arguments,
  }) : arguments = freezeComputerUseArguments(arguments);

  final ComputerUseToolRequest toolRequest;
  final McpToolResult actionResult;
  final String observationToolName;
  final Map<String, dynamic> arguments;
}

/// Outcome of selecting and running the policy-required observation.
final class ComputerUseObservationRun {
  const ComputerUseObservationRun.absent()
    : runtimeExpired = false,
      observation = null;

  const ComputerUseObservationRun.observed(this.observation)
    : runtimeExpired = false;

  const ComputerUseObservationRun.runtimeExpired()
    : runtimeExpired = true,
      observation = null;

  final bool runtimeExpired;
  final ComputerUsePostActionObservation? observation;
}

/// Immutable Computer Use audit event emitted at the legacy call sites.
final class ComputerUseAuditRecord {
  const ComputerUseAuditRecord({
    required this.toolName,
    required this.policy,
    required this.approvalResult,
    required this.success,
    this.result,
    this.errorCode,
    this.postActionObservation,
    this.effectUncertain = false,
  });

  final String toolName;
  final MacosComputerUseToolPolicyDecision? policy;
  final String approvalResult;
  final bool success;
  final String? result;
  final String? errorCode;
  final ComputerUsePostActionObservation? postActionObservation;
  final bool effectUncertain;
}

/// Executes only an explicitly authorized runtime action.
abstract interface class ComputerUseExecutionPort {
  Future<ComputerUseOwnedValue<McpToolResult>> execute(
    ComputerUseToolRequest request,
    ComputerUseRuntimeLease lease,
  );

  ComputerUseEffectAcknowledgement recordAudit(
    ComputerUseToolRequest request,
    ComputerUseAuditRecord record,
  );
}

/// Owns approval UI and exact-operation denial reuse.
abstract interface class ComputerUseApprovalPort {
  bool isOwnerCurrent(ChatTurnOwner owner);

  ComputerUseOwnedValue<McpToolResult>? lookupDenial(
    ComputerUseToolRequest request,
  );

  Future<ComputerUseOwnedValue<ComputerUseApprovalOutcome>> requestApproval(
    ComputerUseApprovalRequest request,
  );

  ComputerUseEffectAcknowledgement rememberDenial(
    ComputerUseToolRequest request,
    McpToolResult result,
  );
}

/// Runs one explicitly selected observation under the same runtime lease.
abstract interface class ComputerUseObservationPort {
  Future<ComputerUseOwnedValue<ComputerUsePostActionObservation>> observe(
    ComputerUseObservationRequest request,
    ComputerUseRuntimeLease lease,
  );
}
