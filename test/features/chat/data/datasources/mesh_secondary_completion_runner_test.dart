import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';

/// Identifies which endpoint a call landed on, plus the model requested.
class _Call {
  const _Call(this.tag, this.model);
  final String tag;
  final String model;
}

NamedEndpoint _endpoint(String baseUrl, {bool enabled = true}) => NamedEndpoint(
  id: NamedEndpoint.buildId(baseUrl),
  baseUrl: baseUrl,
  enabled: enabled,
).normalizedForPersistence();

void main() {
  const primaryBaseUrl = 'http://localhost:1234/v1';
  const primaryApiKey = 'primary';

  MeshSecondaryCompletionRunner<_FakeDataSource> buildRunner(
    EndpointHealthTracker health, {
    void Function(String baseUrl)? onBuild,
    bool failMesh = false,
  }) {
    return MeshSecondaryCompletionRunner<_FakeDataSource>(
      router: const MeshEndpointRouter(),
      health: health,
      // Data sources are opaque here; the closure tags them by base URL.
      buildEndpointDataSource: (baseUrl, apiKey) {
        onBuild?.call(baseUrl);
        return _FakeDataSource(baseUrl, fail: failMesh);
      },
    );
  }

  Future<_Call> run(
    MeshSecondaryCompletionRunner<_FakeDataSource> runner, {
    required List<NamedEndpoint> endpoints,
    required String endpointId,
    String model = 'role-model',
    String fallbackModel = 'primary-model',
  }) {
    return runner.run<_Call>(
      primary: _FakeDataSource('primary'),
      primaryBaseUrl: primaryBaseUrl,
      primaryApiKey: primaryApiKey,
      endpoints: endpoints,
      endpointId: endpointId,
      model: model,
      fallbackModel: fallbackModel,
      call: (dataSource, model) async {
        if (dataSource.fail) throw StateError('mesh call failed');
        return _Call(dataSource.tag, model);
      },
    );
  }

  test('routes to the primary endpoint when no endpoint is assigned', () async {
    final runner = buildRunner(EndpointHealthTracker());
    final result = await run(runner, endpoints: const [], endpointId: '');
    expect(result.tag, 'primary');
    expect(result.model, 'role-model');
  });

  test('routes to a healthy assigned endpoint', () async {
    final endpoint = _endpoint('http://192.168.100.241:1234/v1');
    final runner = buildRunner(EndpointHealthTracker());
    final result = await run(
      runner,
      endpoints: [endpoint],
      endpointId: endpoint.id,
    );
    expect(result.tag, 'http://192.168.100.241:1234/v1');
  });

  test('falls back to primary and demotes when the mesh call throws', () async {
    final endpoint = _endpoint('http://192.168.100.241:1234/v1');
    final health = EndpointHealthTracker(failureThreshold: 1);
    final runner = buildRunner(health, failMesh: true);

    final result = await run(
      runner,
      endpoints: [endpoint],
      endpointId: endpoint.id,
    );

    // The active turn still completed on the primary endpoint, using the
    // primary-valid fallback model (not the mesh-only role model)...
    expect(result.tag, 'primary');
    expect(result.model, 'primary-model');
    // ...and the endpoint is now demoted for the next call.
    expect(health.isUnhealthy(endpoint.id), isTrue);
  });

  test('skips an already-unhealthy endpoint without building it', () async {
    final endpoint = _endpoint('http://192.168.100.241:1234/v1');
    final health = EndpointHealthTracker(failureThreshold: 1)
      ..recordFailure(endpoint.id);
    final builtBaseUrls = <String>[];
    final runner = buildRunner(health, onBuild: builtBaseUrls.add);

    final result = await run(
      runner,
      endpoints: [endpoint],
      endpointId: endpoint.id,
    );

    expect(result.tag, 'primary');
    // A pre-emptively demoted endpoint also uses the primary fallback model.
    expect(result.model, 'primary-model');
    expect(builtBaseUrls, isEmpty);
  });

  test('demotes immediately on an unambiguous connectivity failure', () async {
    final endpoint = _endpoint('http://192.168.100.241:1234/v1');
    final health = EndpointHealthTracker(failureThreshold: 2);
    final runner = MeshSecondaryCompletionRunner<_FakeDataSource>(
      router: const MeshEndpointRouter(),
      health: health,
      buildEndpointDataSource: (baseUrl, apiKey) => _FakeDataSource(baseUrl),
    );

    final result = await runner.run<_Call>(
      primary: _FakeDataSource('primary'),
      primaryBaseUrl: primaryBaseUrl,
      primaryApiKey: primaryApiKey,
      endpoints: [endpoint],
      endpointId: endpoint.id,
      model: 'role-model',
      fallbackModel: 'primary-model',
      call: (dataSource, model) async {
        if (!dataSource.tag.startsWith('primary')) {
          throw Exception(
            'ClientException with SocketException: Connection refused '
            '(OS Error: Connection refused, errno = 61)',
          );
        }
        return _Call(dataSource.tag, model);
      },
    );

    expect(result.tag, 'primary');
    // A single hard failure demotes the endpoint despite threshold 2.
    expect(health.isUnhealthy(endpoint.id), isTrue);
  });

  test('keeps a flapping endpoint eligible after one soft failure', () async {
    final endpoint = _endpoint('http://192.168.100.241:1234/v1');
    final health = EndpointHealthTracker(failureThreshold: 2);
    final runner = buildRunner(health, failMesh: true);

    await run(runner, endpoints: [endpoint], endpointId: endpoint.id);

    // A single ambiguous failure (StateError) is below threshold 2.
    expect(health.isUnhealthy(endpoint.id), isFalse);
  });

  group('isHardEndpointFailure', () {
    test('classifies connectivity failures as hard', () {
      expect(
        MeshSecondaryCompletionRunner.isHardEndpointFailure(
          Exception('SocketException: Connection refused (errno = 61)'),
        ),
        isTrue,
      );
      expect(
        MeshSecondaryCompletionRunner.isHardEndpointFailure(
          Exception('Failed host lookup: mesh.local'),
        ),
        isTrue,
      );
    });

    test('treats ambiguous failures as soft', () {
      expect(
        MeshSecondaryCompletionRunner.isHardEndpointFailure(
          StateError('mesh call failed'),
        ),
        isFalse,
      );
      expect(
        MeshSecondaryCompletionRunner.isHardEndpointFailure(
          Exception('TimeoutException after 0:00:30'),
        ),
        isFalse,
      );
    });
  });

  test('caches the data source for repeated calls to one endpoint', () async {
    final endpoint = _endpoint('http://192.168.100.241:1234/v1');
    final builtBaseUrls = <String>[];
    final runner = buildRunner(
      EndpointHealthTracker(),
      onBuild: builtBaseUrls.add,
    );

    await run(runner, endpoints: [endpoint], endpointId: endpoint.id);
    await run(runner, endpoints: [endpoint], endpointId: endpoint.id);

    expect(builtBaseUrls, ['http://192.168.100.241:1234/v1']);
  });
}

/// Minimal opaque stand-in for a ChatDataSource; the runner never inspects it.
class _FakeDataSource {
  _FakeDataSource(this.tag, {this.fail = false});
  final String tag;
  final bool fail;
}
