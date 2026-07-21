import 'goal_update_ack.dart';

/// A disagreement between the two goal-completion mechanisms in one turn.
///
/// LL35 runs the new explicit tool ([GoalUpdateAckResolver]) alongside the
/// incumbent lexical inference (`ConversationGoalProgressInference`) in shadow
/// mode. The lexical path stays authoritative; this classifies where the two
/// decided differently so the disagreement can be recorded and counted before
/// the lexical path is removed. Deleting the lexical path is then a measurement
/// (does the tool cover it?), not a guess.
enum GoalCompletionShadowDisagreement {
  /// The tool accepted completion but the lexical path did not complete —
  /// the model reported completion correctly through the tool while writing
  /// no completion prose. This is the case the tool exists to catch; a high
  /// count here means the lexical path is missing real completions.
  toolAcceptedLexicalMissed,

  /// The lexical path completed but the model made no accepted tool
  /// completion this turn — completion inferred from prose alone. A high
  /// count here means removing the lexical path would strand these turns
  /// unless the model is nudged to call the tool.
  lexicalCompletedToolSilent,

  /// The tool rejected completion (a mechanical gap the lexical gate does not
  /// check) yet the lexical path completed anyway — the lexical path is the
  /// less strict of the two. These are the completions the tool would have
  /// prevented.
  toolRejectedLexicalCompleted,
}

/// Compares the two goal-completion decisions for a single turn.
abstract final class GoalCompletionShadow {
  /// The stable transform label recorded for a disagreement, for triage.
  static String labelFor(GoalCompletionShadowDisagreement disagreement) {
    switch (disagreement) {
      case GoalCompletionShadowDisagreement.toolAcceptedLexicalMissed:
        return 'goal_completion_tool_accepted_lexical_missed';
      case GoalCompletionShadowDisagreement.lexicalCompletedToolSilent:
        return 'goal_completion_lexical_only';
      case GoalCompletionShadowDisagreement.toolRejectedLexicalCompleted:
        return 'goal_completion_tool_rejected_lexical_completed';
    }
  }

  /// Returns the disagreement to record, or null when the two paths agree.
  ///
  /// [toolCompletionOutcome] is the outcome of an `update_goal(completed: true)`
  /// call made this turn, or null when no completion was claimed through the
  /// tool. Only the two completion outcomes are meaningful here; any other
  /// outcome (progress, blocker, inactive) is treated as no completion claim.
  static GoalCompletionShadowDisagreement? compare({
    required GoalUpdateAckOutcome? toolCompletionOutcome,
    required bool lexicalCompleted,
  }) {
    final toolAccepted =
        toolCompletionOutcome == GoalUpdateAckOutcome.completionRecorded;
    final toolRejected =
        toolCompletionOutcome == GoalUpdateAckOutcome.completionRejected;

    if (toolAccepted && !lexicalCompleted) {
      return GoalCompletionShadowDisagreement.toolAcceptedLexicalMissed;
    }
    if (toolRejected && lexicalCompleted) {
      return GoalCompletionShadowDisagreement.toolRejectedLexicalCompleted;
    }
    if (!toolAccepted && !toolRejected && lexicalCompleted) {
      return GoalCompletionShadowDisagreement.lexicalCompletedToolSilent;
    }
    // Remaining cases agree: both complete, both reject, or neither acts.
    return null;
  }
}
