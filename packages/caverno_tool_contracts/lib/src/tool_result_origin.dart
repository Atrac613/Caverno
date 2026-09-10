/// Who authored a tool result payload for a call that never reached its tool.
///
/// Two very different things render identically today. When the harness
/// synthesizes feedback to steer its own loop -- "retry that through the
/// tool-aware continuation", "this result is identical to an earlier one" --
/// the payload is `{"ok": false, "code": ..., "error": ...}` with no `stdout`.
/// When a policy refuses a call the user's rules did not allow -- a production
/// release without approval, a git write through the local shell -- the payload
/// is `{"ok": false, "code": ..., "error": ...}` with no `stdout`. Nothing in
/// the shape says which happened.
///
/// That cost a measurement. HEU3 sized a command analogue of
/// `BlockedMutationNotice` at 22 of 715 turns; auditing the instrument
/// collapsed it to 3, because 19 of the 22 were harness-authored feedback
/// counted as refusals. Any rate gated on "the turn tried and was stopped" is
/// wrong by roughly 7x while the distinction lives only in a reader's
/// familiarity with the code strings. See `docs/text_heuristic_inventory.md`
/// and `caverno-triage-marker-transport-inflation`.
///
/// It also costs production code, quietly. Three separate call sites keep their
/// own hand-written list of "synthetic" codes -- in
/// `ConversationPlanExecutionGuardrails`, `ToolResultPromptBuilder` and
/// `MemoryExtractionDraftService` -- and the three lists already disagree with
/// each other and with the four codes HEU3 measured. A producer that declares
/// its own provenance cannot drift from a reader that asks for it.
///
/// Deliberately absent for results a tool actually produced: marking every
/// executing tool would be a far larger change for a distinction nobody is
/// confusing. An unmarked payload therefore means "not declared", never
/// "executed" -- the same rule `ToolOutcome` follows.
enum ToolResultOrigin {
  /// The harness wrote this payload to steer its own loop.
  ///
  /// No tool ran and no rule forbade one. The loop is telling the model
  /// something about the loop: retry this call properly, you already have this
  /// result, run a verifier before continuing. Counting these as refusals
  /// overstates how often the user's rules stopped anything.
  harness('harness'),

  /// A policy refused a call that was otherwise ready to run.
  ///
  /// No tool ran because a permission, scope or safety rule said no. This is
  /// the population "the turn attempted something and was stopped" means.
  refusal('refusal'),

  /// The tool could not accept the call as written.
  ///
  /// Nothing about authority: the arguments were the problem, and rewriting
  /// them is the whole remedy. `git_execute_command` refusing a piped command
  /// is the canonical case — git is never spawned, the model reissues the
  /// command with git's own filtering arguments, and the turn continues.
  ///
  /// Separate from [refusal] because the two answer different questions. A
  /// refusal rate says how often the user's rules stopped work; folding
  /// syntax retries into it inflates that rate with something no rule caused.
  /// The pipe rejection alone was the most frequent `git_execute_command`
  /// error in the twelve days to 2026-09-11 (7 of 109 results), so this is not
  /// a rounding error in either direction.
  ///
  /// Separate from "undeclared" because a producer exists and knows. Undeclared
  /// means a tool ran and failed on its own terms, with nobody to declare
  /// anything.
  malformed('malformed');

  const ToolResultOrigin(this.wireValue);

  /// The value written into the payload under [jsonKey].
  final String wireValue;

  /// The payload key producers write and readers parse.
  ///
  /// Kept next to the enum so the Python analysis tooling and the Dart
  /// producers cannot drift on the spelling; `tool/analyze_tool_results.py`
  /// reads the same string.
  static const String jsonKey = 'result_origin';

  /// Spread into a payload map literal: `...ToolResultOrigin.harness.marker`.
  Map<String, Object?> get marker => {jsonKey: wireValue};

  /// The origin a decoded payload declares, or null when it declares none.
  ///
  /// Null is "not declared". It must not be read as either value.
  static ToolResultOrigin? fromPayload(Map<String, Object?>? payload) {
    if (payload == null) return null;
    final raw = payload[jsonKey];
    if (raw is! String) return null;
    for (final origin in values) {
      if (origin.wireValue == raw) return origin;
    }
    return null;
  }
}
