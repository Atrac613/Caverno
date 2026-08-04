import '../entities/conversation_goal.dart';

/// Projects one existing goal into an explicitly requested status.
final class ConversationGoalStatusTransition {
  const ConversationGoalStatusTransition();

  ConversationGoal? apply({
    required ConversationGoal? goal,
    required ConversationGoalStatus status,
    String? blockedReason,
    String? completionSummary,
    DateTime? now,
  }) {
    if (goal == null || !goal.hasObjective) {
      return null;
    }
    final updatedAt = now ?? DateTime.now();
    return goal.copyWith(
      enabled: true,
      status: status,
      completionSummary: status == ConversationGoalStatus.completed
          ? completionSummary?.trim() ??
                goal.normalizedCompletionSummary ??
                'Marked complete by the user.'
          : '',
      blockedReason: status == ConversationGoalStatus.blocked
          ? blockedReason?.trim() ??
                goal.normalizedBlockedReason ??
                'Marked blocked by the user.'
          : '',
      blockerSignature: status == ConversationGoalStatus.blocked
          ? goal.blockerSignature
          : '',
      blockerRepeatCount: status == ConversationGoalStatus.blocked
          ? goal.blockerRepeatCount
          : 0,
      completedAt: status == ConversationGoalStatus.completed
          ? updatedAt
          : null,
      blockedAt: status == ConversationGoalStatus.blocked ? updatedAt : null,
      lastBlockerSeenAt: status == ConversationGoalStatus.blocked
          ? goal.lastBlockerSeenAt
          : null,
      updatedAt: updatedAt,
    );
  }
}
