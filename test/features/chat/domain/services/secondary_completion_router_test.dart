import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/chat/domain/services/secondary_completion_router.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:test/test.dart';

void main() {
  group('SecondaryCompletionRouter', () {
    test('routes OpenAI-compatible work to an assigned endpoint', () async {
      final endpoint = _endpoint('mesh-a', 'http://mesh-a.test/v1');
      final fixture = _fixture();

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(
          enabledEndpoints: [endpoint],
          selectedEndpointId: endpoint.id,
        ),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('http://mesh-a.test/v1', 'role'));
    });

    test('uses primary for a non-compatible provider', () async {
      final endpoint = _endpoint('mesh-a', 'http://mesh-a.test/v1');
      final fixture = _fixture();

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(
          provider: LlmProvider.appleFoundationModels,
          enabledEndpoints: [endpoint],
          selectedEndpointId: endpoint.id,
        ),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('primary', 'role'));
      expect(fixture.builtEndpoints, isEmpty);
    });

    test('keeps the selected model for an empty endpoint', () async {
      final fixture = _fixture();

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('primary', 'role'));
    });

    test('uses the primary data source supplied to each invocation', () async {
      final fixture = _fixture();

      final first = await fixture.router.run(
        primaryDataSource: const _FakeDataSource('primary-a'),
        route: _route(),
        operation: _successfulOperation,
      );
      final second = await fixture.router.run(
        primaryDataSource: const _FakeDataSource('primary-b'),
        route: _route(),
        operation: _successfulOperation,
      );

      expect(first.dataSource, 'primary-a');
      expect(second.dataSource, 'primary-b');
    });

    test('substitutes the primary model for a missing endpoint', () async {
      final fixture = _fixture();

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(selectedEndpointId: 'missing'),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('primary', 'primary-model'));
    });

    test('falls back when the assigned endpoint is unhealthy', () async {
      final endpoint = _endpoint('mesh-a', 'http://mesh-a.test/v1');
      final health = EndpointHealthTracker(failureThreshold: 1)
        ..recordFailure(endpoint.id);
      final fixture = _fixture(health: health);

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(
          enabledEndpoints: [endpoint],
          selectedEndpointId: endpoint.id,
        ),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('primary', 'primary-model'));
      expect(fixture.builtEndpoints, isEmpty);
    });

    test('uses the explicit fallback model after a mesh call fails', () async {
      final endpoint = _endpoint('mesh-a', 'http://mesh-a.test/v1');
      final fixture = _fixture(failingEndpointId: endpoint.id);

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(
          enabledEndpoints: [endpoint],
          selectedEndpointId: endpoint.id,
          fallbackModel: 'safe-primary-model',
        ),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('primary', 'safe-primary-model'));
    });

    test('freezes the enabled endpoint snapshot', () async {
      final endpoint = _endpoint('mesh-a', 'http://mesh-a.test/v1');
      final endpoints = <LlmEndpoint>[endpoint];
      final route = _route(
        enabledEndpoints: endpoints,
        selectedEndpointId: endpoint.id,
      );
      endpoints.clear();
      final fixture = _fixture();

      final result = await fixture.router.run(
        primaryDataSource: fixture.primaryDataSource,
        route: route,
        operation: _successfulOperation,
      );

      expect(result.dataSource, 'http://mesh-a.test/v1');
      expect(
        () => route.enabledEndpoints.add(endpoint),
        throwsUnsupportedError,
      );
    });

    test('records planning route metadata for an assigned endpoint', () async {
      final endpoint = _endpoint('planner', 'http://planner.test/v1');
      final log = _RecordingLogPort();
      final fixture = _fixture(logPort: log);

      final result = await fixture.router.runPlanning(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(
          enabledEndpoints: [endpoint],
          selectedEndpointId: ' planner ',
          selectedModel: 'planning-model',
        ),
        operation: _successfulOperation,
      );

      expect(
        result,
        const _CompletionResult('http://planner.test/v1', 'planning-model'),
      );
      expect(log.attempts, hasLength(1));
      expect(log.attempts.single.model, 'planning-model');
      expect(log.attempts.single.endpoint, 'planner');
      expect(log.attempts.single.isFallback, isFalse);
    });

    test('records both planning attempts when mesh fallback runs', () async {
      final endpoint = _endpoint('planner', 'http://planner.test/v1');
      final log = _RecordingLogPort();
      final fixture = _fixture(failingEndpointId: endpoint.id, logPort: log);

      final result = await fixture.router.runPlanning(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(
          enabledEndpoints: [endpoint],
          selectedEndpointId: endpoint.id,
          selectedModel: 'planning-model',
        ),
        operation: _successfulOperation,
      );

      expect(result, const _CompletionResult('primary', 'primary-model'));
      expect(log.attempts, hasLength(2));
      expect(log.attempts.first.model, 'planning-model');
      expect(log.attempts.first.endpoint, 'planner');
      expect(log.attempts.first.isFallback, isFalse);
      expect(log.attempts.last.model, 'primary-model');
      expect(log.attempts.last.endpoint, 'planner');
      expect(log.attempts.last.isFallback, isTrue);
    });

    test('labels an unassigned planning route as primary', () async {
      final log = _RecordingLogPort();
      final fixture = _fixture(logPort: log);

      await fixture.router.runPlanning(
        primaryDataSource: fixture.primaryDataSource,
        route: _route(selectedEndpointId: '   '),
        operation: _successfulOperation,
      );

      expect(log.attempts.single.endpoint, 'primary');
      expect(log.attempts.single.isFallback, isFalse);
    });

    test(
      'does not let a planning log failure change route execution',
      () async {
        final endpoint = _endpoint('planner', 'http://planner.test/v1');
        final log = _ThrowingLogPort();
        final fixture = _fixture(logPort: log);

        final result = await fixture.router.runPlanning(
          primaryDataSource: fixture.primaryDataSource,
          route: _route(
            enabledEndpoints: [endpoint],
            selectedEndpointId: endpoint.id,
            selectedModel: 'planning-model',
          ),
          operation: _successfulOperation,
        );

        expect(
          result,
          const _CompletionResult('http://planner.test/v1', 'planning-model'),
        );
        expect(log.attempts, 1);
      },
    );

    test('propagates an operation failure on the primary route', () async {
      final fixture = _fixture();
      final error = StateError('primary completion failed');

      await expectLater(
        fixture.router.run<_CompletionResult>(
          primaryDataSource: fixture.primaryDataSource,
          route: _route(),
          operation: (_, _) => Future<_CompletionResult>.error(error),
        ),
        throwsA(same(error)),
      );
    });

    test(
      'propagates the primary error after a mesh fallback also fails',
      () async {
        final endpoint = _endpoint('mesh-a', 'http://mesh-a.test/v1');
        final fixture = _fixture();
        final attempts = <String>[];

        await expectLater(
          fixture.router.run<_CompletionResult>(
            primaryDataSource: fixture.primaryDataSource,
            route: _route(
              enabledEndpoints: [endpoint],
              selectedEndpointId: endpoint.id,
            ),
            operation: (dataSource, _) async {
              attempts.add(dataSource.tag);
              throw StateError('${dataSource.tag} completion failed');
            },
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'primary completion failed',
            ),
          ),
        );
        expect(attempts, ['http://mesh-a.test/v1', 'primary']);
      },
    );
  });

  test('callback log port forwards the exact metadata instance', () {
    SecondaryCompletionRouteMetadata? seen;
    final port = CallbackSecondaryCompletionLogPort((metadata) {
      seen = metadata;
    });
    const metadata = SecondaryCompletionRouteMetadata(
      model: 'planner',
      endpoint: 'mesh-a',
      isFallback: false,
    );

    port.recordPlanningAttempt(metadata);

    expect(seen, same(metadata));
  });
}

