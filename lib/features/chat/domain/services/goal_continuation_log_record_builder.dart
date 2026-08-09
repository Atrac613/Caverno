import '../entities/chat_turn_owner.dart';
import '../entities/conversation_goal.dart';
import 'conversation_goal_auto_continue_policy.dart';
import 'goal_auto_continue_evidence_marker.dart';
import 'goal_auto_continue_tracker_registry.dart';
import 'goal_completion_shadow.dart';
import 'goal_update_ack.dart';
import 'immutable_json_snapshot.dart';
import 'tool_result_prompt_builder.dart';
import 'verification_cadence_policy.dart';

// ChatNotifier decomposition collaborator: goal-continuation-log-record-builder
final class GoalAutoContinueLogRecord {
  const GoalAutoContinueLogRecord._({
    required this.owner,
    required this.decision,
    required this.reason,
    required this.goalId,
    required this.nextTurnNumber,
    required this.effectiveTurnBudget,
    required this.consecutiveAutoContinuations,
    required this.evidence,
  });
  final ChatTurnOwner owner;
  final String decision;
  final String reason;
  final String? goalId;
  final int? nextTurnNumber;
  final int? effectiveTurnBudget;
  final int? consecutiveAutoContinuations;
  final Map<String, dynamic> evidence;
  Map<String, dynamic> get payload => Map<String, dynamic>.unmodifiable({
    'decision': decision,
    'reason': reason,
    if (goalId != null) 'goalId': goalId,
    if (nextTurnNumber != null) 'nextTurnNumber': nextTurnNumber,
    if (effectiveTurnBudget != null) 'effectiveTurnBudget': effectiveTurnBudget,
    if (consecutiveAutoContinuations != null)
      'consecutiveAutoContinuations': consecutiveAutoContinuations,
    if (evidence.isNotEmpty) 'evidence': evidence,
  });
}

final class GoalCompletionShadowLogRecord {
  const GoalCompletionShadowLogRecord._({
    required this.owner,
    required this.agreement,
    required this.label,
    required this.toolOutcome,
    required this.lexicalCompleted,
    required this.turnId,
  });
  final ChatTurnOwner owner;
  final GoalCompletionShadowAgreement agreement;
  final String? label;
  final String? toolOutcome;
  final bool lexicalCompleted;
  final String turnId;
  Map<String, dynamic> get payload => Map<String, dynamic>.unmodifiable({
    'agreement': agreement.name,
    if (label != null) 'label': label,
    if (toolOutcome != null) 'toolOutcome': toolOutcome,
    'lexicalCompleted': lexicalCompleted,
    'turnId': turnId,
  });
}

final class GoalContinuationLogRecordBuilder {
  const GoalContinuationLogRecordBuilder();

  GoalAutoContinueLogRecord buildAutoContinue({
    required ChatTurnOwner owner,
    required String decision,
    required String reason,
    required ConversationGoal? goal,
    required int? nextTurnNumber,
    required int? effectiveTurnBudget,
    required GoalAutoContinueTrackerSnapshot? tracker,
    required ToolResultCompletionEvidence evidence,
    required VerificationCadence verificationCadence,
    required int? mutationGeneration,
    required int? verificationGeneration,
    required GoalAutoContinueSafeBoundary safeBoundary,
  }) {
    final normalizedGoalId = goal?.id.trim();
    final evidenceMarker = GoalAutoContinueEvidenceMarker.build(
      evidence: evidence,
      verificationCadence: verificationCadence,
      mutationGeneration: mutationGeneration,
      verificationGeneration: verificationGeneration,
      safeBoundaryVeto: safeBoundary.firstVetoReason,
      noProgressStreak: tracker?.noProgressStreak ?? 0,
      hasVerifierReplayCandidate: tracker?.verifierReplayCandidate != null,
      diagnosticRepairContinuations:
          tracker?.diagnosticRepairContinuations ?? 0,
      consecutiveValidationMisses: tracker?.consecutiveValidationMisses ?? 0,
      diagnosticRepairExtensionUsed:
          tracker?.diagnosticRepairExtensionUsed ?? false,
      previousUnresolvedErrorCount:
          tracker?.previousEvidence?.unresolvedErrorCount,
      identicalDiagnosticSignatureStreak:
          tracker?.identicalDiagnosticSignatureStreak ?? 0,
    );
    return GoalAutoContinueLogRecord._(
      owner: owner,
      decision: decision,
      reason: reason,
      goalId: normalizedGoalId == null || normalizedGoalId.isEmpty
          ? null
          : normalizedGoalId,
      nextTurnNumber: nextTurnNumber,
      effectiveTurnBudget: effectiveTurnBudget,
      consecutiveAutoContinuations: tracker?.consecutiveAutoContinuations,
      evidence: ImmutableJsonSnapshot.freezeMap(evidenceMarker),
    );
  }

  GoalCompletionShadowLogRecord buildCompletionShadow({
    required ChatTurnOwner owner,
    required bool lexicalCompleted,
    required GoalUpdateAckOutcome? toolCompletionOutcome,
  }) {
    final disagreement = GoalCompletionShadow.compare(
      toolCompletionOutcome: toolCompletionOutcome,
      lexicalCompleted: lexicalCompleted,
    );
    return GoalCompletionShadowLogRecord._(
      owner: owner,
      agreement: GoalCompletionShadow.agreementFor(disagreement),
      label: GoalCompletionShadow.optionalLabelFor(disagreement),
      toolOutcome: toolCompletionOutcome?.name,
      lexicalCompleted: lexicalCompleted,
      turnId: 'gen-${owner.interactionGeneration}',
    );
  }
}
