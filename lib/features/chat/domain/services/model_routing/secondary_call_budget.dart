/// Output-token budget for secondary (utility) LLM calls.
///
/// Secondary calls — memory extraction, title/goal suggestion, workflow
/// planning, classifiers — need a fixed, adequate output budget that does NOT
/// track the user's chat `maxTokens`. Those call sites historically used
/// `min(userMaxTokens, ceiling)`, which has a ceiling but no floor: when a user
/// lowers their chat `maxTokens` (observed in a real session: 64), the utility
/// call inherits it and truncates its output (e.g. memory-extraction JSON cut
/// off mid-object, then discarded as invalid).
///
/// [resolve] keeps the per-call [ceiling] but adds a [floor] so a low user
/// setting can no longer starve the call. Normal users (high `maxTokens`) are
/// unaffected: the result is still the ceiling.
class SecondaryCallBudget {
  const SecondaryCallBudget._();

  /// Default minimum output budget for a secondary call. Large enough for a
  /// compact JSON object / short structured answer.
  static const int defaultFloorTokens = 512;

  /// Resolve the output budget for a secondary call.
  ///
  /// Returns [userMaxTokens] clamped to `[floor, ceiling]`, where `floor` is
  /// itself capped at [ceiling] so a small ceiling is never exceeded.
  static int resolve(
    int userMaxTokens,
    int ceiling, {
    int floor = defaultFloorTokens,
  }) {
    final effectiveFloor = floor < ceiling ? floor : ceiling;
    if (userMaxTokens < effectiveFloor) return effectiveFloor;
    if (userMaxTokens > ceiling) return ceiling;
    return userMaxTokens;
  }
}
