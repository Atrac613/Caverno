import 'dart:convert';

import '../../../../core/types/goal_completion_policy.dart';
import '../entities/conversation_goal.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'project_task_completion_evidence.dart';
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
  /// The model emitted arguments that do not satisfy the advertised schema.
  invalidArguments,

  /// A `message`-only update was logged as progress.
  progressLogged,

  /// `completed: true` was accepted — no mechanical evidence contradicts it.
  completionRecorded,

  /// `completed: true` was rejected because mechanical evidence
  /// (unresolved errors, a failed verification, an exhausted tool loop)
  /// contradicts the claim. The goal stays active and the gaps are returned.
  completionRejected,

  /// The completion claim is mechanically admissible, but this model's policy
  /// requires an explicit user decision before the goal closes.
  confirmationRequired,

  /// A `blocked_reason` was logged against an active goal.
  blockerLogged,

  /// Progress was reported after the configured goal budget was exhausted.
  pausedAtCap,

  /// The call arrived with no active goal to update.
  rejectedInactive,
}

/// A parsed `update_goal` call.
class GoalUpdateInput {
  const GoalUpdateInput({
    this.completed = false,
    this.message,
    this.blockedReason,
    this.validationError,
  });

  /// Reads an `update_goal` tool call's raw JSON arguments.
  factory GoalUpdateInput.fromArguments(Map<String, dynamic> arguments) {
    final completed = arguments['completed'];
    final message = arguments['message'];
    final blockedReason = arguments['blocked_reason'];
    return GoalUpdateInput(
      completed: completed is bool && completed,
      message: message is String ? message : null,
      blockedReason: blockedReason is String ? blockedReason : null,
      validationError: validateArguments(arguments),
    );
  }

  /// Returns the exact schema violation without coercing any raw value.
  static String? validateArguments(Map<String, dynamic> arguments) {
    if (!arguments.containsKey('completed')) {
      return 'Invalid update_goal arguments: completed is required and must '
          'be a JSON boolean.';
    }
    final completed = arguments['completed'];
    if (completed is! bool) {
      return 'Invalid update_goal arguments: completed must be a JSON '
          'boolean; received ${completed.runtimeType} ${jsonEncode(completed)}.';
    }
    const allowedKeys = {'completed', 'message', 'blocked_reason'};
    final unexpected =
        arguments.keys
            .where((key) => !allowedKeys.contains(key))
            .toList(growable: false)
          ..sort();
    if (unexpected.isNotEmpty) {
      return 'Invalid update_goal arguments: unexpected field(s): '
          '${unexpected.join(', ')}.';
    }
    final message = arguments['message'];
    if (arguments.containsKey('message') && message is! String) {
      return 'Invalid update_goal arguments: message must be a JSON string; '
          'received ${message.runtimeType} ${jsonEncode(message)}.';
    }
    final blockedReason = arguments['blocked_reason'];
    if (arguments.containsKey('blocked_reason') && blockedReason is! String) {
      return 'Invalid update_goal arguments: blocked_reason must be a JSON '
          'string; received ${blockedReason.runtimeType} '
          '${jsonEncode(blockedReason)}.';
    }
    return null;
  }

  final bool completed;
  final String? message;
  final String? blockedReason;
  final String? validationError;

  bool get isValid => validationError == null;

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
    this.blockedReason,
  });

  final GoalUpdateAckOutcome outcome;
  final String modelMessage;
  final List<String> gaps;
  final String? blockedReason;

  bool get completionAccepted =>
      outcome == GoalUpdateAckOutcome.completionRecorded;

  bool get completionRejected =>
      outcome == GoalUpdateAckOutcome.completionRejected;

  bool get confirmationRequired =>
      outcome == GoalUpdateAckOutcome.confirmationRequired;

  /// Whether this ack claimed completion at all (accepted or rejected), as
  /// opposed to a progress note, a blocker, or an inactive goal.
  bool get isCompletionClaim =>
      completionAccepted || completionRejected || confirmationRequired;

  /// The tool result the dispatch layer returns for this ack.
  ///
  /// A rejected completion is a well-formed call the harness answered, not a
  /// tool failure, so it is a successful result whose body is the verdict —
  /// the model reads the gaps as data. An inactive goal or schema-invalid
  /// arguments are tool failures.
  McpToolResult toToolResult(String toolName) {
    final failed =
        outcome == GoalUpdateAckOutcome.rejectedInactive ||
        outcome == GoalUpdateAckOutcome.invalidArguments;
    return McpToolResult(
      toolName: toolName,
      result: failed ? '' : modelMessage,
      isSuccess: !failed,
      errorMessage: failed ? modelMessage : null,
    );
  }
}

/// Resolves an `update_goal` call to the ack the model reads.
///
/// Pure and mechanical: the verdict comes from the goal's own lifecycle state
/// and the LL34 completion evidence, never from the prose of the response that
/// made the claim. Until LL37 adds an adversarial verifier, "no mechanical
/// evidence against it" is as far as a completion can be checked — so a
/// recorded completion is not independently verified. Project implementation
/// goals additionally require typed change and post-change execution evidence.
class GoalUpdateAckResolver {
  const GoalUpdateAckResolver();

