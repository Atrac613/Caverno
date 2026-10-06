// Same-library access to the owner-scoped acknowledgement and turn messages.
// ignore_for_file: invalid_use_of_protected_member

part of 'chat_notifier.dart';

extension ChatNotifierGoalBlockerBoundary on ChatNotifier {
  GoalUpdateCompletionAcknowledgement? _recordedGoalBlocker(
    ChatTurnOwner owner,
  ) {
    final acknowledgement = _turnEnd.stateFor(owner)?.goalUpdateAcknowledgement;
    return acknowledgement?.outcome == GoalUpdateAckOutcome.blockerLogged
        ? acknowledgement
        : null;
  }

  McpToolResult? _refuseToolAfterGoalBlocker(
    ToolCallInfo toolCall, {
    required int? interactionGeneration,
  }) {
    final owner = interactionGeneration == null
        ? null
        : _turnOwnerForGeneration(interactionGeneration);
    if (owner == null || _recordedGoalBlocker(owner) == null) return null;
    const error =
        'The goal was marked blocked during this turn. End the turn and '
        'report the recorded blocker; further tool calls were not executed.';
    return McpToolResult(
      toolName: toolCall.name,
      isSuccess: false,
      errorMessage: error,
      result: jsonEncode({
        'ok': false,
        'code': 'goal_blocked_turn',
        'executed': false,
        'error': error,
      }),
    );
  }

  String? _recordedGoalBlockerResponse(ChatTurnOwner owner) {
    final acknowledgement = _recordedGoalBlocker(owner);
    if (acknowledgement == null) return null;
    final reason = acknowledgement.input.normalizedBlockedReason;
    if (_conversationForId(owner.conversationId)?.goal?.projectTaskAutoReview ==
        true) {
      return ProjectTaskTerminalStatus(
        outcome: GoalUpdateAckOutcome.blockerLogged,
        gaps: [?reason],
      ).incompleteResponse;
    }
    return 'The goal is blocked${reason == null ? '.' : ': $reason'}\n\n'
        'Resolve the blocker or ask the user before reactivating the goal.';
  }
}