typedef _Fixture = ({
  SecondaryCompletionRouter<_FakeDataSource> router,
  _FakeDataSource primaryDataSource,
  List<String> builtEndpoints,
});

_Fixture _fixture({
  EndpointHealthTracker? health,
  String? failingEndpointId,
  SecondaryCompletionLogPort? logPort,
}) {
  final builtEndpoints = <String>[];
  final runner = MeshSecondaryCompletionRunner<_FakeDataSource>(
    router: const MeshEndpointRouter(),
    health: health ?? EndpointHealthTracker(),
    buildEndpointDataSource: (baseUrl, apiKey) {
      builtEndpoints.add(baseUrl);
      return _FakeDataSource(
        baseUrl,
        fail: baseUrl.contains(failingEndpointId ?? '\u0000'),
      );
    },
  );
  const primaryDataSource = _FakeDataSource('primary');
  return (
    router: SecondaryCompletionRouter(meshRunner: runner, logPort: logPort),
    primaryDataSource: primaryDataSource,
    builtEndpoints: builtEndpoints,
  );
}

SecondaryCompletionRouteSnapshot _route({
  LlmProvider provider = LlmProvider.openAiCompatible,
  List<LlmEndpoint> enabledEndpoints = const [],
  String selectedEndpointId = '',
  String selectedModel = 'role',
  String? fallbackModel,
}) {
  return SecondaryCompletionRouteSnapshot(
    provider: provider,
    primaryBaseUrl: 'http://primary.test/v1',
    primaryApiKey: 'primary-key',
    primaryModel: 'primary-model',
    enabledEndpoints: enabledEndpoints,
    selectedEndpointId: selectedEndpointId,
    selectedModel: selectedModel,
    fallbackModel: fallbackModel,
  );
}

LlmEndpoint _endpoint(String id, String baseUrl) {
  return LlmEndpoint(
    id: id,
    baseUrl: baseUrl,
    apiKey: '$id-key',
  ).normalizedForPersistence();
}

Future<_CompletionResult> _successfulOperation(
  _FakeDataSource dataSource,
  String model,
) async {
  if (dataSource.fail) {
    throw StateError('mesh endpoint failed');
  }
  return _CompletionResult(dataSource.tag, model);
}

final class _FakeDataSource {
  const _FakeDataSource(this.tag, {this.fail = false});

  final String tag;
  final bool fail;
}

final class _CompletionResult {
  const _CompletionResult(this.dataSource, this.model);

  final String dataSource;
  final String model;

  @override
  bool operator ==(Object other) {
    return other is _CompletionResult &&
        other.dataSource == dataSource &&
        other.model == model;
  }

  @override
  int get hashCode => Object.hash(dataSource, model);
}

final class _RecordingLogPort implements SecondaryCompletionLogPort {
  final List<SecondaryCompletionRouteMetadata> attempts = [];

  @override
  void recordPlanningAttempt(SecondaryCompletionRouteMetadata metadata) {
    attempts.add(metadata);
  }
}

final class _ThrowingLogPort implements SecondaryCompletionLogPort {
  int attempts = 0;

  @override
  void recordPlanningAttempt(SecondaryCompletionRouteMetadata metadata) {
    attempts += 1;
    throw StateError('planning log unavailable');
  }
}
