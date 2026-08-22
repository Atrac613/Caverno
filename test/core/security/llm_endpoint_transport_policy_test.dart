import 'package:caverno/core/security/llm_endpoint_transport_policy.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_discovery.dart';
import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_transport.dart';
import 'package:caverno/features/settings/data/model_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = LlmEndpointTransportPolicy();

  test('allows HTTPS endpoints with credentials', () {
    expect(
      policy.validate(baseUrl: 'https://api.example.com/v1', apiKey: 'secret'),
      'https://api.example.com/v1',
    );
  });

  test('allows plaintext loopback endpoints with credentials', () {
    for (final baseUrl in <String>[
      'http://localhost:1234/v1',
      'http://worker.localhost:1234/v1',
      'http://127.0.0.1:1234/v1',
      'http://[::1]:1234/v1',
    ]) {
      expect(
        policy.validate(baseUrl: baseUrl, apiKey: 'secret'),
        baseUrl,
        reason: baseUrl,
      );
    }
  });

  test('allows credentialless plaintext LAN endpoints', () {
    for (final apiKey in <String>['', 'no-key']) {
      expect(
        policy.validate(
          baseUrl: 'http://192.168.100.241:1234/v1',
          apiKey: apiKey,
        ),
        'http://192.168.100.241:1234/v1',
      );
    }
  });

  test('rejects credentials on plaintext non-loopback endpoints', () {
    for (final baseUrl in <String>[
      'http://192.168.100.241:1234/v1',
      'http://10.0.0.4:1234/v1',
      'http://api.example.com/v1',
    ]) {
      expect(
        () => policy.validate(baseUrl: baseUrl, apiKey: 'secret'),
        throwsA(isA<LlmEndpointTransportException>()),
        reason: baseUrl,
      );
    }
  });

  test('rejects unsupported or malformed endpoint URLs', () {
    for (final baseUrl in <String>[
      'api.example.com/v1',
      'ftp://localhost/v1',
    ]) {
      expect(
        () => policy.validate(baseUrl: baseUrl, apiKey: 'no-key'),
        throwsA(isA<LlmEndpointTransportException>()),
        reason: baseUrl,
      );
    }
  });

  test('all LLM HTTP client boundaries reject insecure credentials', () {
    const baseUrl = 'http://192.168.100.241:1234/v1';
    const apiKey = 'secret';
    final constructors = <Object? Function()>[
      () => ChatRemoteDataSource(baseUrl: baseUrl, apiKey: apiKey),
      () => ModelRemoteDataSource(baseUrl: baseUrl, apiKey: apiKey),
      () => EmbeddingsClient(baseUrl: baseUrl, apiKey: apiKey),
      () => LlamaCppSlotDiscovery(baseUrl: baseUrl, apiKey: apiKey),
      () => LlamaCppSlotTransport(baseUrl: baseUrl, apiKey: apiKey),
    ];

    for (final construct in constructors) {
      expect(construct, throwsA(isA<LlmEndpointTransportException>()));
    }
  });
}
