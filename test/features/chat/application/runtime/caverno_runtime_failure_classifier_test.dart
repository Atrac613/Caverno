import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/application/runtime/caverno_runtime_failure_classifier.dart';

void main() {
  const classifier = CavernoRuntimeFailureClassifier();

  test('maps transport failures to service unavailable', () {
    for (final error in const [
      'SocketException: Failed host lookup',
      'Connection refused by the endpoint',
      'Request timed out',
      'HTTP 503 Service Unavailable',
    ]) {
      final result = classifier.classify(error);
      expect(result.code, 'service_unavailable');
      expect(result.exitCode, 69);
    }
  });

  test('maps persistence failures to the stable persistence exit code', () {
    final result = classifier.classify('HiveError: disk full');

    expect(result.code, 'persistence_failed');
    expect(result.exitCode, 74);
  });

  test('keeps ordinary turn failures blocked', () {
    final result = classifier.classify('The response could not be parsed');

    expect(result.code, 'turn_failed');
    expect(result.exitCode, 2);
  });
}
