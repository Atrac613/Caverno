/// Outcome of the shared high-risk tool-approval gate.
///
/// The gate collapses the three permission modes (default / auto-review /
/// full access) into a single decision that every tool handler can switch on,
/// regardless of whether the tool is a coding write, a browser action, or a
/// device/remote connection.
enum ToolApprovalGateOutcome {
  /// Run the tool immediately without any prompt (full access, or auto-review
  /// allowed the action).
  runDirectly,

  /// Auto-review rejected the action; surface [ToolApprovalGateDecision.deniedRationale]
  /// to the model instead of executing.
  denied,

  /// Fall back to the handler's existing interactive approval flow (default
  /// mode, or auto-review was unavailable).
  needsManualApproval,
}

/// Result of [ChatNotifier]'s shared approval gate. Use the const [fullAccess]
/// / [autoReviewAllowed] / [needsManualApproval] singletons, or
/// [ToolApprovalGateDecision.denied] to carry the reviewer's rationale.
class ToolApprovalGateDecision {
  const ToolApprovalGateDecision._(
    this.outcome, {
    this.deniedRationale,
    this.bypassedApproval = false,
  });

  final ToolApprovalGateOutcome outcome;

  /// Reviewer rationale; non-null only when [outcome] is
  /// [ToolApprovalGateOutcome.denied].
  final String? deniedRationale;

  /// True when full access ran the tool with no approval step at all. Callers
  /// use this to SKIP per-turn result caching, so repeated identical calls
  /// re-execute (e.g. re-running tests after an edit) instead of returning a
  /// stale cached result. Auto-review / manual approvals still cache, so the
  /// model is not re-prompted for an action the user already cleared.
  final bool bypassedApproval;

  /// Ran directly via full access — no approval step occurred.
  static const ToolApprovalGateDecision fullAccess = ToolApprovalGateDecision._(
    ToolApprovalGateOutcome.runDirectly,
    bypassedApproval: true,
  );

  /// Ran directly because auto-review allowed it (an approval decision was made).
  static const ToolApprovalGateDecision autoReviewAllowed =
      ToolApprovalGateDecision._(ToolApprovalGateOutcome.runDirectly);

  static const ToolApprovalGateDecision needsManualApproval =
      ToolApprovalGateDecision._(ToolApprovalGateOutcome.needsManualApproval);

  factory ToolApprovalGateDecision.denied(String rationale) =>
      ToolApprovalGateDecision._(
        ToolApprovalGateOutcome.denied,
        deniedRationale: rationale,
      );

  bool get runsDirectly => outcome == ToolApprovalGateOutcome.runDirectly;

  bool get isDenied => outcome == ToolApprovalGateOutcome.denied;

  bool get needsManual => outcome == ToolApprovalGateOutcome.needsManualApproval;
}
