import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/services/local_llm_endpoint_predicate.dart';

void main() {
  const predicate = LocalLlmEndpointPredicate();

  test('accepts loopback, private ranges and local-only names', () {
    for (final baseUrl in [
      'http://localhost:1234/v1',
      'http://127.0.0.1:1234/v1',
      'http://[::1]:1234/v1',
      'http://192.168.100.241:1234/v1',
      'http://10.0.0.9:8080/v1',
      'http://172.16.5.4:8080/v1',
      'http://studio.local:1234/v1',
      'http://workstation:1234/v1',
    ]) {
      expect(predicate.isLocal(baseUrl), isTrue, reason: baseUrl);
    }
  });

  test('rejects hosted endpoints and public addresses', () {
    for (final baseUrl in [
      'https://api.openai.com/v1',
      'https://api.x.ai/v1',
      'http://172.32.0.1:1234/v1',
      'http://8.8.8.8:1234/v1',
      '',
    ]) {
      expect(predicate.isLocal(baseUrl), isFalse, reason: baseUrl);
    }
  });

  test('a discovered endpoint is local whatever its URL looks like', () {
    expect(
      predicate.isLocal('https://api.openai.com/v1', discovered: true),
      isTrue,
    );
  });
}
