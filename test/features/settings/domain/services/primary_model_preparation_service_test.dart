import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/primary_model_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrimaryModelPreparationService', () {
    test('loads an unloaded OpenAI-compatible primary model', () async {
      final loadedModelIds = <String>[];
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          expect(refresh, isTrue);
          return const LocalModelLifecycleCatalog.supported(
            models: [
              LocalManagedModel(
                id: 'qwen3.6-35b-a3b-vision',
                state: LocalModelLifecycleState.unloaded,
                statusValue: 'unloaded',
              ),
            ],
          );
        },
        loadManagedModel: (modelId) async {
          loadedModelIds.add(modelId);
          return LocalModelLifecycleActionResult.success(
            message: 'Requested load for "$modelId".',
          );
        },
        unloadManagedModel: (modelId) async {
          fail('Expected no unload request for $modelId.');
        },
      );

      final outcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(
          model: 'qwen3.6-35b-a3b-vision',
        ),
        refreshCatalog: true,
      );

      expect(outcome.status, PrimaryModelPreparationStatus.loadStarted);
      expect(outcome.attemptedLoad, isTrue);
      expect(loadedModelIds, ['qwen3.6-35b-a3b-vision']);
    });

    test(
      'unloads previous model and confirms before loading next model',
      () async {
        final operations = <String>[];
        final service = PrimaryModelPreparationService(
          listManagedModels: ({bool refresh = false}) async {
            operations.add('list:$refresh');
            return const LocalModelLifecycleCatalog.supported(
              models: [
                LocalManagedModel(
                  id: 'qwen3.6-27b-mtp-vision',
                  state: LocalModelLifecycleState.unloaded,
                  statusValue: 'unloaded',
                ),
                LocalManagedModel(
                  id: 'qwen3.6-35b-a3b-vision',
                  state: LocalModelLifecycleState.unloaded,
                  statusValue: 'unloaded',
                ),
              ],
            );
          },
          unloadManagedModel: (modelId) async {
            operations.add('unload:$modelId');
            return LocalModelLifecycleActionResult.success(
              message: 'Requested unload for "$modelId".',
            );
          },
          loadManagedModel: (modelId) async {
            operations.add('load:$modelId');
            return LocalModelLifecycleActionResult.success(
              message: 'Requested load for "$modelId".',
            );
          },
        );

        final outcome = await service.preparePrimaryModel(
          settings: AppSettings.defaults().copyWith(
            model: 'qwen3.6-35b-a3b-vision',
          ),
          previousPrimaryModelId: 'qwen3.6-27b-mtp-vision',
        );

        expect(outcome.status, PrimaryModelPreparationStatus.loadStarted);
        expect(outcome.previousModelId, 'qwen3.6-27b-mtp-vision');
        expect(outcome.attemptedUnload, isTrue);
        expect(outcome.previousModelUnloadConfirmed, isTrue);
        expect(outcome.attemptedLoad, isTrue);
        expect(operations, [
          'unload:qwen3.6-27b-mtp-vision',
          'list:true',
          'load:qwen3.6-35b-a3b-vision',
        ]);
      },
    );

    test('infers loaded previous model before loading next model', () async {
      final operations = <String>[];
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          operations.add('list:$refresh');
          final previousState =
              operations.contains('unload:qwen3.6-27b-mtp-vision')
              ? LocalModelLifecycleState.unloaded
              : LocalModelLifecycleState.loaded;
          return LocalModelLifecycleCatalog.supported(
            models: [
              LocalManagedModel(
                id: 'qwen3.6-27b-mtp-vision',
                state: previousState,
                statusValue: previousState.name,
              ),
              const LocalManagedModel(
                id: 'qwen3.6-35b-a3b-vision',
                state: LocalModelLifecycleState.unloaded,
                statusValue: 'unloaded',
              ),
            ],
          );
        },
        unloadManagedModel: (modelId) async {
          operations.add('unload:$modelId');
          return LocalModelLifecycleActionResult.success(
            message: 'Requested unload for "$modelId".',
          );
        },
        loadManagedModel: (modelId) async {
          operations.add('load:$modelId');
          return LocalModelLifecycleActionResult.success(
            message: 'Requested load for "$modelId".',
          );
        },
      );

      final outcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(
          model: 'qwen3.6-35b-a3b-vision',
        ),
      );

      expect(outcome.status, PrimaryModelPreparationStatus.loadStarted);
      expect(outcome.previousModelId, 'qwen3.6-27b-mtp-vision');
      expect(outcome.previousModelUnloadConfirmed, isTrue);
      expect(operations, [
        'list:false',
        'unload:qwen3.6-27b-mtp-vision',
        'list:true',
        'load:qwen3.6-35b-a3b-vision',
      ]);
    });

    test(
      'does not load next model until previous unload is confirmed',
      () async {
        final operations = <String>[];
        final service = PrimaryModelPreparationService(
          listManagedModels: ({bool refresh = false}) async {
            operations.add('list:$refresh');
            return const LocalModelLifecycleCatalog.supported(
              models: [
                LocalManagedModel(
                  id: 'qwen3.6-27b-mtp-vision',
                  state: LocalModelLifecycleState.loaded,
                  statusValue: 'loaded',
                ),
                LocalManagedModel(
                  id: 'qwen3.6-35b-a3b-vision',
                  state: LocalModelLifecycleState.unloaded,
                  statusValue: 'unloaded',
                ),
              ],
            );
          },
          unloadManagedModel: (modelId) async {
            operations.add('unload:$modelId');
            return LocalModelLifecycleActionResult.success(
              message: 'Requested unload for "$modelId".',
            );
          },
          loadManagedModel: (modelId) async {
            operations.add('load:$modelId');
            fail(
              'Expected no load request until previous unload is confirmed.',
            );
          },
        );

        final outcome = await service.preparePrimaryModel(
          settings: AppSettings.defaults().copyWith(
            model: 'qwen3.6-35b-a3b-vision',
          ),
          previousPrimaryModelId: 'qwen3.6-27b-mtp-vision',
        );

        expect(outcome.status, PrimaryModelPreparationStatus.failed);
        expect(outcome.attemptedUnload, isTrue);
        expect(outcome.previousModelUnloadConfirmed, isFalse);
        expect(outcome.attemptedLoad, isFalse);
        expect(operations, ['unload:qwen3.6-27b-mtp-vision', 'list:true']);
      },
    );

    test('does not load ready or in-progress models', () async {
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          return const LocalModelLifecycleCatalog.supported(
            models: [
              LocalManagedModel(
                id: 'ready-model',
                state: LocalModelLifecycleState.sleeping,
                statusValue: 'sleeping',
              ),
              LocalManagedModel(
                id: 'loading-model',
                state: LocalModelLifecycleState.loading,
                statusValue: 'loading',
              ),
            ],
          );
        },
        loadManagedModel: (modelId) async {
          fail('Expected no load request for $modelId.');
        },
        unloadManagedModel: (modelId) async {
          fail('Expected no unload request for $modelId.');
        },
      );

      final readyOutcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(model: 'ready-model'),
      );
      final loadingOutcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(model: 'loading-model'),
      );

      expect(readyOutcome.status, PrimaryModelPreparationStatus.ready);
      expect(loadingOutcome.status, PrimaryModelPreparationStatus.inProgress);
    });

    test('skips unsupported providers before catalog inspection', () async {
      var catalogInspected = false;
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          catalogInspected = true;
          return const LocalModelLifecycleCatalog.supported(models: []);
        },
        loadManagedModel: (modelId) async {
          fail('Expected no load request for $modelId.');
        },
        unloadManagedModel: (modelId) async {
          fail('Expected no unload request for $modelId.');
        },
      );

      final outcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(
          llmProvider: LlmProvider.appleFoundationModels,
        ),
      );

      expect(outcome.status, PrimaryModelPreparationStatus.skipped);
      expect(catalogInspected, isFalse);
    });

    test('treats missing and unsupported lifecycle data as no-op', () {
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          return const LocalModelLifecycleCatalog.supported(models: []);
        },
        loadManagedModel: (modelId) async {
          fail('Expected no load request for $modelId.');
        },
        unloadManagedModel: (modelId) async {
          fail('Expected no unload request for $modelId.');
        },
      );

      final missingPlan = service.buildPlan(
        modelId: 'missing-model',
        catalog: const LocalModelLifecycleCatalog.supported(models: []),
      );
      final unsupportedPlan = service.buildPlan(
        modelId: 'qwen3.6-27b-mtp-vision',
        catalog: const LocalModelLifecycleCatalog.unsupported(
          message: 'Lifecycle unsupported.',
        ),
      );

      expect(missingPlan.status, PrimaryModelPreparationStatus.missing);
      expect(unsupportedPlan.status, PrimaryModelPreparationStatus.unsupported);
      expect(missingPlan.shouldLoad, isFalse);
      expect(unsupportedPlan.shouldLoad, isFalse);
    });
  });
}
