import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/conversation_participant.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'participant_tool_policy.dart';
import 'tool_approval_auto_review_service.dart';
import 'turn_tool_approval_coordinator.dart';

// ChatNotifier decomposition collaborator: participant-tool-executor

/// Exact conversation turn and participant that own a tool operation.
final class ParticipantToolScope {
  ParticipantToolScope({required this.owner, required String participantId})
    : participantId = participantId {
    if (participantId.trim().isEmpty) {
      throw ArgumentError.value(
        participantId,
        'participantId',
        'Participant ID must not be empty.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String participantId;

  bool matches(ParticipantToolScope other) {
    return owner == other.owner && participantId == other.participantId;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ParticipantToolScope && matches(other);
  }

  @override
  int get hashCode => Object.hash(owner, participantId);
}

/// Immutable participant context captured before any asynchronous operation.
final class ParticipantToolSession {
  ParticipantToolSession({
    required this.owner,
    required this.participant,
    required this.supportsToolAwareRequests,
    required List<Map<String, dynamic>> availableDefinitions,
    List<Message> conversationMessages = const [],
    this.hasUntrustedInfluence = false,
  }) : availableDefinitions = List<Map<String, dynamic>>.unmodifiable(
         availableDefinitions.map(_freezeMap),
       ),
       conversationMessages = List<Message>.unmodifiable(conversationMessages),
       scope = ParticipantToolScope(
         owner: owner,
         participantId: participant.id,
       );

  final ChatTurnOwner owner;
  final ConversationParticipant participant;
  final bool supportsToolAwareRequests;
  final List<Map<String, dynamic>> availableDefinitions;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;
  final ParticipantToolScope scope;
}

/// Typed approval input preserving distinct review and manual arguments.
final class ParticipantToolApprovalRequest {
  ParticipantToolApprovalRequest({
    required this.scope,
    required this.coordinatorRequest,
    required Map<String, dynamic> manualArguments,
  }) : manualArguments = _freezeMap(manualArguments);

  final ParticipantToolScope scope;
  final ToolApprovalRequest coordinatorRequest;
  final Map<String, dynamic> manualArguments;
}

/// Owner-tagged approval result returned after the port revalidates scope.
final class ParticipantToolApprovalResult {
  const ParticipantToolApprovalResult({
    required this.scope,
    required this.outcome,
  });

  final ParticipantToolScope scope;
  final ToolApprovalOutcome outcome;
}

/// Immutable execution input for one participant tool call.
final class ParticipantToolExecutionRequest {
  ParticipantToolExecutionRequest({
    required this.scope,
    required this.toolCallId,
    required this.toolName,
    required Map<String, dynamic> arguments,
  }) : arguments = _freezeMap(arguments);

  final ParticipantToolScope scope;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
}

/// Owner-tagged execution completion returned by the tool adapter.
final class ParticipantToolExecutionResult {
  const ParticipantToolExecutionResult({
    required this.scope,
    required this.result,
  });

  final ParticipantToolScope scope;
  final McpToolResult result;
}

/// Immutable activity projection for one exact participant turn.
final class ParticipantToolActivityUpdate {
  const ParticipantToolActivityUpdate({
    required this.scope,
    required this.activeToolName,
  });

  final ParticipantToolScope scope;
  final String activeToolName;
}

/// Immutable taint event built only after execution returns a result.
final class ParticipantToolTaintEvent {
  const ParticipantToolTaintEvent({required this.scope, required this.result});

  final ParticipantToolScope scope;
  final McpToolResult result;
}

/// Scope acknowledgement from a synchronous side-effect adapter.
final class ParticipantToolScopeAcknowledgement {
  const ParticipantToolScopeAcknowledgement({required this.scope});

  final ParticipantToolScope scope;
}

/// Resolves approval for the exact conversation generation and participant.
///
/// Implementations must use [ParticipantToolApprovalRequest.coordinatorRequest]
/// with `TurnToolApprovalCoordinator`, validate the participant before showing
/// manual UI, and return the same scope after every asynchronous boundary.
abstract interface class ParticipantToolApprovalPort {
  Future<ParticipantToolApprovalResult> resolve(
    ParticipantToolApprovalRequest request,
  );
}

/// Executes a tool only for the exact conversation generation and participant.
abstract interface class ParticipantToolExecutionPort {
  Future<ParticipantToolExecutionResult> execute(
    ParticipantToolExecutionRequest request,
  );
}

/// Projects activity only into the exact participant runtime.
abstract interface class ParticipantToolActivityPort {
  ParticipantToolScopeAcknowledgement update(
    ParticipantToolActivityUpdate update,
  );
}

/// Records provenance only in the exact owner's conversation taint state.
abstract interface class ParticipantToolTaintPort {
  ParticipantToolScopeAcknowledgement record(ParticipantToolTaintEvent event);
}

/// Filters, approves, executes, and records one participant tool call.
final class ParticipantToolExecutor {
  const ParticipantToolExecutor({
    required ParticipantToolApprovalPort approvalPort,
    required ParticipantToolActivityPort activityPort,
    required ParticipantToolTaintPort taintPort,
    ParticipantToolExecutionPort? executionPort,
    ParticipantToolPolicy policy = const ParticipantToolPolicy(),
  }) : _approvalPort = approvalPort,
       _executionPort = executionPort,
       _activityPort = activityPort,
       _taintPort = taintPort,
       _policy = policy;

  static const String actionKind = 'participant_read_only_tool';

  final ParticipantToolApprovalPort _approvalPort;
  final ParticipantToolExecutionPort? _executionPort;
  final ParticipantToolActivityPort _activityPort;
  final ParticipantToolTaintPort _taintPort;
  final ParticipantToolPolicy _policy;

  /// Returns the immutable participant-safe definitions advertised to the LLM.
  List<Map<String, dynamic>> definitionsFor(ParticipantToolSession session) {
    if (!session.participant.toolsEnabled ||
        !session.supportsToolAwareRequests ||
        _executionPort == null) {
      return const <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.unmodifiable(
      _policy.filterDefinitions(session.availableDefinitions),
    );
  }

  Future<McpToolResult> execute(
    ParticipantToolSession session,
    ToolCallInfo toolCall,
  ) async {
    final denied = _policy.enforce(toolCall);
    if (denied != null) return denied;

    final executionPort = _executionPort;
    if (executionPort == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Participant tool service is unavailable.',
      );
    }

    final arguments = _freezeMap(toolCall.arguments);
    final approvalRequest = _approvalRequest(session, toolCall, arguments);
    final approval = await _approvalPort.resolve(approvalRequest);
    _requireScope(approval.scope, session.scope, 'Participant tool approval');
    if (approval.outcome.denialResult case final denial?) return denial;

    try {
      _requireScope(
        _activityPort
            .update(
              ParticipantToolActivityUpdate(
                scope: session.scope,
                activeToolName: toolCall.name,
              ),
            )
            .scope,
        session.scope,
        'Participant tool activity start',
      );
      final execution = await executionPort.execute(
        ParticipantToolExecutionRequest(
          scope: session.scope,
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          arguments: arguments,
        ),
      );
      _requireScope(
        execution.scope,
        session.scope,
        'Participant tool execution',
      );
      _requireScope(
        _taintPort
            .record(
              ParticipantToolTaintEvent(
                scope: session.scope,
                result: execution.result,
              ),
            )
            .scope,
        session.scope,
        'Participant tool taint',
      );
      return execution.result;
    } finally {
      _requireScope(
        _activityPort
            .update(
              ParticipantToolActivityUpdate(
                scope: session.scope,
                activeToolName: '',
              ),
            )
            .scope,
        session.scope,
        'Participant tool activity clear',
      );
    }
  }

  ParticipantToolApprovalRequest _approvalRequest(
    ParticipantToolSession session,
    ToolCallInfo toolCall,
    Map<String, dynamic> toolArguments,
  ) {
    final participant = session.participant;
    final reviewArguments = <String, dynamic>{
      'participantId': participant.id,
      'participantName': participant.effectiveDisplayName,
      'participantRoleLabel': participant.effectiveRoleLabel,
      'toolArguments': toolArguments,
    };
    return ParticipantToolApprovalRequest(
      scope: session.scope,
      coordinatorRequest: ToolApprovalRequest(
        owner: session.owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        arguments: reviewArguments,
        actionKind: actionKind,
        mode: participant.toolApprovalMode,
        reviewDomain: ToolApprovalAutoReviewDomain.participant,
        fullAccessEligible: true,
        reason: toolArguments['reason'] as String?,
        conversationMessages: session.conversationMessages,
        hasUntrustedInfluence: session.hasUntrustedInfluence,
      ),
      manualArguments: toolArguments,
    );
  }

  static McpToolResult manualApprovalDeniedResult(String toolName) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': 'approval_denied',
        'error': 'User denied the participant tool action.',
        'nextAction':
            'Ask the user for explicit approval before retrying this participant tool.',
      }),
      isSuccess: false,
      errorMessage: 'User denied participant tool action.',
    );
  }

  void _requireScope(
    ParticipantToolScope actual,
    ParticipantToolScope expected,
    String source,
  ) {
    if (!actual.matches(expected)) {
      throw StateError('$source scope mismatch.');
    }
  }
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}
