/// Exponential backoff with a ceiling and a bounded retry count.
class RetryPolicy {
  const RetryPolicy({
    this.baseDelay = const Duration(milliseconds: 100),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
  });

  final Duration baseDelay;
  final Duration maxDelay;

  /// Total attempts including the first, so `maxAttempts: 5` allows four
  /// retries after the initial try.
  final int maxAttempts;

  /// Delay before retry [attempt], where attempt 1 is the first retry.
  ///
  /// Doubles per attempt and never exceeds [maxDelay]. The shift is computed
  /// on a bounded exponent so a large attempt number cannot overflow into a
  /// negative or wrapped delay.
  Duration delayFor(int attempt) {
    if (attempt < 1) {
      return Duration.zero;
    }
    const maxExponent = 30;
    final exponent = attempt - 1 > maxExponent ? maxExponent : attempt - 1;
    final scaled = baseDelay.inMicroseconds * (1 << exponent);
    return scaled >= maxDelay.inMicroseconds
        ? maxDelay
        : Duration(microseconds: scaled);
  }

  bool shouldRetry({required int attempt, required bool cancelled}) {
    if (cancelled) {
      return false;
    }
    return attempt < maxAttempts;
  }

  /// Total time spent waiting across every retry this policy permits.
  Duration totalBackoff() {
    var total = Duration.zero;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      total += delayFor(attempt);
    }
    return total;
  }
}
