import '../entities/conversation_goal.dart';
import 'tool_result_prompt_builder.dart';

/// What the model asked the harness to do with the goal.
enum GoalUpdateKind { progress, completion, blocker }

/// The harness's actual response to an `update_goal` call.
///
/// A tool that always returned success would teach the model that any
/// completion claim it makes is received as fact — the exact failure LL35
/// exists to remove. The outcome the model reads has to reflect what the
/// harness really did, so a rejected completion reads as a rejection and the
/// model keeps working. See LL35 in `docs/local_llm_agent_roadmap.md`.
enum GoalUpdateAckOutcome {
  /// A `message`-only update was logged as progress.
  progressLogged,

  /// `completed: true` was accepted — no mechanical evidence contradicts it.
  completionRecorded,

  /// `completed: true` was rejected because mechanical evidence
  /// (unresolved errors, a failed verification, an exhausted tool loop)
  /// contradicts the claim. The goal stays active and the gaps are returned.
  completionRejected,

  /// A `blocked_reason` was logged against an active goal.
  blockerLogged,

  /// The call arrived with no active goal to update.
  rejectedInactive,
}

/// A parsed `update_goal` call.
class GoalUpdateInput {
  const GoalUpdateInput({
    this.completed = false,
    this.message,
    this.blockedReason,
  });

  final bool completed;
  final String? message;
  final String? blockedReason;

  String? get normalizedMessage {
    final trimmed = message?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  String? get normalizedBlockedReason {
    final trimmed = blockedReason?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// A completion claim outranks a blocker note, which outranks a bare message,
  /// so an ambiguous call resolves to the strongest intent it expressed.
  GoalUpdateKind get kind {
    if (completed) return GoalUpdateKind.completion;
    if (normalizedBlockedReason != null) return GoalUpdateKind.blocker;
    return GoalUpdateKind.progress;
  }
}

/// The resolved response to an `update_goal` call: an outcome, the message the
/// model reads, and — when a completion was rejected — the concrete gaps that
/// rejected it.
class GoalUpdateAck {
  const GoalUpdateAck({
    required this.outcome,
    required this.modelMessage,
    this.gaps = const <String>[],
  });

  final GoalUpdateAckOutcome outcome;
  final String modelMessage;
  final List<String> gaps;

  bool get completionAccepted =>
      outcome == GoalUpdateAckOutcome.completionRecorded;

  bool get completionRejected =>
      outcome == GoalUpdateAckOutcome.completionRejected;
}

/// Resolves an `update_goal` call to the ack the model reads.
///
/// Pure and mechanical: the verdict comes from the goal's own lifecycle state
/// and the LL34 completion evidence, never from the prose of the response that
/// made the claim. Until LL37 adds an adversarial verifier, "no mechanical
/// evidence against it" is as far as a completion can be checked — so a
/// recorded completion here is *not verified*, only *not contradicted*, and
/// the message says so.
class GoalUpdateAckResolver {
  const GoalUpdateAckResolver();

  GoalUpdateAck resolve({
    required GoalUpdateInput input,
    required ConversationGoal goal,
    ToolResultCompletionEvidence evidence =
        const ToolResultCompletionEvidence(),
  }) {
    if (!goal.isActive) {
      return const GoalUpdateAck(
        outcome: GoalUpdateAckOutcome.rejectedInactive,
        modelMessage:
            'There is no active goal to update. Set a goal with /goal before '
            'reporting its progress.',
      );
    }

    switch (input.kind) {
      case GoalUpdateKind.completion:
        return _resolveCompletion(evidence);
      case GoalUpdateKind.blocker:
        return GoalUpdateAck(
          outcome: GoalUpdateAckOutcome.blockerLogged,
          modelMessage:
              'Logged as blocked: ${input.normalizedBlockedReason}. The goal '
              'stays active; resolve the blocker or ask the user, then report '
              'progress again.',
        );
      case GoalUpdateKind.progress:
        final note = input.normalizedMessage;
        return GoalUpdateAck(
          outcome: GoalUpdateAckOutcome.progressLogged,
          modelMessage: note == null
              ? 'Progress noted. Keep working toward the goal.'
              : 'Progress logged: $note. Keep working toward the goal.',
        );
    }
  }

  GoalUpdateAck _resolveCompletion(ToolResultCompletionEvidence evidence) {
    final gaps = _completionGaps(evidence);
    if (gaps.isNotEmpty) {
      return GoalUpdateAck(
        outcome: GoalUpdateAckOutcome.completionRejected,
        gaps: gaps,
        modelMessage:
            'Completion not recorded — the following remain outstanding:\n'
            '${gaps.map((gap) => '- $gap').join('\n')}\n'
            'The goal is still active. Resolve these and report completion '
            'again.',
      );
    }
    return const GoalUpdateAck(
      outcome: GoalUpdateAckOutcome.completionRecorded,
      modelMessage:
          'Completion recorded. Note: no mechanical evidence contradicts it, '
          'but it has not been independently verified.',
    );
  }

  /// Concrete, mechanically-derived reasons a completion cannot be recorded.
  ///
  /// Reads the LL34 completion evidence, not the response text. Order is most
  /// to least actionable. There are a fixed six evidence sources, so the list
  /// is naturally bounded — no truncation is needed.
  List<String> _completionGaps(ToolResultCompletionEvidence evidence) {
    final gaps = <String>[];

    if (evidence.unresolvedErrorCount > 0) {
      final paths = evidence.unresolvedErrorPaths;
      gaps.add(
        paths.isEmpty
            ? '${evidence.unresolvedErrorCount} unresolved error(s) from the '
                  'last tool run'
            : '${evidence.unresolvedErrorCount} unresolved error(s) in '
                  '${_joinPaths(paths)}',
      );
    }
    if (evidence.hasFailedExecutionVerification) {
      gaps.add('the last verification command failed');
    }
    if (evidence.boundedToolLoopExhausted) {
      gaps.add('the tool loop stopped before the work converged');
    }
    if (evidence.unverifiedChangePaths.isNotEmpty) {
      gaps.add(
        'unverified change(s) in ${_joinPaths(evidence.unverifiedChangePaths)}',
      );
    }
    if (evidence.mutatedWithoutExecutionVerification) {
      gaps.add('files were changed but no verification command was run');
    }
    if (evidence.hasUnexecutedActionClaim) {
      gaps.add('an action was claimed in prose but never executed');
    }

    return gaps;
  }

  String _joinPaths(List<String> paths) {
    const maxShown = 3;
    if (paths.length <= maxShown) {
      return paths.join(', ');
    }
    return '${paths.take(maxShown).join(', ')} (+${paths.length - maxShown} more)';
  }
}
