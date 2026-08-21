import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/core/services/lan_endpoint_discovery.dart';
import 'package:caverno/features/onboarding/domain/services/local_llm_autodetect_service.dart';

String _modelsBody(List<String> ids) => jsonEncode({
  'object': 'list',
  'data': [
    for (final id in ids) {'id': id, 'object': 'model'},
  ],
});

void main() {
  group('LocalLlmAutodetectService.probeLoopback', () {
    test('finds the one loopback port that answers', () async {
      final probed = <String>[];
      final service = LocalLlmAutodetectService(
        LanEndpointDiscovery(
          client: MockClient((request) async {
            probed.add('${request.url.host}:${request.url.port}');
            if (request.url.port == 1234) {
              return http.Response(_modelsBody(['qwen3.6-35b']), 200);
            }
            return http.Response('not found', 404);
          }),
        ),
      );

      final endpoints = await service.probeLoopback();

      expect(endpoints, hasLength(1));
      expect(endpoints.single.baseUrl, 'http://127.0.0.1:1234/v1');
      expect(endpoints.single.serverHint, 'LM Studio');
      expect(endpoints.single.modelIds, ['qwen3.6-35b']);
      // Every known port is tried, and only loopback is contacted — the whole
      // point of the cheap first pass is that it never touches the network.
      expect(probed, hasLength(LanEndpointDiscovery.knownPorts.length));
      expect(probed.every((target) => target.startsWith('127.0.0.1:')), isTrue);
    });

    test('reports nothing running as an empty list, not an error', () async {
      final service = LocalLlmAutodetectService(
        LanEndpointDiscovery(
          client: MockClient((_) async => throw const _Unreachable()),
        ),
      );

      expect(await service.probeLoopback(), isEmpty);
    });

    test('sorts multiple hits fastest first', () async {
      final service = LocalLlmAutodetectService(
        LanEndpointDiscovery(
          client: MockClient((request) async {
            if (request.url.port == 11434) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return http.Response(_modelsBody(['llama3']), 200);
            }
            if (request.url.port == 1234) {
              return http.Response(_modelsBody(['qwen3.6-35b']), 200);
            }
            return http.Response('not found', 404);
          }),
        ),
      );

      final endpoints = await service.probeLoopback();

      expect(endpoints.map((e) => e.port), [1234, 11434]);
    });
  });
}

class _Unreachable implements Exception {
  const _Unreachable();
}
