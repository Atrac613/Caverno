/// LL31 — structured turn-exit reasons and the completion explainer.
///
/// The tool-calling loop in `ChatNotifier` has many exit points (a normal text
/// response, the iteration cap, a twice-failing tool call, guardrail/confirmation
/// blocks, a cancelled stream, a length-truncated answer). Today those exits are
/// untyped, so when a complex turn ends with an empty or fragmentary response the
/// user sees a blank bubble with no explanation, and the session log carries no
/// structured record of *why* the turn stopped.
///
/// This service is the LL31 "instrument": a pure, testable classifier that maps
/// the terminal turn state to a [ToolLoopExitReason], plus a completion explainer
/// that turns an empty/partial result into a single user-visible sentence. It is
/// deliberately dependency-free so it can be unit-tested in isolation and wired
/// into the finalization tail (`_finishStreaming`) without growing the god-file
/// with logic. See `docs/local_llm_agent_roadmap.md` (LL31).
library;

/// Why a single tool-calling turn ended.
///
/// Ordering is by specificity, not severity: the classifier prefers an explicit
/// loop-supplied hint, then derives from terminal state. Healthy completions map
/// to [textResponse]; everything else is an abnormal or capped exit the explainer
/// may surface to the user.
enum ToolLoopExitReason {
  /// The model produced a normal final answer. Healthy — never explained.
  textResponse,

  /// The loop hit the iteration cap (`iteration >= maxIterations`) before the
  /// model produced a final answer.
  maxIterations,

  /// The same tool call failed repeatedly with identical arguments and the loop
  /// gave up (the current `toolFailureCounts[key] >= 2` break — LL29's target).
  toolFailureAbort,

  /// A guardrail (e.g. release-approval, git-tag inspection) blocked the pending
  /// tool calls and ended the turn.
  guardrailBlock,

  /// The assistant asked the user to confirm before a write/destructive tool, so
  /// the loop intentionally stopped and rendered the question.
  userConfirmationBlock,

  /// The stream was cancelled mid-flight (user interrupt / new generation).
  streamingCancelled,

  /// The final answer was cut off at the provider's max-token limit.
  lengthTruncated,

  /// The turn ended with no usable text (empty or the `(empty)` sentinel).
  emptyResponse,

  /// The turn ended with a short, unterminated fragment (e.g. "The") — a
  /// truncated partial rather than a real short answer.
  partialFragment,

  /// Could not be classified — recorded so the log still carries a reason.
  unknown,
}

/// Terminal state of a finished tool-calling turn, as seen at finalization time.
class ToolLoopExitState {
  const ToolLoopExitState({
    required this.finalResponseText,
    this.explicitHint,
    this.finishReason,
    this.iteration = 0,
    this.maxIterations = 0,
    this.hadPendingToolCalls = false,
    this.lastMessageIsToolResult = false,
    this.lastToolName,
  });

  /// The visible assistant text for this turn (may be empty).
  final String finalResponseText;

  /// A reason set by the loop at a specific break site, when known. Takes
  /// priority over derivation so precise exits (max-iterations, tool-failure
  /// abort, guardrail/confirmation blocks, cancellation) are never mis-derived.
  final ToolLoopExitReason? explicitHint;

  /// Provider finish reason for the final completion (e.g. `length`, `stop`).
  final String? finishReason;

  final int iteration;
  final int maxIterations;

  /// True when the loop still had unprocessed tool calls when it stopped.
  final bool hadPendingToolCalls;

  /// True when the persisted turn ends on a tool result with no closing
  /// assistant message — the "agent just stops mid-work" shape worth a WARNING.
  final bool lastMessageIsToolResult;

  /// Name of the last tool call when [lastMessageIsToolResult] — for diagnostics.
  final String? lastToolName;
}

/// Pure classifier + completion explainer for tool-loop turn exits.
class ToolLoopExitClassifier {
  const ToolLoopExitClassifier();

  /// Max length of a final response still treated as a possible truncated
  /// fragment rather than a real short answer.
  static const int _partialFragmentMaxLength = 24;

  /// The terminal sentinel some recovery paths leave behind for an empty turn.
  static const String _emptySentinel = '(empty)';

  static const Set<String> _terminators = <String>{
    '.', '!', '?', '。', '！', '？', '`', ')', '）', '"', '”', ':',
  };

  /// Finish reasons that mean the answer was cut at the token limit.
  static const Set<String> _truncatedFinishReasons = <String>{
    'length',
    'max_tokens',
    'max_output_tokens',
  };

