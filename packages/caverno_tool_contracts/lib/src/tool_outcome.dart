/// Structured outcome a first-party tool reports about its own execution.
///
/// Tool results travel as an opaque `result` string plus a coarse success
/// flag, so every consumer that needs a fact about what happened re-derives it
/// by parsing that string. `ToolFailureClassifier`, the workflow failure
/// detector, and the coding output guardrail each decode the same JSON
/// independently, and phrases in tool output end up load-bearing.
///
/// A `ToolOutcome` carries those facts alongside the string instead. The
/// string stays authoritative for the model — this is what the *harness*
/// reads.
///
/// Only fields a tool genuinely knows belong here. A tool that cannot
/// determine its own outcome reports nothing rather than a guessed value: a
/// fabricated fact is worse than an absent one, because consumers are entitled
/// to trust what they find.
///
/// Fields are added alongside the producer and consumer that need them, so an
/// outcome never carries a field nothing populates. See LL34 in
/// `docs/local_llm_agent_roadmap.md`.
class ToolOutcome {
  const ToolOutcome({this.exitCode});

  /// Process exit status for tools that run a command.
  ///
  /// `0` means the command ran and succeeded; a non-zero value means it ran
  /// and failed. `null` means the tool does not run commands, or the process
  /// never reached an exit (it was denied, timed out, or failed to spawn) —
  /// those are distinct from a failing exit status and must not be flattened
  /// into one.
  final int? exitCode;

  /// Whether this outcome carries any fact at all.
  ///
  /// An outcome with nothing populated is equivalent to no outcome, and
  /// consumers should fall back to their existing text handling.
  bool get isEmpty => exitCode == null;

  bool get isNotEmpty => !isEmpty;

  /// Whether a command ran to completion and reported failure.
  ///
  /// False when no command ran, so a caller cannot mistake "no exit status"
  /// for success.
  bool get hasFailingExitCode => exitCode != null && exitCode != 0;

  /// Whether a command ran to completion and reported success.
  bool get hasSucceedingExitCode => exitCode == 0;

  Map<String, dynamic> toJson() => {
    if (exitCode != null) 'exit_code': exitCode,
  };

  static ToolOutcome? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final rawExitCode = json['exit_code'];
    final outcome = ToolOutcome(
      exitCode: rawExitCode is num ? rawExitCode.toInt() : null,
    );
    return outcome.isEmpty ? null : outcome;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolOutcome && other.exitCode == exitCode;

  @override
  int get hashCode => exitCode.hashCode;

  @override
  String toString() => 'ToolOutcome(exitCode: $exitCode)';
}
