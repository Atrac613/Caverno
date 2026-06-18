import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/core/services/lan_endpoint_discovery.dart';

String _modelsBody(List<String> ids) => jsonEncode({
  'object': 'list',
  'data': [
    for (final id in ids) {'id': id, 'object': 'model'},
  ],
});

void main() {
  group('LanEndpointDiscovery.probe', () {
    test('returns an endpoint with model ids on a valid /v1/models', () async {
      late Uri sentUri;
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async {
          sentUri = request.url;
          return http.Response(
            _modelsBody(['qwen3.6-35b', 'qwen3-embed']),
            200,
          );
        }),
      );

      final endpoint = await discovery.probe(
        host: '192.168.100.241',
        port: 1234,
      );

      expect(endpoint, isNotNull);
      expect(sentUri.toString(), 'http://192.168.100.241:1234/v1/models');
      expect(endpoint!.modelIds, ['qwen3.6-35b', 'qwen3-embed']);
      expect(endpoint.baseUrl, 'http://192.168.100.241:1234/v1');
      expect(endpoint.serverHint, 'LM Studio');
      expect(endpoint.responseMs, greaterThanOrEqualTo(0));
    });

    test('never sends an Authorization header to an unverified host', () async {
      String? authHeader;
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async {
          authHeader = request.headers['Authorization'];
          return http.Response(_modelsBody(const ['m']), 200);
        }),
      );

      await discovery.probe(host: '10.0.0.5', port: 8080);

      expect(authHeader, isNull);
    });

    test('returns null on a non-2xx response', () async {
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async => http.Response('nope', 404)),
      );
      expect(await discovery.probe(host: '10.0.0.5', port: 1234), isNull);
    });

    test('returns null on a non-OpenAI body', () async {
      final discovery = LanEndpointDiscovery(
        client: MockClient(
          (request) async => http.Response('<html>hi</html>', 200),
        ),
      );
      expect(await discovery.probe(host: '10.0.0.5', port: 80), isNull);
    });

    test('returns null on a network error', () async {
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async => throw const SocketishError()),
      );
      expect(await discovery.probe(host: '10.0.0.5', port: 1234), isNull);
    });

    test(
      'returns an empty model list when the server advertises none',
      () async {
        final discovery = LanEndpointDiscovery(
          client: MockClient(
            (request) async => http.Response(_modelsBody([]), 200),
          ),
        );
        final endpoint = await discovery.probe(host: '10.0.0.5', port: 8000);
        expect(endpoint, isNotNull);
        expect(endpoint!.modelIds, isEmpty);
        expect(endpoint.serverHint, 'OpenAI-compatible');
      },
    );

    test('rejects an out-of-range port without a request', () async {
      var called = false;
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async {
          called = true;
          return http.Response(_modelsBody(const ['m']), 200);
        }),
      );
      expect(await discovery.probe(host: '10.0.0.5', port: 70000), isNull);
      expect(called, isFalse);
    });

    test('brackets an IPv6 host in the probe URL', () async {
      late Uri sentUri;
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async {
          sentUri = request.url;
          return http.Response(_modelsBody(const ['m']), 200);
        }),
      );
      final endpoint = await discovery.probe(host: 'fd00::1', port: 1234);
      expect(sentUri.toString(), 'http://[fd00::1]:1234/v1/models');
      expect(endpoint!.baseUrl, 'http://[fd00::1]:1234/v1');
    });
  });

  group('LanEndpointDiscovery.discover', () {
    test('probes host x port combos and returns reachable, sorted', () async {
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async {
          // Only one specific host:port answers; everything else 404s.
          if (request.url.host == '192.168.100.241' &&
              request.url.port == 1234) {
            return http.Response(_modelsBody(const ['qwen3.6-35b']), 200);
          }
          return http.Response('nope', 404);
        }),
      );

      final endpoints = await discovery.discover(
        hosts: ['192.168.100.241', '192.168.100.10'],
      );

      expect(endpoints, hasLength(1));
      expect(endpoints.single.host, '192.168.100.241');
      expect(endpoints.single.port, 1234);
    });

    test('honors explicit ports over the known-port defaults', () async {
      final probedPorts = <int>{};
      final discovery = LanEndpointDiscovery(
        client: MockClient((request) async {
          probedPorts.add(request.url.port);
          return http.Response('nope', 404);
        }),
      );

      await discovery.discover(hosts: ['10.0.0.5'], ports: [9999]);

      expect(probedPorts, {9999});
    });
  });
}

/// A throwing exception type to simulate a network failure in MockClient.
class SocketishError implements Exception {
  const SocketishError();
}
