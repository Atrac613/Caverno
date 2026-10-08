/// What one model on one endpoint has shown about its context window, learned
/// from ordinary requests instead of a probe or a published table.
///
/// [provenPromptTokens] is the largest prompt the endpoint accepted, so the
/// window is at least that large. [failedPromptTokens] is the smallest prompt
/// it rejected for length, and [reportedLimitTokens] the limit its error named,
/// when it named one. Either bounds the window from above.
final class ContextWindowObservation {
  const ContextWindowObservation({
    this.provenPromptTokens = 0,
    this.failedPromptTokens,
    this.reportedLimitTokens,
    this.budgetScale = 1,
  });

  final int provenPromptTokens;
  final int? failedPromptTokens;
  final int? reportedLimitTokens;

  /// The tool-result budget multiplier learned for a window nobody reported:
  /// raised by [scaleStep] after an accepted request whose tool results the
  /// budget had to shorten, halved by a length rejection.
  final double budgetScale;

  static const double scaleStep = 0.5;
  static const double maxBudgetScale = 4;

  /// The tightest known upper bound, or null when nothing has failed yet.
  int? get ceilingTokens => switch ((reportedLimitTokens, failedPromptTokens)) {
    (final int reported, _) => reported,
    (null, final int failed) => failed,
    (null, null) => null,
  };

  /// Records an accepted prompt; null when it proves nothing new. A request
  /// that fit although the budget [pressured] its tool results earns room.
  ContextWindowObservation? accept(int promptTokens, {bool pressured = false}) {
    final proven = promptTokens > provenPromptTokens
        ? promptTokens
        : provenPromptTokens;
    final scale = pressured
        ? (budgetScale + scaleStep).clamp(1.0, maxBudgetScale)
        : budgetScale;
    if (proven == provenPromptTokens && scale == budgetScale) return null;
    return _copy(proven: proven, scale: scale);
  }

  ContextWindowObservation _copy({
    int? proven,
    int? failed,
    int? reported,
    double? scale,
  }) => ContextWindowObservation(
    provenPromptTokens: proven ?? provenPromptTokens,
    failedPromptTokens: failed ?? failedPromptTokens,
    reportedLimitTokens: reported ?? reportedLimitTokens,
    budgetScale: scale ?? budgetScale,
  );

  /// Records a prompt rejected for length; null when it proves nothing new.
  ContextWindowObservation? reject({int? promptTokens, int? reportedLimit}) {
    final failed = promptTokens == null || promptTokens <= 0
        ? failedPromptTokens
        : failedPromptTokens == null || promptTokens < failedPromptTokens!
        ? promptTokens
        : failedPromptTokens;
    final reported = reportedLimit != null && reportedLimit > 0
        ? reportedLimit
        : reportedLimitTokens;
    final scale = (budgetScale / 2).clamp(1.0, maxBudgetScale);
    if (failed == failedPromptTokens &&
        reported == reportedLimitTokens &&
        scale == budgetScale) {
      return null;
    }
    return _copy(failed: failed, reported: reported, scale: scale);
  }

  Map<String, Object?> toJson() => {
    'provenPromptTokens': provenPromptTokens,
    if (failedPromptTokens != null) 'failedPromptTokens': failedPromptTokens,
    if (reportedLimitTokens != null) 'reportedLimitTokens': reportedLimitTokens,
    if (budgetScale != 1) 'budgetScale': budgetScale,
  };

  static ContextWindowObservation fromJson(Map<String, Object?> json) {
    int? read(String key) => switch (json[key]) {
      final int value when value > 0 => value,
      _ => null,
    };
    return ContextWindowObservation(
      provenPromptTokens: read('provenPromptTokens') ?? 0,
      failedPromptTokens: read('failedPromptTokens'),
      reportedLimitTokens: read('reportedLimitTokens'),
      budgetScale: switch (json['budgetScale']) {
        final num value when value >= 1 => value.toDouble().clamp(
          1.0,
          maxBudgetScale,
        ),
        _ => 1,
      },
    );
  }

  /// One endpoint-and-model pair, the unit a context window belongs to.
  static String keyFor({required String baseUrl, required String model}) =>
      '${baseUrl.trim().toLowerCase()}|${model.trim().toLowerCase()}';
}