  /// Resolves an `update_goal` tool call to the ack the harness returns.
  ///
  /// A null or inactive goal yields the inactive ack. Callers map it to a tool
  /// result with [GoalUpdateAck.toToolResult], and LL35 shadow-tracking reads
  /// [GoalUpdateAck.outcome] from the same ack.
  GoalUpdateAck resolveCall({
    required ToolCallInfo toolCall,
    required ConversationGoal? goal,
    ToolResultCompletionEvidence evidence =
        const ToolResultCompletionEvidence(),
    GoalCompletionPolicy completionPolicy = GoalCompletionPolicy.toolOrAsk,
    List<ToolResultInfo> taskToolResults = const [],
  }) {
    return resolve(
      input: GoalUpdateInput.fromArguments(toolCall.arguments),
      goal: goal,
      evidence: evidence,
      completionPolicy: completionPolicy,
      taskToolResults: taskToolResults,
    );
  }

  GoalUpdateAck resolve({
    required GoalUpdateInput input,
    required ConversationGoal? goal,
    ToolResultCompletionEvidence evidence =
        const ToolResultCompletionEvidence(),
    GoalCompletionPolicy completionPolicy = GoalCompletionPolicy.toolOrAsk,
    List<ToolResultInfo> taskToolResults = const [],
  }) {
    if (!input.isValid) {
      return GoalUpdateAck(
        outcome: GoalUpdateAckOutcome.invalidArguments,
        modelMessage: input.validationError!,
      );
    }
    if (goal == null || !goal.isActive) {
      return const GoalUpdateAck(
        outcome: GoalUpdateAckOutcome.rejectedInactive,
        modelMessage:
            'There is no active goal to update. Set a goal with /goal before '
            'reporting its progress.',
      );
    }

    switch (input.kind) {
      case GoalUpdateKind.completion:
        return _resolveCompletion(
          evidence,
          completionPolicy,
          supersedesProgress: goal.projectTaskAutoReview,
          taskGaps: goal.projectTaskAutoReview
              ? const ProjectTaskCompletionEvidence().gaps(
                  toolResults: taskToolResults,
                  evidence: evidence,
                )
              : const [],
        );
      case GoalUpdateKind.blocker:
        return GoalUpdateAck(
          outcome: GoalUpdateAckOutcome.blockerLogged,
          blockedReason: input.normalizedBlockedReason,
          modelMessage:
              'Goal marked blocked: ${input.normalizedBlockedReason}. Resolve '
              'the blocker or ask the user before reactivating the goal.',
        );
      case GoalUpdateKind.progress:
        final note = input.normalizedMessage;
        if (goal.budgetExceeded) {
          return GoalUpdateAck(
            outcome: GoalUpdateAckOutcome.pausedAtCap,
            modelMessage: note == null
                ? 'Progress received, but the goal is paused at its configured '
                      'budget cap. User confirmation is required to continue.'
                : 'Progress received at the budget cap: $note. User '
                      'confirmation is required to continue.',
          );
        }
        return GoalUpdateAck(
          outcome: GoalUpdateAckOutcome.progressLogged,
          modelMessage: note == null
              ? 'Progress noted. Keep working toward the goal.'
              : 'Progress logged: $note. Keep working toward the goal.',
        );
    }
  }

  GoalUpdateAck _resolveCompletion(
    ToolResultCompletionEvidence evidence,
    GoalCompletionPolicy completionPolicy, {
    required List<String> taskGaps,
    required bool supersedesProgress,
  }) {
    final gaps = [
      ...completionGaps(evidence, includeRemainingWork: !supersedesProgress),
      ...taskGaps,
    ];
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
    if (!completionPolicy.acceptsToolCompletion) {
      return const GoalUpdateAck(
        outcome: GoalUpdateAckOutcome.confirmationRequired,
        modelMessage:
            'Completion is mechanically admissible, but this model requires '
            'user confirmation. The goal is awaiting a decision.',
      );
    }
    return const GoalUpdateAck(
      outcome: GoalUpdateAckOutcome.completionRecorded,
      modelMessage:
          'Completion accepted: no mechanical evidence contradicts it. It has '
          'not been independently verified, so state plainly what you did and '
          'what remains unchecked.',
    );
  }

  /// Concrete, mechanically-derived reasons a completion cannot be recorded.
  ///
  /// Reads the LL34 completion evidence, not the response text. Order is most
  /// to least actionable. There are a fixed seven evidence sources, so the
  /// list is naturally bounded — no truncation is needed.
  List<String> completionGaps(
    ToolResultCompletionEvidence evidence, {
    bool includeRemainingWork = true,
  }) {
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
    if (includeRemainingWork && evidence.hasReportedRemainingWork) {
      final message = evidence.remainingWorkMessage.trim();
      gaps.add(
        message.isEmpty
            ? 'remaining work was reported without completion'
            : 'remaining work was reported: $message',
      );
    }

    return gaps;
  }

  String buildConfirmationSummary({
    required String assistantResponse,
    required ToolResultCompletionEvidence evidence,
    required bool stoppedAtBudget,
  }) {
    final firstLine = assistantResponse
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final boundedLine = firstLine.length <= 180
        ? firstLine
        : '${firstLine.substring(0, 177).trimRight()}...';
    final gaps = completionGaps(evidence);
    return [
      if (stoppedAtBudget)
        'The configured goal budget was reached before an accepted completion '
            'claim.',
      if (boundedLine.isNotEmpty) 'Latest result: $boundedLine',
      if (gaps.isEmpty)
        'No mechanical gap is currently recorded.'
      else
        'Still unverified: ${gaps.take(3).join('; ')}.',
      'Confirm completion or reactivate the goal to continue.',
    ].join('\n');
  }

  String _joinPaths(List<String> paths) {
    const maxShown = 3;
    if (paths.length <= maxShown) {
      return paths.join(', ');
    }
    return '${paths.take(maxShown).join(', ')} (+${paths.length - maxShown} more)';
  }
}