  /// Derive the exit reason from the terminal [state].
  ///
  /// Precedence: an [ToolLoopExitState.explicitHint] always wins. Otherwise the
  /// reason is derived from finish reason, iteration count, and the content
  /// shape, so even an unwired call site still records something useful.
  ToolLoopExitReason classify(ToolLoopExitState state) {
    if (state.explicitHint != null) {
      return state.explicitHint!;
    }

    final text = state.finalResponseText.trim();

    if (_isTruncated(state.finishReason)) {
      return ToolLoopExitReason.lengthTruncated;
    }
    if (text.isEmpty || text == _emptySentinel) {
      return ToolLoopExitReason.emptyResponse;
    }
    if (state.maxIterations > 0 &&
        state.iteration >= state.maxIterations &&
        state.hadPendingToolCalls) {
      return ToolLoopExitReason.maxIterations;
    }
    if (_looksLikePartialFragment(text)) {
      return ToolLoopExitReason.partialFragment;
    }
    return ToolLoopExitReason.textResponse;
  }

  /// True when the turn ended without a genuinely usable reply, so the explainer
  /// should run. Healthy short answers (a terse "Done.") are intentionally left
  /// alone — only empty/sentinel content and unterminated fragments qualify.
  bool shouldExplain(ToolLoopExitReason reason, String finalResponseText) {
    final text = finalResponseText.trim();
    final isEmptyTerminal = text.isEmpty || text == _emptySentinel;
    if (isEmptyTerminal) {
      return true;
    }
    // A non-empty answer is only "incomplete" when it reads like a truncated
    // partial; a real short answer keeps its text untouched.
    return reason != ToolLoopExitReason.textResponse &&
        _looksLikePartialFragment(text);
  }

  /// A single user-visible sentence explaining an abnormal/capped exit, or
  /// `null` when the turn completed normally (so terse answers stay silent).
  String? completionExplanation(ToolLoopExitReason reason) {
    switch (reason) {
      case ToolLoopExitReason.textResponse:
        return null;
      case ToolLoopExitReason.maxIterations:
        return 'I stopped because the turn reached its tool-call limit before '
            'finishing. Ask me to continue and I will pick up where I left off.';
      case ToolLoopExitReason.toolFailureAbort:
        return 'I stopped because a tool kept failing the same way. Tell me how '
            "you'd like to proceed, or share more detail about the blocker.";
      case ToolLoopExitReason.guardrailBlock:
        return 'I paused before running a tool that needs a closer look. Review '
            'the request above and confirm how you want me to continue.';
      case ToolLoopExitReason.userConfirmationBlock:
        return 'I paused for your confirmation before making a change. Let me '
            'know whether to go ahead.';
      case ToolLoopExitReason.streamingCancelled:
        return 'The response was interrupted before it finished.';
      case ToolLoopExitReason.lengthTruncated:
        return 'The response was cut off at the length limit, so it may be '
            'incomplete. Ask me to continue for the rest.';
      case ToolLoopExitReason.emptyResponse:
        return 'I stopped without producing an answer this turn. Please try '
            'again, or rephrase what you need.';
      case ToolLoopExitReason.partialFragment:
        return 'The response stopped partway through. Ask me to continue to '
            'finish it.';
      case ToolLoopExitReason.unknown:
        return 'I stopped before finishing this turn. Ask me to continue.';
    }
  }

  /// Stable lowercase token used in session-log diagnostics, e.g.
  /// `max_iterations`, `tool_failure_abort`.
  String logToken(ToolLoopExitReason reason) {
    switch (reason) {
      case ToolLoopExitReason.textResponse:
        return 'text_response';
      case ToolLoopExitReason.maxIterations:
        return 'max_iterations';
      case ToolLoopExitReason.toolFailureAbort:
        return 'tool_failure_abort';
      case ToolLoopExitReason.guardrailBlock:
        return 'guardrail_block';
      case ToolLoopExitReason.userConfirmationBlock:
        return 'user_confirmation_block';
      case ToolLoopExitReason.streamingCancelled:
        return 'streaming_cancelled';
      case ToolLoopExitReason.lengthTruncated:
        return 'length_truncated';
      case ToolLoopExitReason.emptyResponse:
        return 'empty_response';
      case ToolLoopExitReason.partialFragment:
        return 'partial_fragment';
      case ToolLoopExitReason.unknown:
        return 'unknown';
    }
  }

  /// True when the turn stopped mid-work — the last persisted message is a tool
  /// result with no closing assistant text. Callers log this at WARNING so the
  /// session-log triage tooling can find "agent appears stuck" turns.
  bool isMidWorkStop(ToolLoopExitState state) {
    return state.lastMessageIsToolResult;
  }

  bool _isTruncated(String? finishReason) {
    if (finishReason == null) {
      return false;
    }
    return _truncatedFinishReasons.contains(finishReason.trim().toLowerCase());
  }

  /// A short, non-empty answer with no sentence-ending punctuation reads like a
  /// truncated partial (the "The" case) rather than a real short reply.
  bool _looksLikePartialFragment(String trimmedText) {
    if (trimmedText.isEmpty || trimmedText.length > _partialFragmentMaxLength) {
      return false;
    }
    final lastChar = trimmedText.substring(trimmedText.length - 1);
    return !_terminators.contains(lastChar);
  }
}
