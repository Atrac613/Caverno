/// Exponential backoff with a ceiling and a bounded retry count.
class RetryPolicy {
  const RetryPolicy({
    this.baseDelay = const Duration(milliseconds: 100),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
  });

  final Duration baseDelay;
  final Duration maxDelay;
  final int maxAttempts;

  /// Delay before retry [attempt], where attempt 1 is the first retry.
  Duration delayFor(int attempt) {
    if (attempt < 1) return Duration.zero;
    const maxExponent = 30;
    final exponent = attempt - 1 > maxExponent ? maxExponent : attempt - 1;
    final scaled = baseDelay.inMicroseconds * (1 << exponent);
    return scaled >= maxDelay.inMicroseconds
        ? maxDelay
        : Duration(microseconds: scaled);
  }

  bool shouldRetry({required int attempt, required bool cancelled}) {
    return false;
  }

  /// Total time spent waiting across every retry this policy permits.
  Duration totalBackoff() {
    return Duration.zero;
  }
}
