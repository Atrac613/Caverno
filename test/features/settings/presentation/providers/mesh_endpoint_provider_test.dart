import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/core/services/lan_endpoint_discovery.dart';
import 'package:caverno/features/settings/presentation/providers/mesh_endpoint_provider.dart';

String _modelsBody(List<String> ids) => jsonEncode({
  'data': [
    for (final id in ids) {'id': id},
  ],
});

void main() {
  group('meshHostsFromScanJson', () {
    test('extracts host ips and ignores error payloads', () {
      expect(
        meshHostsFromScanJson(
          jsonEncode({
            'hosts': [
              {'ip': '192.168.100.241'},
              {'ip': '192.168.100.10'},
              {'no_ip': true},
            ],
          }),
        ),
        ['192.168.100.241', '192.168.100.10'],
      );
      expect(meshHostsFromScanJson(jsonEncode({'error': true})), isEmpty);
      expect(meshHostsFromScanJson('not json'), isEmpty);
    });
  });

  group('MeshDiscoveryNotifier', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(meshDiscoveryProvider).value, isEmpty);
    });

    test('scan verifies enumerated hosts and exposes endpoints', () async {
      final container = ProviderContainer(
        overrides: [
          meshHostEnumeratorProvider.overrideWithValue(
            () async => ['192.168.100.241', '192.168.100.10'],
          ),
          lanEndpointDiscoveryProvider.overrideWithValue(
            LanEndpointDiscovery(
              client: MockClient((request) async {
                if (request.url.host == '192.168.100.241' &&
                    request.url.port == 1234) {
                  return http.Response(_modelsBody(const ['qwen3.6-35b']), 200);
                }
                return http.Response('nope', 404);
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(meshDiscoveryProvider.notifier).scan();

      final endpoints = container.read(meshDiscoveryProvider).value;
      expect(endpoints, hasLength(1));
      expect(endpoints!.single.host, '192.168.100.241');
      expect(endpoints.single.baseUrl, 'http://192.168.100.241:1234/v1');
    });

    test('scan with no hosts yields an empty result, not an error', () async {
      final container = ProviderContainer(
        overrides: [
          meshHostEnumeratorProvider.overrideWithValue(() async => <String>[]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(meshDiscoveryProvider.notifier).scan();

      final state = container.read(meshDiscoveryProvider);
      expect(state.hasError, isFalse);
      expect(state.value, isEmpty);
    });

    test('scan surfaces an enumerator failure as an error state', () async {
      final container = ProviderContainer(
        overrides: [
          meshHostEnumeratorProvider.overrideWithValue(
            () async => throw Exception('scan failed'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(meshDiscoveryProvider.notifier).scan();

      expect(container.read(meshDiscoveryProvider).hasError, isTrue);
    });
  });
}
