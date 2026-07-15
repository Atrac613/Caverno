final class CavernoRuntimeFailureClassification {
  const CavernoRuntimeFailureClassification({
    required this.code,
    required this.exitCode,
  });

  final String code;
  final int exitCode;
}

final class CavernoRuntimeFailureClassifier {
  const CavernoRuntimeFailureClassifier();

  CavernoRuntimeFailureClassification classify(String error) {
    final normalized = error.toLowerCase();
    if (_containsAny(normalized, const <String>[
      'failed host lookup',
      'socketexception',
      'connection refused',
      'connection reset',
      'timed out',
      'timeout',
      'service unavailable',
      'bad gateway',
      'gateway timeout',
      'http 502',
      'http 503',
      'http 504',
    ])) {
      return const CavernoRuntimeFailureClassification(
        code: 'service_unavailable',
        exitCode: 69,
      );
    }
    if (_containsAny(normalized, const <String>[
      'hiveerror',
      'databaseexception',
      'database is locked',
      'disk full',
      'no space left on device',
      'session log write',
    ])) {
      return const CavernoRuntimeFailureClassification(
        code: 'persistence_failed',
        exitCode: 74,
      );
    }
    return const CavernoRuntimeFailureClassification(
      code: 'turn_failed',
      exitCode: 2,
    );
  }

  bool _containsAny(String value, Iterable<String> candidates) {
    return candidates.any(value.contains);
  }
}
