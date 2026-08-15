import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/local_llm_health.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/local_llm_health_service.dart';

void main() {
  const service = LocalLlmHealthService();
  DateTime clock() => DateTime.utc(2026, 8, 15, 18);

  Future<LocalLlmHealthSnapshot> probe({
    required Future<List<String>> Function() listModelIds,
    required Future<LocalModelLifecycleCatalog> Function() listManagedModels,
  }) {
    return service.probe(
      endpointId: 'studio',
      label: 'Studio Box',
      baseUrl: 'http://192.168.0.10:1234/v1',
      isPrimary: true,
      listModelIds: listModelIds,
      listManagedModels: listManagedModels,
      clock: clock,
    );
  }

  test('reports the loaded models a lifecycle-aware server names', () async {
    final snapshot = await probe(
      listModelIds: () async => ['loaded-model', 'idle-model'],
      listManagedModels: () async => const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'loaded-model',
            state: LocalModelLifecycleState.loaded,
            statusValue: 'loaded',
          ),
          LocalManagedModel(
            id: 'idle-model',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    expect(snapshot.isOnline, isTrue);
    expect(snapshot.modelEvidence, LocalLlmModelEvidence.loaded);
    expect(snapshot.modelIds, ['loaded-model']);
    expect(snapshot.checkedAt, clock());
  });

  test('an unreachable endpoint is a result, not an error', () async {
    final snapshot = await probe(
      listModelIds: () async => throw Exception('Connection refused'),
      listManagedModels: () async =>
          fail('liveness must be decided before asking for models'),
    );

    expect(snapshot.isOnline, isFalse);
    expect(snapshot.modelIds, isEmpty);
    expect(snapshot.modelEvidence, LocalLlmModelEvidence.none);
    expect(snapshot.detail, contains('Connection refused'));
  });

  test('falls back to advertised models without a lifecycle API', () async {
    // A single-model llama.cpp process serves one model and exposes no
    // lifecycle endpoint; reporting nothing there would read as "idle".
    final snapshot = await probe(
      listModelIds: () async => ['gemma-4-31b'],
      listManagedModels: () async =>
          const LocalModelLifecycleCatalog.unsupported(
            message: 'No lifecycle API',
          ),
    );

    expect(snapshot.isOnline, isTrue);
    expect(snapshot.modelEvidence, LocalLlmModelEvidence.advertised);
    expect(snapshot.modelIds, ['gemma-4-31b']);
  });

  test('a lifecycle failure does not demote a reachable server', () async {
    final snapshot = await probe(
      listModelIds: () async => ['gemma-4-31b'],
      listManagedModels: () async => throw Exception('lifecycle 500'),
    );

    expect(snapshot.isOnline, isTrue);
    expect(snapshot.modelEvidence, LocalLlmModelEvidence.advertised);
    expect(snapshot.detail, contains('lifecycle 500'));
  });

  test('an online server with nothing loaded reports no models', () async {
    final snapshot = await probe(
      listModelIds: () async => ['idle-model'],
      listManagedModels: () async => const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'idle-model',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    expect(snapshot.isOnline, isTrue);
    expect(snapshot.hasModels, isFalse);
    expect(snapshot.modelEvidence, LocalLlmModelEvidence.none);
  });
}
