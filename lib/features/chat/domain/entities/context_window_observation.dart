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
  });

  final int provenPromptTokens;
  final int? failedPromptTokens;
  final int? reportedLimitTokens;

  /// The tightest known upper bound, or null when nothing has failed yet.
  int? get ceilingTokens => switch ((reportedLimitTokens, failedPromptTokens)) {
    (final int reported, _) => reported,
    (null, final int failed) => failed,
    (null, null) => null,
  };

  /// Records an accepted prompt; null when it proves nothing new.
  ContextWindowObservation? accept(int promptTokens) =>
      promptTokens > provenPromptTokens
      ? ContextWindowObservation(
          provenPromptTokens: promptTokens,
          failedPromptTokens: failedPromptTokens,
          reportedLimitTokens: reportedLimitTokens,
        )
      : null;

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
    if (failed == failedPromptTokens && reported == reportedLimitTokens) {
      return null;
    }
    return ContextWindowObservation(
      provenPromptTokens: provenPromptTokens,
      failedPromptTokens: failed,
      reportedLimitTokens: reported,
    );
  }

  Map<String, Object?> toJson() => {
    'provenPromptTokens': provenPromptTokens,
    if (failedPromptTokens != null) 'failedPromptTokens': failedPromptTokens,
    if (reportedLimitTokens != null) 'reportedLimitTokens': reportedLimitTokens,
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
    );
  }

  /// One endpoint-and-model pair, the unit a context window belongs to.
  static String keyFor({required String baseUrl, required String model}) =>
      '${baseUrl.trim().toLowerCase()}|${model.trim().toLowerCase()}';
}
