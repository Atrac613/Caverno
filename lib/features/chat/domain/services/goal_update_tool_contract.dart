import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/conversation_goal.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'immutable_json_snapshot.dart';
import 'tool_result_prompt_builder.dart';

const String canonicalGoalUpdateToolName = 'update_goal';

/// Exact identity of one immutable `update_goal` invocation.
final class GoalUpdateOperationIdentity {
  GoalUpdateOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _requireCanonicalToolName(toolName),
       argumentDigest = _requiredValue(argumentDigest, 'argumentDigest');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  bool belongsTo(GoalUpdateOperationIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GoalUpdateOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.argumentDigest == argumentDigest;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

/// Recursively immutable input captured before goal acknowledgement evaluation.
final class GoalUpdateToolRequest {
  factory GoalUpdateToolRequest.fromToolCall(
    ChatTurnOwner owner,
    ToolCallInfo toolCall,
  ) => GoalUpdateToolRequest(
    owner: owner,
    toolCallId: toolCall.id,
    toolName: toolCall.name,
    arguments: toolCall.arguments,
  );

  factory GoalUpdateToolRequest({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) {
    final frozenArguments = ImmutableJsonSnapshot.freezeMap(arguments);
    return GoalUpdateToolRequest._(
      identity: GoalUpdateOperationIdentity(
        owner: owner,
        toolCallId: toolCallId,
        toolName: toolName,
        argumentDigest: sha256
            .convert(utf8.encode(jsonEncode(frozenArguments)))
            .toString(),
      ),
      arguments: frozenArguments,
    );
  }

  const GoalUpdateToolRequest._({
    required this.identity,
    required this.arguments,
  });

  final GoalUpdateOperationIdentity identity;
  final Map<String, dynamic> arguments;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;

  ToolCallInfo toToolCallInfo() =>
      ToolCallInfo(id: toolCallId, name: toolName, arguments: arguments);
}

/// Exact-owner goal and completion evidence captured at the call boundary.
final class GoalUpdateOwnerSnapshot {
  GoalUpdateOwnerSnapshot({
    required this.identity,
    required this.goal,
    required List<ToolResultInfo> toolResults,
    required ToolResultCompletionEvidence completionEvidence,
  }) : toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults.map(_freezeToolResult),
       ),
       completionEvidence = freezeGoalUpdateCompletionEvidence(
         completionEvidence,
       );

  final GoalUpdateOperationIdentity identity;
  final ConversationGoal? goal;
  final List<ToolResultInfo> toolResults;
  final ToolResultCompletionEvidence completionEvidence;
}

/// Owner-bound acknowledgement safe to hand to claim persistence.
final class GoalUpdateCompletionAcknowledgement {
  const GoalUpdateCompletionAcknowledgement({
    required this.identity,
    required this.outcome,
  });

  final GoalUpdateOperationIdentity identity;
  final GoalUpdateAckOutcome outcome;

  bool get isCompletionClaim =>
      outcome == GoalUpdateAckOutcome.completionRecorded ||
      outcome == GoalUpdateAckOutcome.completionRejected;

  bool get completionAccepted =>
      outcome == GoalUpdateAckOutcome.completionRecorded;

  bool belongsTo(GoalUpdateOperationIdentity expected) =>
      identity.belongsTo(expected);
}

final class GoalUpdateToolHandlerOutcome {
  const GoalUpdateToolHandlerOutcome({
    required this.identity,
    required this.toolResult,
    required this.completionEvidence,
    required this.acknowledgement,
    required this.shadowOutcome,
  });

  final GoalUpdateOperationIdentity identity;
  final McpToolResult toolResult;
  final ToolResultCompletionEvidence completionEvidence;
  final GoalUpdateCompletionAcknowledgement acknowledgement;
  final GoalUpdateAckOutcome? shadowOutcome;

  ChatTurnOwner get owner => identity.owner;
  GoalUpdateAckOutcome get ackOutcome => acknowledgement.outcome;
  bool get isCompletionClaim => acknowledgement.isCompletionClaim;
  bool get completionAccepted => acknowledgement.completionAccepted;
}

ToolResultCompletionEvidence freezeGoalUpdateCompletionEvidence(
  ToolResultCompletionEvidence evidence,
) => ToolResultCompletionEvidence(
  boundedToolLoopExhausted: evidence.boundedToolLoopExhausted,
  unexecutedToolNames: List<String>.unmodifiable(evidence.unexecutedToolNames),
  unresolvedErrorCount: evidence.unresolvedErrorCount,
  unresolvedErrorPaths: List<String>.unmodifiable(
    evidence.unresolvedErrorPaths,
  ),
  unresolvedErrorDiagnostics: List<UnresolvedErrorDiagnostic>.unmodifiable(
    evidence.unresolvedErrorDiagnostics.map(
      (diagnostic) => UnresolvedErrorDiagnostic(
        path: diagnostic.path,
        code: diagnostic.code,
        message: diagnostic.message,
      ),
    ),
  ),
  unverifiedChangePaths: List<String>.unmodifiable(
    evidence.unverifiedChangePaths,
  ),
  mutatedWithoutExecutionVerification:
      evidence.mutatedWithoutExecutionVerification,
  hasExecutionVerification: evidence.hasExecutionVerification,
  hasSuccessfulExecutionVerification:
      evidence.hasSuccessfulExecutionVerification,
  hasFailedExecutionVerification: evidence.hasFailedExecutionVerification,
  hasAuthoritativeDiagnosticSnapshot:
      evidence.hasAuthoritativeDiagnosticSnapshot,
  hasUnexecutedActionClaim: evidence.hasUnexecutedActionClaim,
  diagnosticSignature: evidence.diagnosticSignature,
);

ToolResultInfo _freezeToolResult(ToolResultInfo source) => ToolResultInfo(
  id: source.id,
  name: source.name,
  arguments: ImmutableJsonSnapshot.freezeMap(
    source.arguments,
    argumentName: 'toolResult.arguments',
  ),
  result: source.result,
);

String _requiredValue(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return value;
}

String _requireCanonicalToolName(String toolName) {
  if (toolName != canonicalGoalUpdateToolName) {
    throw ArgumentError.value(
      toolName,
      'toolName',
      'toolName must be exactly $canonicalGoalUpdateToolName.',
    );
  }
  return toolName;
}
