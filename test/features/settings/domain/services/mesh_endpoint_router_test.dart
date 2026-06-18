import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';

NamedEndpoint _endpoint(
  String baseUrl, {
  String apiKey = '',
  bool enabled = true,
}) => NamedEndpoint(
  id: NamedEndpoint.buildId(baseUrl),
  baseUrl: baseUrl,
  apiKey: apiKey,
  enabled: enabled,
).normalizedForPersistence();

void main() {
  const router = MeshEndpointRouter();
  const primaryBaseUrl = 'http://localhost:1234/v1';
  const primaryApiKey = 'primary-key';

  ResolvedEndpoint resolve({
    required List<NamedEndpoint> endpoints,
    required String requestedEndpointId,
    String model = 'role-model',
    Set<String> unhealthy = const {},
  }) => router.resolve(
    primaryBaseUrl: primaryBaseUrl,
    primaryApiKey: primaryApiKey,
    endpoints: endpoints,
    requestedEndpointId: requestedEndpointId,
    model: model,
    unhealthyEndpointIds: unhealthy,
  );

  group('MeshEndpointRouter.resolve', () {
    test('uses the primary endpoint when no endpoint is requested', () {
      final resolved = resolve(endpoints: const [], requestedEndpointId: '');
      expect(resolved.isPrimary, isTrue);
      expect(resolved.demotedToPrimary, isFalse);
      expect(resolved.baseUrl, primaryBaseUrl);
      expect(resolved.apiKey, primaryApiKey);
      expect(resolved.model, 'role-model');
    });

    test('routes to a healthy registered endpoint', () {
      final endpoint = _endpoint('http://192.168.100.241:1234/v1', apiKey: 'k');
      final resolved = resolve(
        endpoints: [endpoint],
        requestedEndpointId: endpoint.id,
      );
      expect(resolved.isPrimary, isFalse);
      expect(resolved.demotedToPrimary, isFalse);
      expect(resolved.endpointId, endpoint.id);
      expect(resolved.baseUrl, 'http://192.168.100.241:1234/v1');
      expect(resolved.apiKey, 'k');
    });

    test('demotes to primary when the requested endpoint is unhealthy', () {
      final endpoint = _endpoint('http://192.168.100.241:1234/v1');
      final resolved = resolve(
        endpoints: [endpoint],
        requestedEndpointId: endpoint.id,
        unhealthy: {endpoint.id},
      );
      expect(resolved.isPrimary, isTrue);
      expect(resolved.demotedToPrimary, isTrue);
      expect(resolved.baseUrl, primaryBaseUrl);
    });

    test('demotes to primary when the requested endpoint is missing', () {
      final resolved = resolve(
        endpoints: const [],
        requestedEndpointId: 'http://10.0.0.9:1234/v1',
      );
      expect(resolved.demotedToPrimary, isTrue);
      expect(resolved.baseUrl, primaryBaseUrl);
    });

    test('demotes to primary when the requested endpoint is disabled', () {
      final endpoint = _endpoint(
        'http://192.168.100.241:1234/v1',
        enabled: false,
      );
      final resolved = resolve(
        endpoints: [endpoint],
        requestedEndpointId: endpoint.id,
      );
      expect(resolved.demotedToPrimary, isTrue);
      expect(resolved.isPrimary, isTrue);
    });
  });

  group('EndpointHealthTracker', () {
    test('unknown endpoints are healthy until probed', () {
      final tracker = EndpointHealthTracker();
      expect(tracker.isUnhealthy('x'), isFalse);
      expect(tracker.unhealthyEndpointIds, isEmpty);
    });

    test('marks unhealthy after the failure threshold', () {
      final tracker = EndpointHealthTracker(failureThreshold: 2);
      tracker.recordFailure('x');
      expect(tracker.isUnhealthy('x'), isFalse);
      tracker.recordFailure('x');
      expect(tracker.isUnhealthy('x'), isTrue);
      expect(tracker.unhealthyEndpointIds, {'x'});
    });

    test('a success resets the failure streak', () {
      final tracker = EndpointHealthTracker(failureThreshold: 2);
      tracker.recordFailure('x');
      tracker.recordFailure('x');
      expect(tracker.isUnhealthy('x'), isTrue);

      tracker.recordSuccess('x');
      expect(tracker.isUnhealthy('x'), isFalse);
      expect(tracker.healthFor('x').consecutiveFailures, 0);
      expect(tracker.healthFor('x').lastSuccessAt, isNotNull);
    });

    test('forget clears tracked state', () {
      final tracker = EndpointHealthTracker(failureThreshold: 1);
      tracker.recordFailure('x');
      expect(tracker.isUnhealthy('x'), isTrue);
      tracker.forget('x');
      expect(tracker.isUnhealthy('x'), isFalse);
    });

    test('drives router demotion end to end', () {
      final tracker = EndpointHealthTracker(failureThreshold: 1);
      final endpoint = _endpoint('http://192.168.100.241:1234/v1');
      tracker.recordFailure(endpoint.id);

      final resolved = resolve(
        endpoints: [endpoint],
        requestedEndpointId: endpoint.id,
        unhealthy: tracker.unhealthyEndpointIds,
      );
      expect(resolved.demotedToPrimary, isTrue);
    });
  });
}
